"""
Order journey — the customer-facing stages an order moves through.

Preordered goods (shipped in from China):
  confirmed -> fulfilled -> CN domestic transit -> consolidation ->
  cross-border transit (on sea / in the air, by the batch) ->
  awaiting clearance -> packing -> NG domestic transit -> delivered | returned

Stocked goods (already in Nigeria) skip the China and shipping stages:
  confirmed -> packing -> NG domestic transit -> delivered | returned

Most stages are WORKED OUT from real records, so they can never drift from
what actually happened:
  cross-border transit  = the sale is in a shipment batch
  awaiting clearance    = that batch has arrived
  packing               = shipping settled, or a delivery has been created
  NG domestic transit   = its delivery is out for delivery
  delivered / returned  = its delivery was delivered / returned
Only the early stages happen outside the app, so they are set by hand, in
bulk: fulfilled, CN domestic transit, consolidation (and packing for stocked
goods). Those are kept as SaleJourneyEvent rows.
"""
from datetime import datetime

from app import db
from app.models import Delivery, SaleJourneyEvent, ShipmentBatch

STAGE_INFO = {
    "confirmed": ("Confirmed", "Your order has been recorded.", "Your order is confirmed."),
    "fulfilled": ("Fulfilled", "Your order is packed and ready to be transported to the shipping warehouse.", "Your order is fulfilled and ready for transport."),
    "cn_transit": ("CN domestic transit", "Your goods are on the move to the shipping warehouse.", "Your order is in transit through China."),
    "consolidation": ("Consolidation", "Your order is being packed to be shipped.", "Your order is being consolidated for international shipping."),
    "cross_border": ("Cross-border transit", "Your goods are on their way to Nigeria.", "Your order is in cross-border transit."),
    "awaiting_clearance": ("Awaiting customs clearance", "Your goods have arrived in the country and are pending shipping cost.", "Your order is awaiting customs clearance."),
    "packing": ("Packing", "Your order is being prepared for delivery.", "Your order is being prepared for delivery."),
    "ng_transit": ("Out for delivery", "Your order is out for delivery.", "Your order is out for delivery."),
    "delivered": ("Delivered", "Your order has been delivered and signed for.", "Your order has been delivered."),
    "returned": ("Returned", "Your order was rejected and has been returned.", "Your order has been returned."),
}

# Public ordered list of all journey stages, used by dashboard/reporting code.\nSTAGES = tuple(STAGE_INFO.keys())

PREORDER_FLOW = [
    "confirmed", "fulfilled", "cn_transit", "consolidation", "cross_border",
    "awaiting_clearance", "packing", "ng_transit", "delivered",
]
STOCK_FLOW = ["confirmed", "packing", "ng_transit", "delivered"]

# Stages that are set by hand, per kind of sale.
MANUAL_STAGES = {
    "preorder": ("fulfilled", "cn_transit", "consolidation"),
    "stock": ("packing",),
}


class JourneyError(ValueError):
    pass


def stage_label(key):
    return STAGE_INFO[key][0]


def flow_for(sale):
    return STOCK_FLOW if sale.is_stock_sale else PREORDER_FLOW


def manual_stages_for(sale):
    return MANUAL_STAGES["stock" if sale.is_stock_sale else "preorder"]


def _reached(sale):
    """{stage: datetime or None} for every stage the order has reached.
    None means 'reached, time unknown'."""
    reached = {"confirmed": sale.created_at}

    # Stages set by hand (latest event per stage wins).
    for event in sorted(sale.journey_events, key=lambda e: (e.created_at or datetime.min, e.id or 0)):
        reached[event.stage] = event.created_at

    batch = sale.batch
    if not sale.is_stock_sale and batch is not None:
        reached["cross_border"] = sale.batch_assigned_at or batch.created_at
        if batch.status != ShipmentBatch.STATUS_IN_TRANSIT:
            reached["awaiting_clearance"] = batch.arrived_at

    delivery = sale.delivery  # (loaded together with the sale in list queries)

    # Packing: shipping settled (preorder) or a delivery exists.
    packing_times = []
    if sale.shipping_payment_settled and not sale.is_stock_sale:
        packing_times.append(sale.shipping_payment_settled_at)
    if delivery:
        packing_times.append(delivery.created_at)
    if packing_times:
        known = [t for t in packing_times if t]
        reached["packing"] = min(known) if known else None

    if delivery and delivery.status in (
        Delivery.STATUS_OUT_FOR_DELIVERY, Delivery.STATUS_DELIVERED, Delivery.STATUS_RETURNED,
    ):
        reached["ng_transit"] = delivery.shipped_at
    if delivery and delivery.status == Delivery.STATUS_DELIVERED:
        reached["delivered"] = delivery.delivered_at
    elif sale.order_status == "Delivered":
        reached["delivered"] = reached.get("delivered")
    if delivery and delivery.status == Delivery.STATUS_RETURNED:
        reached["returned"] = delivery.returned_at

    return reached, delivery


