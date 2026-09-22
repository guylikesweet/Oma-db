"""add order_id, shipment date, and label capture fields

Revision ID: 24ba0daf2a17
Revises: 15266d7fb5f3
Create Date: 2026-09-22 06:19:58.321358

"""
import random
import string

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '24ba0daf2a17'
down_revision = '15266d7fb5f3'
branch_labels = None
depends_on = None

_ALPHABET = string.ascii_uppercase + string.digits


def upgrade():
    with op.batch_alter_table('deliveries', schema=None) as batch_op:
        batch_op.add_column(sa.Column('shipped_at', sa.DateTime(), nullable=True))
        batch_op.add_column(sa.Column('package_weight_kg', sa.Numeric(precision=10, scale=3), nullable=True))
        batch_op.add_column(sa.Column('package_dimensions', sa.String(length=100), nullable=True))
        batch_op.add_column(sa.Column('remarks', sa.Text(), nullable=True))

    with op.batch_alter_table('sales', schema=None) as batch_op:
        batch_op.add_column(sa.Column('order_id', sa.String(length=20), nullable=True))

    # Backfill order_id for any sales that existed before this column did —
    # without this, pre-existing orders would show a blank/None order ID
    # everywhere (sale pages, labels, barcodes) instead of a real OMB- id.
    conn = op.get_bind()
    existing_ids = {row[0] for row in conn.execute(sa.text("SELECT order_id FROM sales WHERE order_id IS NOT NULL"))}
    rows = conn.execute(sa.text("SELECT id FROM sales WHERE order_id IS NULL")).fetchall()
    for (sale_pk,) in rows:
        while True:
            candidate = "OMB-" + "".join(random.choices(_ALPHABET, k=6))
            if candidate not in existing_ids:
                existing_ids.add(candidate)
                break
        conn.execute(sa.text("UPDATE sales SET order_id = :oid WHERE id = :pk"), {"oid": candidate, "pk": sale_pk})

    with op.batch_alter_table('sales', schema=None) as batch_op:
        batch_op.create_unique_constraint('uq_sales_order_id', ['order_id'])


def downgrade():
    with op.batch_alter_table('sales', schema=None) as batch_op:
        batch_op.drop_constraint('uq_sales_order_id', type_='unique')
        batch_op.drop_column('order_id')

    with op.batch_alter_table('deliveries', schema=None) as batch_op:
        batch_op.drop_column('remarks')
        batch_op.drop_column('package_dimensions')
        batch_op.drop_column('package_weight_kg')
        batch_op.drop_column('shipped_at')
