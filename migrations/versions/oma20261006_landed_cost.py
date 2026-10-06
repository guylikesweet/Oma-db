"""add landed cost and product pricing fields

Revision ID: oma20261006_landed_cost
Revises: oma20261005_profile
"""

from alembic import op
import sqlalchemy as sa


revision = "oma20261006_landed_cost"
down_revision = "oma20261005_profile"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("products", sa.Column("supplier_cost", sa.Numeric(12, 2), nullable=True, server_default="0"))
    op.add_column("products", sa.Column("inbound_shipping_cost", sa.Numeric(12, 2), nullable=True, server_default="0"))
    op.add_column("products", sa.Column("markup_percent", sa.Numeric(8, 2), nullable=True, server_default="0"))
    op.add_column("products", sa.Column("selling_price", sa.Numeric(12, 2), nullable=True, server_default="0"))

    # Existing product.cost historically represented supplier cost. Preserve it
    # as supplier_cost while retaining cost as the current COGS/landed-cost field.
    op.execute("UPDATE products SET supplier_cost = COALESCE(cost, 0) WHERE supplier_cost IS NULL OR supplier_cost = 0")


def downgrade():
    op.drop_column("products", "selling_price")
    op.drop_column("products", "markup_percent")
    op.drop_column("products", "inbound_shipping_cost")
    op.drop_column("products", "supplier_cost")
