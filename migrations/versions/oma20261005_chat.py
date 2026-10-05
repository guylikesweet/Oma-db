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

    op.add_column("chat_messages", sa.Column("original_content", sa.Text(), nullable=True))
    op.add_column("chat_messages", sa.Column("edited_at", sa.DateTime(), nullable=True))
    op.add_column("chat_messages", sa.Column("edited_by_user_id", sa.Integer(), nullable=True))
    op.add_column("chat_messages", sa.Column("deleted_at", sa.DateTime(), nullable=True))
    op.add_column("chat_messages", sa.Column("deleted_by_user_id", sa.Integer(), nullable=True))
    op.add_column("chat_messages", sa.Column("attachment_data", sa.LargeBinary(), nullable=True))
    op.add_column("chat_messages", sa.Column("attachment_mimetype", sa.String(50), nullable=True))
    op.add_column("chat_messages", sa.Column("attachment_filename", sa.String(255), nullable=True))
    op.add_column("chat_messages", sa.Column("attachment_created_at", sa.DateTime(), nullable=True))
    op.create_index("ix_chat_messages_edited_by_user_id", "chat_messages", ["edited_by_user_id"])
    op.create_index("ix_chat_messages_deleted_by_user_id", "chat_messages", ["deleted_by_user_id"])
    op.create_foreign_key("fk_chat_messages_edited_by_user_id", "chat_messages", "users", ["edited_by_user_id"], ["id"], ondelete="SET NULL")
    op.create_foreign_key("fk_chat_messages_deleted_by_user_id", "chat_messages", "users", ["deleted_by_user_id"], ["id"], ondelete="SET NULL")
    op.create_table(
        "chat_reactions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("message_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("emoji", sa.String(32), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["message_id"], ["chat_messages.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("message_id", "user_id", "emoji", name="uq_chat_reaction_message_user_emoji"),
    )
    op.create_index("ix_chat_reactions_message_id", "chat_reactions", ["message_id"])
    op.create_index("ix_chat_reactions_user_id", "chat_reactions", ["user_id"])

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

    op.drop_index("ix_chat_reactions_user_id", table_name="chat_reactions")
    op.drop_index("ix_chat_reactions_message_id", table_name="chat_reactions")
    op.drop_table("chat_reactions")

    op.drop_constraint("fk_chat_messages_deleted_by_user_id", "chat_messages", type_="foreignkey")
    op.drop_constraint("fk_chat_messages_edited_by_user_id", "chat_messages", type_="foreignkey")
    op.drop_index("ix_chat_messages_deleted_by_user_id", table_name="chat_messages")
    op.drop_index("ix_chat_messages_edited_by_user_id", table_name="chat_messages")
    op.drop_column("chat_messages", "attachment_created_at")
    op.drop_column("chat_messages", "attachment_filename")
    op.drop_column("chat_messages", "attachment_mimetype")
    op.drop_column("chat_messages", "attachment_data")
    op.drop_column("chat_messages", "deleted_by_user_id")
    op.drop_column("chat_messages", "deleted_at")
    op.drop_column("chat_messages", "edited_by_user_id")
    op.drop_column("chat_messages", "edited_at")
    op.drop_column("chat_messages", "original_content")

    op.drop_index("ix_chat_messages_created_at", table_name="chat_messages")
    op.drop_index("ix_chat_messages_reply_to_id", table_name="chat_messages")
    op.drop_index("ix_chat_messages_sender_user_id", table_name="chat_messages")
    op.drop_table("chat_messages")
