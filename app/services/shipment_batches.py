"""
Shipment batch logic — Stage 6.

A batch is an inbound consignment from the supplier containing many
customers' sales, arriving together after the 60-70 day window.

Status flow: In Transit -> Arrived (awaiting shipping payment) -> Payment Settled (ready for delivery)
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
    Locks in the ACTUAL shipping cost for every sale in the batch, using the
    MonthlyShippingRate for the month the batch arrives (today) — not the rate
    that was in effect when the estimate was originally made.
    """
    batch = ShipmentBatch.query.get(batch_id)
    if not batch:
        raise BatchValidationError("Batch not found.")
    if batch.status != ShipmentBatch.STATUS_IN_TRANSIT:
        raise BatchValidationError(f"Batch must be 'In Transit' to mark arrived (currently '{batch.status}').")
    if not batch.sales:
        raise BatchValidationError("Batch has no sales assigned — nothing to cost.")

    arrival_date = date.today()
    rate = get_rate_for_month(arrival_date)

    for sale in batch.sales:
        total_cbm = sum((item.line_cbm or Decimal("0")) for item in sale.items)
        sale.actual_shipping_cost = total_cbm * rate

    batch.arrived_at = datetime.utcnow()
    batch.status = ShipmentBatch.STATUS_ARRIVED
    db.session.commit()
    return batch


def mark_payment_settled(batch_id):
    batch = ShipmentBatch.query.get(batch_id)
    if not batch:
        raise BatchValidationError("Batch not found.")
    if batch.status != ShipmentBatch.STATUS_ARRIVED:
        raise BatchValidationError(
            f"Batch must be 'Arrived - Awaiting Shipping Payment' first (currently '{batch.status}')."
        )

    batch.payment_settled_at = datetime.utcnow()
    batch.status = ShipmentBatch.STATUS_SETTLED
    db.session.commit()
    return batch
