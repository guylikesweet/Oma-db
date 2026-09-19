"""
Shipment batch logic — Stage 6, reworked in Stage 8.

A batch is an inbound consignment from the supplier containing many
customers' sales, arriving together after the 60-70 day window.

Stage 8 change: settlement is per-order, not per-batch. A batch arriving
("In Transit" -> "Arrived") is a physical, whole-batch event, but each
sale's shipping payment is settled individually (settle_sale_shipping),
locking in that sale's actual_shipping_cost and final profit using
whichever MonthlyShippingRate is current AT THE MOMENT of that specific
settlement — not the rate when the batch physically arrived, since
settlement can happen later (even in a different month) per order.
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
    Marks the batch as physically arrived. Does NOT touch any sale's shipping
    cost or profit — that only happens per-sale, via settle_sale_shipping,
    whenever each order's shipping payment is actually settled.
    """
    batch = ShipmentBatch.query.get(batch_id)
    if not batch:
        raise BatchValidationError("Batch not found.")
    if batch.status != ShipmentBatch.STATUS_IN_TRANSIT:
        raise BatchValidationError(f"Batch must be 'In Transit' to mark arrived (currently '{batch.status}').")
    if not batch.sales:
        raise BatchValidationError("Batch has no sales assigned.")

    batch.arrived_at = datetime.utcnow()
    batch.status = ShipmentBatch.STATUS_ARRIVED
    db.session.commit()
    return batch


def settle_sale_shipping(sale_id):
    """
    Settles ONE sale's shipping payment. Locks in actual_shipping_cost and the
    final profit using the MonthlyShippingRate for the CURRENT month (i.e. the
    month this settlement happens), regardless of when the batch arrived or
    when other sales in the same batch get settled.
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

    total_cbm = sum((item.line_cbm or Decimal("0")) for item in sale.items)
    total_cost = sum((item.unit_cost or Decimal("0")) * item.qty for item in sale.items)
    rate = get_rate_for_month(date.today())

    sale.actual_shipping_cost = total_cbm * rate
    sale.total_amount = (sale.subtotal_amount or Decimal("0")) + sale.actual_shipping_cost
    sale.profit = (sale.subtotal_amount or Decimal("0")) - total_cost - sale.actual_shipping_cost
    sale.shipping_payment_settled = True
    sale.shipping_payment_settled_at = datetime.utcnow()

    db.session.commit()
    return sale
