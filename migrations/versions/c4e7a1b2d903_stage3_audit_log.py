"""stage 3 audit log

Revision ID: c4e7a1b2d903
Revises: a9c3e5b7d201
"""

from alembic import op
import sqlalchemy as sa


revision = "c4e7a1b2d903"
down_revision = "a9c3e5b7d201"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "audit_log",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("username", sa.String(length=80), nullable=True),
        sa.Column("action", sa.String(length=120), nullable=False),
        sa.Column("target_type", sa.String(length=80), nullable=True),
        sa.Column("target_id", sa.String(length=80), nullable=True),
        sa.Column("outcome", sa.String(length=30), nullable=False, server_default="success"),
        sa.Column("details_json", sa.Text(), nullable=True),
        sa.Column("ip_address", sa.String(length=64), nullable=True),
        sa.Column("user_agent", sa.String(length=500), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index(
        "ix_audit_log_created_at",
        "audit_log",
        ["created_at"],
    )
    op.create_index(
        "ix_audit_log_action",
        "audit_log",
        ["action"],
    )
    op.create_index(
        "ix_audit_log_user_id",
        "audit_log",
        ["user_id"],
    )


def downgrade():
    op.drop_index("ix_audit_log_user_id", table_name="audit_log")
    op.drop_index("ix_audit_log_action", table_name="audit_log")
    op.drop_index("ix_audit_log_created_at", table_name="audit_log")
    op.drop_table("audit_log")
