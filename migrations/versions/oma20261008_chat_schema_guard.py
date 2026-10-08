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

    if "chat_messages" not in inspector.get_table_names():
        # The normal chat migrations should create this table. Do not silently
        # fabricate a partial schema here; the missing table must be repaired
        # by the preceding chat migration chain.
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
