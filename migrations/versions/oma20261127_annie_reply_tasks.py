"""Add a durable queue for Annie's tagged chat replies.

Revision ID: oma20261127_annie_tasks
Revises: oma20261126_annie
"""
from alembic import op
import sqlalchemy as sa

revision = "oma20261127_annie_tasks"
down_revision = "oma20261126_annie"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "annie_reply_tasks",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("message_id", sa.Integer(), sa.ForeignKey("chat_messages.id", ondelete="CASCADE"), nullable=False, unique=True),
        sa.Column("asker_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="pending"),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("processed_at", sa.DateTime(), nullable=True),
        sa.Column("last_error", sa.Text(), nullable=True),
    )
    op.create_index("ix_annie_reply_tasks_status", "annie_reply_tasks", ["status"])
    op.create_index("ix_annie_reply_tasks_created_at", "annie_reply_tasks", ["created_at"])


def downgrade():
    op.drop_index("ix_annie_reply_tasks_created_at", table_name="annie_reply_tasks")
    op.drop_index("ix_annie_reply_tasks_status", table_name="annie_reply_tasks")
    op.drop_table("annie_reply_tasks")
