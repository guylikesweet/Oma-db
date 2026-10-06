"""
Shipment batch logic (simplified).

A batch is an inbound consignment containing many customers' sales,
arriving together. It travels by SEA or AIR (chosen when it is created), and
that decides how each sale's shipping is priced when it arrives:
  sea: (CBM x monthly sea rate)          + (actual kg x packing rate)
  air: (volumetric kg x monthly air rate) + (actual kg x packing rate)
When it arrives, EVERY sale in it gets its actual_shipping_cost calculated
at once, using that month's rate (the month of arrival). Settling a sale's shipping payment afterward is
just a confirmation flag — it doesn't recalculate anything — and it's
what individually unlocks that one sale for delivery, not the whole batch.
"""
from datetime import date, datetime
from decimal import Decimal

from app import db
from app.models import ShipmentBatch, Sale, SaleJourneyEvent
from app.services.rates import get_volume_rate, get_rate_per_kg, RateMissingError
from app.services.sales import shipping_cost_for_items, refresh_sale_profit
from app.services.push_notifications import queue_batch_arrival, flush_outbox
from app.services.audit import record_audit


class BatchValidationError(Exception):
    pass


def normalize_mode(value):
    """'air' / 'sea' (any case) -> the stored value; anything else is an error."""
    mode = (value or "").strip().lower()
    if mode not in ShipmentBatch.MODES:
        raise BatchValidationError("Choose how this batch travels: Air or Sea.")
    return mode


def create_batch(name, notes=None, transport_mode=ShipmentBatch.MODE_SEA):
    if not name or not name.strip():
        raise BatchValidationError("Batch needs a name.")
    batch = ShipmentBatch(
        name=name.strip(), notes=notes, status=ShipmentBatch.STATUS_IN_TRANSIT,
        transport_mode=normalize_mode(transport_mode),
    )
    db.session.add(batch)
    db.session.flush()
    record_audit(
        "batch.create",
        target_type="shipment_batch",
        target_id=batch.id,
        details={"name": batch.name, "transport_mode": batch.transport_mode},
    )
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
    if sale.is_stock_sale:
        raise BatchValidationError("Stocked sales are not shipped in batches.")

    sale.batch_id = batch.id
    sale.batch_assigned_at = datetime.utcnow()
    record_audit(
        "batch.add_sale",
        target_type="sale",
        target_id=sale.id,
        details={"batch_id": batch.id, "transport_mode": batch.transport_mode},
    )
    db.session.commit()
    return batch


def remove_sale_from_batch(sale_id):
    sale = Sale.query.get(sale_id)
    if not sale:
        raise BatchValidationError("Sale not found.")
    batch_id = sale.batch_id
    sale.batch_id = None
    sale.batch_assigned_at = None
    record_audit(
        "batch.remove_sale",
        target_type="sale",
        target_id=sale.id,
        details={"batch_id": batch_id},
    )
    db.session.commit()


