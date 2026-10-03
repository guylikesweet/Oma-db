"""sale item line weight + per-kg shipping rate setting

Revision ID: e2a5b7d9c014
Revises: c8d1f4a7b930
"""
from alembic import op
import sqlalchemy as sa

revision = "e2a5b7d9c014"
down_revision = "c8d1f4a7b930"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("sale_items", sa.Column("line_weight_kg", sa.Numeric(12, 3), nullable=True))
    op.add_column(
        "app_settings",
        sa.Column("shipping_rate_per_kg", sa.Numeric(12, 2), nullable=False, server_default="1115"),
    )


def downgrade():
    op.drop_column("app_settings", "shipping_rate_per_kg")
    op.drop_column("sale_items", "line_weight_kg")