def journey_for(sale):
    """The whole journey for one order, ready to render or serialise."""
    reached, _delivery = _reached(sale)
    flow = list(flow_for(sale))

    returned = "returned" in reached
    if returned:
        flow[-1] = "returned"  # the last step is either delivered or returned

    # Current = the furthest stage reached (a later stage implies the earlier
    # ones were passed, even if nobody recorded them).
    current_index = 0
    for index, key in enumerate(flow):
        if key in reached:
            current_index = index

    mode = sale.batch.transport_mode if (sale.batch is not None and not sale.is_stock_sale) else None
    steps = []
    for index, key in enumerate(flow):
        label, description, headline = STAGE_INFO[key]
        if key == "cross_border":
            if mode == ShipmentBatch.MODE_AIR:
                label, description, headline = "Cross-border transit (air)", "Your goods are on their way to Nigeria by air.", "Your order is in cross-border transit by air."
            elif mode == ShipmentBatch.MODE_SEA:
                label, description, headline = "Cross-border transit (sea)", "Your goods are on their way to Nigeria by sea.", "Your order is in cross-border transit by sea."
        if index < current_index:
            state = "done"
        elif index == current_index:
            state = "final" if key in ("delivered", "returned") else "current"
        else:
            state = "upcoming"
        at = reached.get(key)
        steps.append({
            "key": key,
            "label": label,
            "description": description,
            "headline": headline,
            "state": state,
            "at": at.isoformat() if at else None,
            "at_dt": at,
        })

    current = steps[current_index]
    return {
        "kind": "stock" if sale.is_stock_sale else "preorder",
        "current": current["key"],
        "current_label": current["label"],
        "current_description": current["description"],
        "current_headline": current["headline"],
        "mode": mode,
        "cancelled": sale.order_status == "Cancelled",
        "steps": steps,
    }


def journey_public(sale):
    """journey_for() without the raw datetime objects (safe for jsonify)."""
    data = journey_for(sale)
    for step in data["steps"]:
        step.pop("at_dt", None)
    return data


def current_stage_key(sale):
    reached, _ = _reached(sale)
    flow = list(flow_for(sale))
    if "returned" in reached:
        flow[-1] = "returned"
    index = 0
    for i, key in enumerate(flow):
        if key in reached:
            index = i
    return flow[index]


def set_manual_stage(sale, stage, user_id=None):
    """
    Moves one sale to a hand-set stage. Raises JourneyError (with a plain
    reason) if it can't: wrong kind of stage for this sale, cancelled, or the
    order has already moved on in a way the app tracks itself.
    Moving back is allowed so a mistake can be corrected.
    """
    allowed = manual_stages_for(sale)
    if stage not in allowed:
        names = ", ".join(stage_label(k) for k in allowed)
        raise JourneyError(f"{sale.order_id or sale.id}: only {names} can be set by hand for this kind of order.")
    if sale.order_status == "Cancelled":
        raise JourneyError(f"{sale.order_id or sale.id}: the order is cancelled.")

    if sale.is_stock_sale:
        if sale.delivery_id:
            raise JourneyError(f"{sale.order_id or sale.id}: it already has a delivery.")
    else:
        if sale.batch_id:
            raise JourneyError(f"{sale.order_id or sale.id}: it is already in a shipment batch.")

    order = list(allowed)
    target_index = order.index(stage)

    # Correcting backwards: forget any hand-set stage later than the target.
    for event in list(sale.journey_events):
        if event.stage in order and order.index(event.stage) > target_index:
            db.session.delete(event)

    existing = [e for e in sale.journey_events if e.stage == stage]
    if existing:
        return False  # already there

    db.session.add(SaleJourneyEvent(sale_id=sale.id, stage=stage, user_id=user_id))
    return True


def set_manual_stage_bulk(sales, stage, user_id=None):
    """Applies set_manual_stage() to many sales. Returns (updated, unchanged, skipped)
    where skipped is a list of plain-English reasons."""
    updated, unchanged, skipped = 0, 0, []
    for sale in sales:
        try:
            if set_manual_stage(sale, stage, user_id=user_id):
                updated += 1
            else:
                unchanged += 1
        except JourneyError as e:
            skipped.append(str(e))
    return updated, unchanged, skipped
