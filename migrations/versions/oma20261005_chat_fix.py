"""Reconcile the Team Chat database schema with the current models.

Revision ID: oma20261005_chat_fix
Revises: oma20261005_chat

This migration is intentionally defensive. The chat migration was already
marked as applied in some environments even though the physical database
schema was older. Reconcile the existing tables without deleting messages.
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


revision = "oma20261005_chat_fix"
down_revision = "oma20261005_chat"
branch_labels = None
depends_on = None


def _inspector():
    return inspect(op.get_bind())


def _table_exists(inspector, table_name):
    return table_name in inspector.get_table_names()


def _columns(inspector, table_name):
    return {column["name"] for column in inspector.get_columns(table_name)}


def _indexes(inspector, table_name):
    return {index["name"] for index in inspector.get_indexes(table_name)}


def _has_foreign_key(inspector, table_name, constrained_columns, referred_table):
    wanted = set(constrained_columns)
    for fk in inspector.get_foreign_keys(table_name):
        if (
            set(fk.get("constrained_columns") or []) == wanted
            and fk.get("referred_table") == referred_table
        ):
            return True
    return False


def _add_column_if_missing(inspector, table_name, column):
    if column.name not in _columns(inspector, table_name):
        op.add_column(table_name, column)
        inspector.clear_cache()


def _create_index_if_missing(inspector, table_name, index_name, columns):
    if index_name not in _indexes(inspector, table_name):
        op.create_index(index_name, table_name, columns)
        inspector.clear_cache()


def upgrade():
    inspector = _inspector()

    if not _table_exists(inspector, "chat_messages"):
        op.create_table(
            "chat_messages",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("sender_user_id", sa.Integer(), nullable=False),
            sa.Column("content", sa.Text(), nullable=False),
            sa.Column("original_content", sa.Text(), nullable=True),
            sa.Column("edited_at", sa.DateTime(), nullable=True),
            sa.Column("edited_by_user_id", sa.Integer(), nullable=True),
            sa.Column("deleted_at", sa.DateTime(), nullable=True),
            sa.Column("deleted_by_user_id", sa.Integer(), nullable=True),
            sa.Column("attachment_data", sa.LargeBinary(), nullable=True),
            sa.Column("attachment_mimetype", sa.String(50), nullable=True),
            sa.Column("attachment_filename", sa.String(255), nullable=True),
            sa.Column("attachment_created_at", sa.DateTime(), nullable=True),
            sa.Column("reply_to_id", sa.Integer(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(
                ["sender_user_id"],
                ["users.id"],
                ondelete="CASCADE",
            ),
            sa.ForeignKeyConstraint(
                ["edited_by_user_id"],
                ["users.id"],
                ondelete="SET NULL",
            ),
            sa.ForeignKeyConstraint(
                ["deleted_by_user_id"],
                ["users.id"],
                ondelete="SET NULL",
            ),
            sa.ForeignKeyConstraint(
                ["reply_to_id"],
                ["chat_messages.id"],
                ondelete="SET NULL",
            ),
            sa.PrimaryKeyConstraint("id"),
        )
        inspector.clear_cache()
    else:
        # The production failure showed that this table existed but was
        # missing columns that the current ChatMessage model selects.
        columns = _columns(inspector, "chat_messages")
        definitions = (
            sa.Column("original_content", sa.Text(), nullable=True),
            sa.Column("edited_at", sa.DateTime(), nullable=True),
            sa.Column("edited_by_user_id", sa.Integer(), nullable=True),
            sa.Column("deleted_at", sa.DateTime(), nullable=True),
            sa.Column("deleted_by_user_id", sa.Integer(), nullable=True),
            sa.Column("attachment_data", sa.LargeBinary(), nullable=True),
            sa.Column("attachment_mimetype", sa.String(50), nullable=True),
            sa.Column("attachment_filename", sa.String(255), nullable=True),
            sa.Column("attachment_created_at", sa.DateTime(), nullable=True),
            sa.Column("reply_to_id", sa.Integer(), nullable=True),
        )
        for column in definitions:
            if column.name not in columns:
                op.add_column("chat_messages", column)
                inspector.clear_cache()
                columns.add(column.name)

    inspector.clear_cache()
    _create_index_if_missing(
        inspector,
        "chat_messages",
        "ix_chat_messages_sender_user_id",
        ["sender_user_id"],
    )
    _create_index_if_missing(
        inspector,
        "chat_messages",
        "ix_chat_messages_reply_to_id",
        ["reply_to_id"],
    )
    _create_index_if_missing(
        inspector,
        "chat_messages",
        "ix_chat_messages_created_at",
        ["created_at"],
    )
    _create_index_if_missing(
        inspector,
        "chat_messages",
        "ix_chat_messages_edited_by_user_id",
        ["edited_by_user_id"],
    )
    _create_index_if_missing(
        inspector,
        "chat_messages",
        "ix_chat_messages_deleted_by_user_id",
        ["deleted_by_user_id"],
    )

    inspector.clear_cache()
    if not _has_foreign_key(
        inspector, "chat_messages", ["sender_user_id"], "users"
    ):
        op.create_foreign_key(
            "fk_chat_messages_sender_user_id",
            "chat_messages",
            "users",
            ["sender_user_id"],
            ["id"],
            ondelete="CASCADE",
        )
        inspector.clear_cache()

    if not _has_foreign_key(
        inspector, "chat_messages", ["edited_by_user_id"], "users"
    ):
        op.create_foreign_key(
            "fk_chat_messages_edited_by_user_id",
            "chat_messages",
            "users",
            ["edited_by_user_id"],
            ["id"],
            ondelete="SET NULL",
        )
        inspector.clear_cache()

    if not _has_foreign_key(
        inspector, "chat_messages", ["deleted_by_user_id"], "users"
    ):
        op.create_foreign_key(
            "fk_chat_messages_deleted_by_user_id",
            "chat_messages",
            "users",
            ["deleted_by_user_id"],
            ["id"],
            ondelete="SET NULL",
        )
        inspector.clear_cache()

    if not _has_foreign_key(
        inspector, "chat_messages", ["reply_to_id"], "chat_messages"
    ):
        op.create_foreign_key(
            "fk_chat_messages_reply_to_id",
            "chat_messages",
            "chat_messages",
            ["reply_to_id"],
            ["id"],
            ondelete="SET NULL",
        )
        inspector.clear_cache()

    inspector.clear_cache()
    if not _table_exists(inspector, "chat_reactions"):
        op.create_table(
            "chat_reactions",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("message_id", sa.Integer(), nullable=False),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("emoji", sa.String(32), nullable=False),
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
                "emoji",
                name="uq_chat_reaction_message_user_emoji",
            ),
        )
        inspector.clear_cache()
    else:
        reaction_columns = _columns(inspector, "chat_reactions")
        for column in (
            sa.Column("message_id", sa.Integer(), nullable=True),
            sa.Column("user_id", sa.Integer(), nullable=True),
            sa.Column("emoji", sa.String(32), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=True),
        ):
            if column.name not in reaction_columns:
                op.add_column("chat_reactions", column)
                inspector.clear_cache()

    inspector.clear_cache()
    _create_index_if_missing(
        inspector, "chat_reactions", "ix_chat_reactions_message_id", ["message_id"]
    )
    _create_index_if_missing(
        inspector, "chat_reactions", "ix_chat_reactions_user_id", ["user_id"]
    )

    inspector.clear_cache()
    if not _table_exists(inspector, "chat_mentions"):
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
        inspector.clear_cache()
    else:
        mention_columns = _columns(inspector, "chat_mentions")
        for column in (
            sa.Column("message_id", sa.Integer(), nullable=True),
            sa.Column("user_id", sa.Integer(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=True),
        ):
            if column.name not in mention_columns:
                op.add_column("chat_mentions", column)
                inspector.clear_cache()

    inspector.clear_cache()
    _create_index_if_missing(
        inspector, "chat_mentions", "ix_chat_mentions_message_id", ["message_id"]
    )
    _create_index_if_missing(
        inspector, "chat_mentions", "ix_chat_mentions_user_id", ["user_id"]
    )


def downgrade():
    # Do not remove or alter existing chat data during a rollback.
    # The corrective migration is intentionally forward-only for safety.
    pass
