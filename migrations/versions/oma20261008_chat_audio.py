"""add durable team-chat voice messages and send idempotency (defensive)

Revision ID: oma20261008_chat_audio
Revises: oma20261008_product_photos
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "oma20261008_chat_audio"
down_revision = "oma20261008_product_photos"
branch_labels = None
depends_on = None

def upgrade():
    bind = op.get_bind()
    inspector = inspect(bind)
    if "chat_messages" not in inspector.get_table_names():
        return

    existing = {c["name"] for c in inspector.get_columns("chat_messages")}
    definitions = (
        sa.Column("audio_data", sa.LargeBinary(), nullable=True),
        sa.Column("audio_mimetype", sa.String(length=50), nullable=True),
        sa.Column("audio_filename", sa.String(length=255), nullable=True),
        sa.Column("audio_created_at", sa.DateTime(), nullable=True),
        sa.Column("client_operation_id", sa.String(length=100), nullable=True),
    )
    for column in definitions:
        if column.name not in existing:
            op.add_column("chat_messages", column)
            existing.add(column.name)
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
    # Preserve production messages/audio during rollback.
    pass
