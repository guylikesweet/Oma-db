"""Stage 7 performance indexes for dashboard and operational queries.

These indexes target columns used repeatedly by dashboard counts, sales/report
filters, shipment status lookups, and mobile idempotency diagnostics.
"""

from alembic import op


revision = "oma20261006_performance"
down_revision = "oma20261006_push_channels"
branch_labels = None
depends_on = None


def upgrade():
    op.create_index("ix_sales_sale_date", "sales", ["sale_date"])
    op.create_index("ix_sales_order_status", "sales", ["order_status"])
    op.create_index("ix_sales_batch_id", "sales", ["batch_id"])
    op.create_index("ix_sales_delivery_id", "sales", ["delivery_id"])
    op.create_index(
        "ix_sales_shipping_payment_settled",
        "sales",
        ["shipping_payment_settled"],
    )
    op.create_index("ix_products_stock", "products", ["stock"])
    op.create_index("ix_shipment_batches_status", "shipment_batches", ["status"])
    op.create_index("ix_deliveries_status", "deliveries", ["status"])
    op.create_index("ix_shipping_shipping_status", "shipping", ["shipping_status"])
    op.create_index("ix_mobile_operations_status", "mobile_operations", ["status"])


def downgrade():
    op.drop_index("ix_mobile_operations_status", table_name="mobile_operations")
    op.drop_index("ix_shipping_shipping_status", table_name="shipping")
    op.drop_index("ix_deliveries_status", table_name="deliveries")
    op.drop_index("ix_shipment_batches_status", table_name="shipment_batches")
    op.drop_index(
        "ix_sales_shipping_payment_settled",
        table_name="sales",
    )
    op.drop_index("ix_products_stock", table_name="products")
    op.drop_index("ix_sales_delivery_id", table_name="sales")
    op.drop_index("ix_sales_batch_id", table_name="sales")
    op.drop_index("ix_sales_order_status", table_name="sales")
    op.drop_index("ix_sales_sale_date", table_name="sales")
