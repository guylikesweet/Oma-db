"""mobile sync infrastructure

Revision ID: d4f2c7a91e60
Revises: ca10b49cd246
"""
from alembic import op
import sqlalchemy as sa

revision = "d4f2c7a91e60"
down_revision = "ca10b49cd246"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "mobile_operations",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("operation_id", sa.String(length=100), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("operation_type", sa.String(length=100), nullable=False),
        sa.Column("status", sa.String(length=30), nullable=False, server_default="processing"),
        sa.Column("response_code", sa.Integer(), nullable=True),
        sa.Column("response_json", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
        sa.UniqueConstraint("operation_id", name="uq_mobile_operations_operation_id"),
    )
    op.create_index("ix_mobile_operations_operation_id", "mobile_operations", ["operation_id"])

    op.create_table(
        "mobile_changes",
        sa.Column("sequence", sa.BigInteger(), autoincrement=True, primary_key=True),
        sa.Column("entity_type", sa.String(length=50), nullable=False),
        sa.Column("entity_id", sa.String(length=100), nullable=False),
        sa.Column("operation", sa.String(length=20), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_mobile_changes_entity_type", "mobile_changes", ["entity_type"])
    op.create_index("ix_mobile_changes_entity_id", "mobile_changes", ["entity_id"])
    op.create_index("ix_mobile_changes_created_at", "mobile_changes", ["created_at"])


def downgrade():
    op.drop_index("ix_mobile_changes_created_at", table_name="mobile_changes")
    op.drop_index("ix_mobile_changes_entity_id", table_name="mobile_changes")
    op.drop_index("ix_mobile_changes_entity_type", table_name="mobile_changes")
    op.drop_table("mobile_changes")
    op.drop_index("ix_mobile_operations_operation_id", table_name="mobile_operations")
    op.drop_table("mobile_operations")
