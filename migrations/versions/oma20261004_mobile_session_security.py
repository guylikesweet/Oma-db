"""add mobile session timeout, biometric credential and active user state

Revision ID: oma20261004
Revises: f7a1c9e4b210, 15266d7fb5f3
"""
from alembic import op
import sqlalchemy as sa

revision = "oma20261004"
down_revision = ("f7a1c9e4b210", "15266d7fb5f3")
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("users", sa.Column("biometric_credential_hash", sa.String(length=255), nullable=True))
    op.add_column("users", sa.Column("api_last_activity_at", sa.DateTime(), nullable=True))
    op.add_column(
        "users",
        sa.Column(
            "is_active",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
    )


def downgrade():
    op.drop_column("users", "is_active")
    op.drop_column("users", "api_last_activity_at")
    op.drop_column("users", "biometric_credential_hash")
