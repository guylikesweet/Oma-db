"""
Shipment batch logic (simplified).

A batch is an inbound consignment containing many customers' sales,
arriving together. When it arrives, EVERY sale in it gets its
actual_shipping_cost calculated at once, using that month's rate
(the month of arrival). Settling a sale's shipping payment afterward is
just a confirmation flag — it doesn't recalculate anything — and it's
what individually unlocks that one sale for delivery, not the whole batch.
"""
from datetime import date, datetime
from decimal import Decimal

from app import db
from app.models import ShipmentBatch, Sale
from app.services.rates import get_rate_for_month


class BatchValidationError(Exception):
    pass


def create_batch(name, notes=None):
    if not name or not name.strip():
        raise BatchValidationError("Batch needs a name.")
    batch = ShipmentBatch(name=name.strip(), notes=notes, status=ShipmentBatch.STATUS_IN_TRANSIT)
    db.session.add(batch)
    db.session.commit()
    return batch


def add_sale_to_batch(batch_id, sale_id):
    batch = ShipmentBatch.query.get(batch_id)
    if not batch:
        raise BatchValidationError("Batch not found.")
    if batch.status != ShipmentBatch.STATUS_IN_TRANSIT:
        raise BatchValidationError("Can only add sales to a batch that is still In Transit.")

    sale = Sale.query.get(sale_id)
    if not sale:
        raise BatchValidationError("Sale not found.")
    if sale.order_status == "Cancelled":
        raise BatchValidationError("Cannot add a cancelled sale to a batch.")

    sale.batch_id = batch.id
    db.session.commit()
    return batch


def remove_sale_from_batch(sale_id):
    sale = Sale.query.get(sale_id)
    if not sale:
        raise BatchValidationError("Sale not found.")
    sale.batch_id = None
    db.session.commit()


def mark_arrived(batch_id):
    """
    Marks the batch arrived and, using THIS month's rate (the arrival month),
    calculates actual_shipping_cost + total_amount for every sale in it, all at once.
    """
    batch = ShipmentBatch.query.get(batch_id)
    if not batch:
        raise BatchValidationError("Batch not found.")
    if batch.status != ShipmentBatch.STATUS_IN_TRANSIT:
        raise BatchValidationError(f"Batch must be 'In Transit' to mark arrived (currently '{batch.status}').")
    if not batch.sales:
        raise BatchValidationError("Batch has no sales assigned.")

    rate = get_rate_for_month(date.today())

    for sale in batch.sales:
        total_cbm = sum((item.line_cbm or Decimal("0")) for item in sale.items)
        sale.actual_shipping_cost = total_cbm * rate
        sale.total_amount = (sale.subtotal_amount or Decimal("0")) + sale.actual_shipping_cost

    batch.arrived_at = datetime.utcnow()
    batch.status = ShipmentBatch.STATUS_ARRIVED
    db.session.commit()
    return batch


def settle_sale_shipping(sale_id):
    """
    Confirms this ONE sale's shipping payment as received. Does not recalculate
    anything (that already happened for the whole batch at arrival) — it just
    flags the sale as settled, which is what unlocks it for delivery.
    """
    sale = Sale.query.get(sale_id)
    if not sale:
        raise BatchValidationError("Sale not found.")
    if not sale.batch_id or not sale.batch:
        raise BatchValidationError("This sale isn't part of a shipment batch yet.")
    if sale.batch.status != ShipmentBatch.STATUS_ARRIVED:
        raise BatchValidationError(
            f"Batch must be 'Arrived' before shipping can be settled (currently '{sale.batch.status}')."
        )
    if sale.shipping_payment_settled:
        raise BatchValidationError(f"Sale #{sale.id}'s shipping payment is already settled.")

    sale.shipping_payment_settled = True
    sale.shipping_payment_settled_at = datetime.utcnow()

    db.session.commit()
    return sale
