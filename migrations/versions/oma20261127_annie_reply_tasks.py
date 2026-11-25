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
    bind = op.get_bind()
    if not sa.inspect(bind).has_table("annie_reply_tasks"):
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
    indexes = {item["name"] for item in sa.inspect(bind).get_indexes("annie_reply_tasks")}
    if "ix_annie_reply_tasks_status" not in indexes:
        op.create_index("ix_annie_reply_tasks_status", "annie_reply_tasks", ["status"])
    if "ix_annie_reply_tasks_created_at" not in indexes:
        op.create_index("ix_annie_reply_tasks_created_at", "annie_reply_tasks", ["created_at"])


def downgrade():
    if sa.inspect(op.get_bind()).has_table("annie_reply_tasks"):
        op.drop_table("annie_reply_tasks")
