"""initial schema

Revision ID: 54a715dce242
Revises: 
Create Date: 2026-09-18 07:28:53.987550

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '54a715dce242'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('users',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('username', sa.String(length=50), nullable=False),
        sa.Column('password_hash', sa.String(length=255), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('username'),
    )
    op.create_table('products',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('sku', sa.String(length=100), nullable=True),
        sa.Column('cost', sa.Numeric(precision=12, scale=2), nullable=True),
        sa.Column('length_cm', sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column('width_cm', sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column('height_cm', sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column('cbm', sa.Numeric(precision=12, scale=6),
                   sa.Computed('(COALESCE(length_cm,0) * COALESCE(width_cm,0) * COALESCE(height_cm,0) / 1000000.0)', persisted=True),
                   nullable=True),
        sa.Column('volumetric_kg', sa.Numeric(precision=12, scale=3),
                   sa.Computed('(COALESCE(length_cm,0) * COALESCE(width_cm,0) * COALESCE(height_cm,0) / 5000.0)', persisted=True),
                   nullable=True),
        sa.Column('actual_weight_kg', sa.Numeric(precision=10, scale=3), nullable=True),
        sa.Column('stock', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('sku'),
    )
    op.create_table('courier_rates',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('state', sa.String(length=100), nullable=False),
        sa.Column('rate_per_cbm', sa.Numeric(precision=12, scale=2), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('state'),
    )
    op.create_table('sales',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('sale_date', sa.Date(), nullable=True),
        sa.Column('customer_name', sa.String(length=255), nullable=True),
        sa.Column('customer_phone', sa.String(length=50), nullable=True),
        sa.Column('customer_address', sa.Text(), nullable=True),
        sa.Column('customer_state', sa.String(length=100), nullable=True),
        sa.Column('order_status', sa.String(length=50), nullable=True),
        sa.Column('subtotal_amount', sa.Numeric(precision=12, scale=2), nullable=True),
        sa.Column('estimated_shipping_cost', sa.Numeric(precision=12, scale=2), nullable=True),
        sa.Column('total_amount', sa.Numeric(precision=12, scale=2), nullable=True),
        sa.Column('profit', sa.Numeric(precision=12, scale=2), nullable=True),
        sa.Column('payment_status', sa.String(length=50), nullable=True),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_table('sale_items',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('sale_id', sa.Integer(), nullable=False),
        sa.Column('product_id', sa.Integer(), nullable=False),
        sa.Column('qty', sa.Integer(), nullable=False),
        sa.Column('unit_cost', sa.Numeric(precision=12, scale=2), nullable=True),
        sa.Column('unit_price', sa.Numeric(precision=12, scale=2), nullable=True),
        sa.Column('line_cbm', sa.Numeric(precision=12, scale=6), nullable=True),
        sa.Column('line_volumetric_kg', sa.Numeric(precision=12, scale=3), nullable=True),
        sa.Column('line_shipping_estimate', sa.Numeric(precision=12, scale=2), nullable=True),
        sa.ForeignKeyConstraint(['product_id'], ['products.id'], ),
        sa.ForeignKeyConstraint(['sale_id'], ['sales.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_table('shipping',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('sale_id', sa.Integer(), nullable=False),
        sa.Column('courier', sa.String(length=100), nullable=True),
        sa.Column('tracking_number', sa.String(length=100), nullable=True),
        sa.Column('chargeable_weight_kg', sa.Numeric(precision=10, scale=3), nullable=True),
        sa.Column('total_cbm', sa.Numeric(precision=12, scale=6), nullable=True),
        sa.Column('shipping_status', sa.String(length=50), nullable=True),
        sa.Column('shipped_at', sa.DateTime(), nullable=True),
        sa.Column('delivered_at', sa.DateTime(), nullable=True),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(['sale_id'], ['sales.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('sale_id'),
    )
    op.create_table('stock_log',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('product_id', sa.Integer(), nullable=False),
        sa.Column('change_qty', sa.Integer(), nullable=False),
        sa.Column('reason', sa.String(length=255), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(['product_id'], ['products.id'], ),
        sa.PrimaryKeyConstraint('id'),
    )


def downgrade():
    op.drop_table('stock_log')
    op.drop_table('shipping')
    op.drop_table('sale_items')
    op.drop_table('sales')
    op.drop_table('courier_rates')
    op.drop_table('products')
    op.drop_table('users')
