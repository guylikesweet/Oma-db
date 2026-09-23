"""add mobile sync change feed and API idempotency records

Revision ID: 7f0f6f0c8a21
Revises: ca10b49cd246
Create Date: 2026-09-23

"""
from alembic import op
import sqlalchemy as sa


revision = "7f0f6f0c8a21"
down_revision = "ca10b49cd246"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "sync_changes",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("entity", sa.String(length=80), nullable=False),
        sa.Column("entity_id", sa.Integer(), nullable=False),
        sa.Column("action", sa.String(length=20), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_sync_changes_id", "sync_changes", ["id"])

    op.create_table(
        "api_operations",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("operation_id", sa.String(length=64), nullable=False),
        sa.Column("operation_type", sa.String(length=80), nullable=False),
        sa.Column("status_code", sa.Integer(), nullable=False),
        sa.Column("response_json", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "operation_id", name="uq_api_operations_user_operation"),
    )
    op.create_index("ix_api_operations_user_id", "api_operations", ["user_id"])


def downgrade():
    op.drop_index("ix_api_operations_user_id", table_name="api_operations")
    op.drop_table("api_operations")
    op.drop_index("ix_sync_changes_id", table_name="sync_changes")
    op.drop_table("sync_changes")
