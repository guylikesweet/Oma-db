"""add sale_type (preorder / stock)

Revision ID: a9c3e5b7d201
Revises: f7a1c9e4b210
"""
from alembic import op
import sqlalchemy as sa

revision = "a9c3e5b7d201"
down_revision = "f7a1c9e4b210"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    cols = [c["name"] for c in sa.inspect(bind).get_columns("sales")]
    if "sale_type" not in cols:
        with op.batch_alter_table("sales", schema=None) as batch_op:
            batch_op.add_column(sa.Column("sale_type", sa.String(length=20), nullable=False, server_default="preorder"))


def downgrade():
    with op.batch_alter_table("sales", schema=None) as batch_op:
        batch_op.drop_column("sale_type")
