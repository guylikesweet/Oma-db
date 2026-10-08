"""add durable team-chat voice messages and send idempotency

Revision ID: oma20261008_chat_audio
Revises: oma20261008_product_photos
"""
from alembic import op
import sqlalchemy as sa

revision = "oma20261008_chat_audio"
down_revision = "oma20261008_product_photos"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("chat_messages", sa.Column("audio_data", sa.LargeBinary(), nullable=True))
    op.add_column("chat_messages", sa.Column("audio_mimetype", sa.String(length=50), nullable=True))
    op.add_column("chat_messages", sa.Column("audio_filename", sa.String(length=255), nullable=True))
    op.add_column("chat_messages", sa.Column("audio_created_at", sa.DateTime(), nullable=True))
    op.add_column("chat_messages", sa.Column("client_operation_id", sa.String(length=100), nullable=True))
    op.create_index("ix_chat_messages_client_operation_id", "chat_messages", ["client_operation_id"], unique=True)


def downgrade():
    op.drop_index("ix_chat_messages_client_operation_id", table_name="chat_messages")
    op.drop_column("chat_messages", "client_operation_id")
    op.drop_column("chat_messages", "audio_created_at")
    op.drop_column("chat_messages", "audio_filename")
    op.drop_column("chat_messages", "audio_mimetype")
    op.drop_column("chat_messages", "audio_data")