def update_batch_sales(batch_id, *, add_sale_ids=None, remove_sale_ids=None, commit=True):
    """Atomically add and/or remove multiple sales from an In Transit batch."""
    batch = ShipmentBatch.query.get(batch_id)
    if not batch:
        raise BatchValidationError("Batch not found.")
    if batch.status != ShipmentBatch.STATUS_IN_TRANSIT:
        raise BatchValidationError("Sales can only be changed while the batch is In Transit.")

    add_ids = list(dict.fromkeys(int(x) for x in (add_sale_ids or [])))
    remove_ids = list(dict.fromkeys(int(x) for x in (remove_sale_ids or [])))

    overlap = set(add_ids) & set(remove_ids)
    if overlap:
        raise BatchValidationError("A sale cannot be added and removed in the same request.")

    if remove_ids:
        remove_sales = Sale.query.filter(Sale.id.in_(remove_ids)).all()
        found = {sale.id for sale in remove_sales}
        missing = [sale_id for sale_id in remove_ids if sale_id not in found]
        if missing:
            raise BatchValidationError(
                "Sales not found: " + ", ".join(str(x) for x in missing) + "."
            )
        for sale in remove_sales:
            if sale.batch_id != batch.id:
                raise BatchValidationError(
                    f"Sale #{sale.id} is not in this batch."
                )

    if add_ids:
        add_sales = Sale.query.filter(Sale.id.in_(add_ids)).all()
        found = {sale.id for sale in add_sales}
        missing = [sale_id for sale_id in add_ids if sale_id not in found]
        if missing:
            raise BatchValidationError(
                "Sales not found: " + ", ".join(str(x) for x in missing) + "."
            )
        for sale in add_sales:
            if sale.order_status == "Cancelled":
                raise BatchValidationError(
                    f"Sale #{sale.id} is cancelled and cannot be added."
                )
            if sale.is_stock_sale:
                raise BatchValidationError(
                    f"Sale #{sale.id} is a stock sale and cannot be shipped in a batch."
                )
            if sale.batch_id is not None and sale.batch_id != batch.id:
                raise BatchValidationError(
                    f"Sale #{sale.id} already belongs to another shipment batch."
                )

    for sale in remove_sales if remove_ids else []:
        sale.batch_id = None
        sale.batch_assigned_at = None
        record_audit(
            "batch.remove_sale",
            target_type="sale",
            target_id=sale.id,
            details={"batch_id": batch.id, "source": "bulk"},
        )

    for sale in add_sales if add_ids else []:
        sale.batch_id = batch.id
        sale.batch_assigned_at = datetime.utcnow()
        record_audit(
            "batch.add_sale",
            target_type="sale",
            target_id=sale.id,
            details={
                "batch_id": batch.id,
                "transport_mode": batch.transport_mode,
                "source": "bulk",
            },
        )

    if commit:
        db.session.commit()
    return batch


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

    # The batch's method decides the volume rate. An air batch can't arrive
    # until this month's air rate has been set — never charged as zero.
    try:
        volume_rate = get_volume_rate(batch.transport_mode, date.today())
    except RateMissingError as e:
        raise BatchValidationError(str(e))
    packing_rate = get_rate_per_kg()

    for sale in batch.sales:
        # Each product line by the batch's method, added up.
        sale.actual_shipping_cost = shipping_cost_for_items(
            sale.items, batch.transport_mode, volume_rate, packing_rate
        )
        sale.total_amount = (sale.subtotal_amount or Decimal("0")) + sale.actual_shipping_cost
        # Recalculate net profit using the immutable landed-cost snapshots on
        # the sale items and the actual shipping cost locked at arrival.
        refresh_sale_profit(sale, sale.actual_shipping_cost)

    batch.arrived_at = datetime.utcnow()
    batch.status = ShipmentBatch.STATUS_ARRIVED
    record_audit(
        'batch.arrive',
        target_type='shipment_batch',
        target_id=batch.id,
        details={'transport_mode': batch.transport_mode, 'sale_count': len(batch.sales), 'name': batch.name},
    )
    from flask_login import current_user
    queue_batch_arrival(batch, exclude_user_id=current_user.id if current_user.is_authenticated else None)
    db.session.commit()
    try:
        flush_outbox()
    except Exception:
        # The outbox remains committed and can be delivered on a later flush.
        pass
    return batch


def mark_unarrived(batch_id, user_id=None):
    """Undo an accidental arrival before any sale has been financially settled."""
    batch = ShipmentBatch.query.get(batch_id)
    if not batch:
        raise BatchValidationError("Batch not found.")
    if batch.status != ShipmentBatch.STATUS_ARRIVED:
        raise BatchValidationError(
            f"Batch must be 'Arrived' to undo arrival (currently '{batch.status}')."
        )
    if any(s.shipping_payment_settled for s in batch.sales):
        raise BatchValidationError(
            "Arrival cannot be undone after shipping payment has been settled for a sale in this batch."
        )
    if any(s.delivery_id for s in batch.sales):
        raise BatchValidationError(
            "Arrival cannot be undone after a sale in this batch has been assigned to a delivery."
        )

    for sale in batch.sales:
        sale.actual_shipping_cost = None
        sale.total_amount = sale.subtotal_amount or Decimal("0")
        sale.shipping_payment_settled = False
        sale.shipping_payment_settled_at = None
        # The automatic arrival milestone must be reversible too. Recording
        # the current batch mode as a fresh journey event makes the downgrade
        # visible immediately on every client.
        db.session.add(
            SaleJourneyEvent(
                sale_id=sale.id,
                stage="cross_border",
                user_id=user_id,
            )
        )

    previous_arrival = batch.arrived_at
    batch.arrived_at = None
    batch.status = ShipmentBatch.STATUS_IN_TRANSIT

    record_audit(
        "batch.undo_arrival",
        target_type="shipment_batch",
        target_id=batch.id,
        details={
            "transport_mode": batch.transport_mode,
            "sale_count": len(batch.sales),
            "previous_arrived_at": previous_arrival.isoformat() if previous_arrival else None,
        },
    )

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
    record_audit(
        'shipping.settle',
        target_type='sale',
        target_id=sale.id,
        details={'shipping_amount': str(sale.actual_shipping_cost or 0)},
    )

    db.session.commit()
    return sale
