"""air/sea batches, monthly air rates, order journey

Revision ID: f3b8c2d1a475
Revises: e2a5b7d9c014
"""
from alembic import op
import sqlalchemy as sa

revision = "f3b8c2d1a475"
down_revision = "e2a5b7d9c014"
branch_labels = None
depends_on = None


def upgrade():
    # Existing batches were priced by CBM, so they become SEA batches.
    op.add_column(
        "shipment_batches",
        sa.Column("transport_mode", sa.String(length=10), nullable=False, server_default="sea"),
    )

    op.create_table(
        "monthly_air_rates",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("month", sa.Date(), nullable=False, unique=True),
        sa.Column("rate_per_kg", sa.Numeric(12, 2), nullable=False),
    )

    op.add_column("sales", sa.Column("estimated_shipping_sea", sa.Numeric(12, 2), nullable=True))
    op.add_column("sales", sa.Column("estimated_shipping_air", sa.Numeric(12, 2), nullable=True))
    op.add_column("sales", sa.Column("batch_assigned_at", sa.DateTime(), nullable=True))

    op.add_column("deliveries", sa.Column("returned_at", sa.DateTime(), nullable=True))

    op.create_table(
        "sale_journey_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("sale_id", sa.Integer(), sa.ForeignKey("sales.id", ondelete="CASCADE"), nullable=False),
        sa.Column("stage", sa.String(length=30), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
    )
    op.create_index("ix_sale_journey_events_sale_id", "sale_journey_events", ["sale_id"])


def downgrade():
    op.drop_index("ix_sale_journey_events_sale_id", table_name="sale_journey_events")
    op.drop_table("sale_journey_events")
    op.drop_column("deliveries", "returned_at")
    op.drop_column("sales", "batch_assigned_at")
    op.drop_column("sales", "estimated_shipping_air")
    op.drop_column("sales", "estimated_shipping_sea")
    op.drop_table("monthly_air_rates")
    op.drop_column("shipment_batches", "transport_mode")
