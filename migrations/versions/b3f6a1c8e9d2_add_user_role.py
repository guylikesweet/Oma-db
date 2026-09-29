"""add user role and is_primary_admin

Revision ID: b3f6a1c8e9d2
Revises: a9c3e5b7d201
"""
from alembic import op
import sqlalchemy as sa

revision = "b3f6a1c8e9d2"
down_revision = "a9c3e5b7d201"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    cols = [c["name"] for c in sa.inspect(bind).get_columns("users")]
    if "role" not in cols:
        with op.batch_alter_table("users", schema=None) as batch_op:
            batch_op.add_column(sa.Column("role", sa.String(length=20), nullable=False, server_default="staff"))
    if "is_primary_admin" not in cols:
        with op.batch_alter_table("users", schema=None) as batch_op:
            batch_op.add_column(sa.Column("is_primary_admin", sa.Boolean(), nullable=False, server_default=sa.false()))

    users = sa.table(
        "users",
        sa.column("id", sa.Integer),
        sa.column("role", sa.String),
        sa.column("is_primary_admin", sa.Boolean),
    )
    # The very first account ever created is the owner — promote it to admin
    # and mark it as the one account nobody can delete. Everyone else keeps
    # the "staff" default they just got above.
    first_id = bind.execute(sa.select(sa.func.min(users.c.id))).scalar()
    if first_id is not None:
        bind.execute(
            users.update()
            .where(users.c.id == first_id)
            .values(role="admin", is_primary_admin=True)
        )


def downgrade():
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.drop_column("is_primary_admin")
        batch_op.drop_column("role")
