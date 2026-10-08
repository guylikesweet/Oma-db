"""Defensively reconcile chat/media columns with the current runtime model.

Some production databases can report an Alembic revision as applied while the
physical schema is missing columns (for example after an interrupted deploy or
a historical branch merge). This forward-only guard makes the current chat
read/write paths self-consistent without deleting existing data.
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "oma20261008_chat_schema_guard"
down_revision = "oma20261008_chat_audio"
branch_labels = None
depends_on = None


def _columns(inspector, table):
    return {c["name"] for c in inspector.get_columns(table)} if table in inspector.get_table_names() else set()


def upgrade():
    bind = op.get_bind()
    inspector = inspect(bind)

    chat_table_missing = "chat_messages" not in inspector.get_table_names()

    # Repair product pricing/media columns if a production database has
    # an Alembic revision recorded but an incomplete physical schema.
    if "products" in inspector.get_table_names():
        product_definitions = (
            sa.Column("supplier_cost", sa.Numeric(12, 2), nullable=True, server_default="0"),
            sa.Column("inbound_shipping_cost", sa.Numeric(12, 2), nullable=True, server_default="0"),
            sa.Column("markup_percent", sa.Numeric(8, 2), nullable=True, server_default="0"),
            sa.Column("selling_price", sa.Numeric(12, 2), nullable=True, server_default="0"),
            sa.Column("image_data", sa.LargeBinary(), nullable=True),
            sa.Column("image_mimetype", sa.String(50), nullable=True),
            sa.Column("image_filename", sa.String(255), nullable=True),
            sa.Column("image_updated_at", sa.DateTime(), nullable=True),
        )
        present_products = _columns(inspector, "products")
        for column in product_definitions:
            if column.name not in present_products:
                op.add_column("products", column)
                present_products.add(column.name)
                inspector.clear_cache()

    # Repair profile-photo columns used by authenticated profile/chat payloads.
    if "users" in inspector.get_table_names():
        user_definitions = (
            sa.Column("profile_photo_data", sa.LargeBinary(), nullable=True),
            sa.Column("profile_photo_mimetype", sa.String(50), nullable=True),
            sa.Column("profile_photo_updated_at", sa.DateTime(), nullable=True),
        )
        present_users = _columns(inspector, "users")
        for column in user_definitions:
            if column.name not in present_users:
                op.add_column("users", column)
                present_users.add(column.name)
                inspector.clear_cache()

    if chat_table_missing:
        # The normal chat migrations should create this table. Do not silently
        # fabricate a partial schema here; product/profile repairs above are
        # still valid even when the chat table needs a separate repair.
        return

    definitions = (
        sa.Column("audio_data", sa.LargeBinary(), nullable=True),
        sa.Column("audio_mimetype", sa.String(50), nullable=True),
        sa.Column("audio_filename", sa.String(255), nullable=True),
        sa.Column("audio_created_at", sa.DateTime(), nullable=True),
        sa.Column("client_operation_id", sa.String(100), nullable=True),
    )
    present = _columns(inspector, "chat_messages")
    for column in definitions:
        if column.name not in present:
            op.add_column("chat_messages", column)
            present.add(column.name)
            inspector.clear_cache()

    indexes = {i["name"] for i in inspector.get_indexes("chat_messages")}
    if "ix_chat_messages_client_operation_id" not in indexes:
        op.create_index(
            "ix_chat_messages_client_operation_id",
            "chat_messages",
            ["client_operation_id"],
            unique=True,
        )


def downgrade():
    # Forward-only production repair; never remove message/audio data.
    pass
