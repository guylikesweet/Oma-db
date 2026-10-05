"""Add team chat messages and mentions.

Revision ID: oma20261005_chat
Revises: oma20261004_final
"""

from alembic import op
import sqlalchemy as sa


revision = "oma20261005_chat"
down_revision = "oma20261004_final"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "chat_messages",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("sender_user_id", sa.Integer(), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("reply_to_id", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["sender_user_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["reply_to_id"],
            ["chat_messages.id"],
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_chat_messages_sender_user_id",
        "chat_messages",
        ["sender_user_id"],
    )
    op.create_index(
        "ix_chat_messages_reply_to_id",
        "chat_messages",
        ["reply_to_id"],
    )
    op.create_index(
        "ix_chat_messages_created_at",
        "chat_messages",
        ["created_at"],
    )

    op.create_table(
        "chat_mentions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("message_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["message_id"],
            ["chat_messages.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "message_id",
            "user_id",
            name="uq_chat_mention_message_user",
        ),
    )
    op.create_index(
        "ix_chat_mentions_message_id",
        "chat_mentions",
        ["message_id"],
    )
    op.create_index(
        "ix_chat_mentions_user_id",
        "chat_mentions",
        ["user_id"],
    )


def downgrade():
    op.drop_index("ix_chat_mentions_user_id", table_name="chat_mentions")
    op.drop_index("ix_chat_mentions_message_id", table_name="chat_mentions")
    op.drop_table("chat_mentions")

    op.drop_index("ix_chat_messages_created_at", table_name="chat_messages")
    op.drop_index("ix_chat_messages_reply_to_id", table_name="chat_messages")
    op.drop_index("ix_chat_messages_sender_user_id", table_name="chat_messages")
    op.drop_table("chat_messages")
