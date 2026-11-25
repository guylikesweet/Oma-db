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
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {column["name"] for column in inspector.get_columns("users")}
    if "is_system" not in columns:
        op.add_column(
            "users",
            sa.Column("is_system", sa.Boolean(), nullable=False, server_default=sa.false()),
        )
    indexes = {index["name"] for index in sa.inspect(bind).get_indexes("users")}
    if "ix_users_is_system" not in indexes:
        op.create_index("ix_users_is_system", "users", ["is_system"])
    op.execute(sa.text("""
        INSERT INTO users
            (username, password_hash, created_at, is_active, role, is_primary_admin, is_system)
        SELECT '__annie__', '!system-account-disabled!', CURRENT_TIMESTAMP,
               FALSE, 'staff', FALSE, TRUE
        WHERE NOT EXISTS (
            SELECT 1 FROM users WHERE username = '__annie__'
        )
    """))


def downgrade():
    op.execute(sa.text("DELETE FROM users WHERE username = '__annie__' AND is_system = TRUE"))
    op.drop_index("ix_users_is_system", table_name="users")
    op.drop_column("users", "is_system")
