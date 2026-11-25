"""Install Annie's non-login system identity for team chat.

Revision ID: oma20261126_annie
Revises: oma20261125_pay_small_small
"""
from alembic import op
import sqlalchemy as sa

revision = "oma20261126_annie"
down_revision = "oma20261125_pay_small_small"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "users",
        sa.Column("is_system", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.execute(sa.text("""
        INSERT INTO users
            (username, password_hash, created_at, is_active, role, is_primary_admin, is_system)
        SELECT '__annie__', '!system-account-disabled!', CURRENT_TIMESTAMP,
               FALSE, 'staff', FALSE, TRUE
        WHERE NOT EXISTS (
            SELECT 1 FROM users WHERE username = '__annie__'
        )
    """))
    op.create_index("ix_users_is_system", "users", ["is_system"])


def downgrade():
    op.execute(sa.text("DELETE FROM users WHERE username = '__annie__' AND is_system = TRUE"))
    op.drop_index("ix_users_is_system", table_name="users")
    op.drop_column("users", "is_system")
