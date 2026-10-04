"""
Delivery logic — Stage 7, eligibility reworked in Stage 8.

A sale becomes eligible for delivery once its OWN shipping payment has
been settled (Sale.shipping_payment_settled) — not when its whole batch
reaches some status. At that point it can be moved into a Delivery record
either on its own, or consolidated with other eligible sales that share
the same customer name/phone or the same destination state — always as
an explicit choice, never automatic, since the customer may have changed
their mind.
"""
from datetime import datetime
from collections import defaultdict

from sqlalchemy import or_

from app import db
from app.models import Sale, Delivery
from app.services.audit import record_audit


class DeliveryValidationError(ValueError):
    pass


# ---------------------------------------------------------------------------
# Matching helpers. Consolidation is always optional — these only decide what
# gets SUGGESTED, and what the stored consolidation_type is labelled as.
# Precedence when several attributes match: phone > name > city > state.
# ---------------------------------------------------------------------------
CONSOLIDATION_ATTRS = ("phone", "name", "city", "state")
CONSOLIDATION_LABELS = {
    "phone": "Same phone number",
    "name": "Same customer name",
    "city": "Same city",
    "state": "Same state",
}


def _norm_text(value):
    return " ".join((value or "").split()).lower()


def _norm_phone(value):
    """Digits only, last 10 — so 0801 234 5678, +234 801 234 5678 and
    2348012345678 all count as the same number."""
    digits = "".join(ch for ch in (value or "") if ch.isdigit())
    return digits[-10:] if len(digits) >= 10 else digits


def _attr_key(sale, attr):
    if attr == "phone":
        return _norm_phone(sale.customer_phone)
    if attr == "name":
        return _norm_text(sale.customer_name)
    if attr == "city":
        return _norm_text(sale.customer_city)
    if attr == "state":
        return _norm_text(sale.customer_state)
    return ""


def shared_attributes(sales):
    """Which of phone/name/city/state are identical (and non-empty) across ALL given sales."""
    shared = []
    for attr in CONSOLIDATION_ATTRS:
        keys = {_attr_key(sale, attr) for sale in sales}
        if len(keys) == 1 and "" not in keys:
            shared.append(attr)
    return shared


def consolidation_type_for(sales):
    """'phone' / 'name' / 'city' / 'state' for the strongest shared attribute; None for a single sale."""
    if len(sales) < 2:
        return None
    shared = shared_attributes(sales)
    return shared[0] if shared else None


def find_consolidation_groups(sales=None):
    """
    Suggested bags: for each of phone/name/city/state, groups of 2+ ready sales sharing that value.
    A sale can appear in several groups (e.g. same phone AND same state) — the person chooses.
    Returns a list of {"type", "label", "value", "sale_ids"} dicts.
    """
    ready = sales if sales is not None else get_ready_for_delivery_sales()
    groups = []
    for attr in CONSOLIDATION_ATTRS:
        buckets = defaultdict(list)
        for sale in ready:
            key = _attr_key(sale, attr)
            if key:
                buckets[key].append(sale)
        for matched in buckets.values():
            if len(matched) > 1:
                display = {
                    "phone": matched[0].customer_phone,
                    "name": matched[0].customer_name,
                    "city": matched[0].customer_city,
                    "state": matched[0].customer_state,
                }[attr]
                groups.append({
                    "type": attr,
                    "label": CONSOLIDATION_LABELS[attr],
                    "value": (display or "").strip(),
                    "sale_ids": [sale.id for sale in matched],
                })
    return groups


def check_consolidation(sales):
    """
    Validates that the chosen sales may share one bag and returns the
    consolidation_type to store. A single sale is always fine. Several sales
    must share at least one of phone / name / city / state — this only stops
    an accidental tap grouping totally unrelated orders.
    """
    if len(sales) < 2:
        return None
    attr = consolidation_type_for(sales)
    if attr is None:
        raise DeliveryValidationError(
            "These sales don't share a phone number, name, city or state, so they "
            "can't go in the same courier bag. Create separate deliveries instead."
        )
    return attr


def get_ready_for_delivery_sales():
    """Sales whose OWN shipping payment has been settled, not cancelled, not yet in a delivery."""
    return (
        Sale.query.filter(
            or_(Sale.shipping_payment_settled.is_(True), Sale.sale_type == "stock"),
            Sale.delivery_id.is_(None),
            Sale.order_status != "Cancelled",
        )
        .order_by(Sale.customer_state, Sale.customer_phone)
        .all()
    )


def find_phone_matches():
    """Groups ready-for-delivery sales by customer_phone where 2+ sales share it."""
    ready = get_ready_for_delivery_sales()
    by_phone = defaultdict(list)
    for sale in ready:
        if sale.customer_phone:
            by_phone[sale.customer_phone].append(sale)
    return {phone: sales for phone, sales in by_phone.items() if len(sales) > 1}


def find_name_matches():
    """Groups ready-for-delivery sales by customer_name (case/space-insensitive) where 2+ share it."""
    ready = get_ready_for_delivery_sales()
    by_name = defaultdict(list)
    for sale in ready:
        if sale.customer_name:
            key = sale.customer_name.strip().lower()
            by_name[key].append(sale)
    return {
        sales[0].customer_name: sales
        for sales in by_name.values()
        if len(sales) > 1
    }


def create_delivery(sale_ids, method, consolidation_type=None, delivery_address=None, notes=None):
    """
    sale_ids: list of Sale ids to include in this delivery (1 = single, 2+ = consolidated).
    consolidation_type: ignored — it is now worked out from what the sales actually share
    (phone / name / city / state); kept in the signature so existing callers still work.
    """
    if not sale_ids:
        raise DeliveryValidationError("Select at least one sale for this delivery.")
    if not method or not method.strip():
        raise DeliveryValidationError("Delivery method is required.")

    sales = Sale.query.filter(Sale.id.in_(sale_ids)).all()
    if len(sales) != len(sale_ids):
        raise DeliveryValidationError("One or more selected sales could not be found.")

    for sale in sales:
        if sale.delivery_id is not None:
            raise DeliveryValidationError(f"Sale #{sale.id} is already assigned to a delivery.")
        if not sale.ready_for_delivery:
            raise DeliveryValidationError(
                f"Sale #{sale.id} isn't ready for delivery yet — its shipping payment hasn't been settled."
            )

    detected_type = check_consolidation(sales)

    delivery = Delivery(
        method=method.strip(),
        status=Delivery.STATUS_PENDING,
        is_consolidated=len(sales) > 1,
        consolidation_type=detected_type,
        delivery_address=delivery_address or sales[0].customer_address,
        notes=notes,
    )
    db.session.add(delivery)
    db.session.flush()

    for sale in sales:
        sale.delivery_id = delivery.id

    record_audit(
        "delivery.create",
        target_type="delivery",
        target_id=delivery.id,
        details={"sale_ids": [sale.id for sale in sales], "method": method.strip()},
    )
    db.session.commit()
    return delivery


def update_delivery_status(delivery_id, new_status):
    delivery = Delivery.query.get(delivery_id)
    if not delivery:
        raise DeliveryValidationError("Delivery not found.")

    valid_statuses = {
        Delivery.STATUS_PENDING, Delivery.STATUS_OUT_FOR_DELIVERY,
        Delivery.STATUS_DELIVERED, Delivery.STATUS_RETURNED,
    }
    if new_status not in valid_statuses:
        raise DeliveryValidationError(f"Invalid delivery status '{new_status}'.")

    old_status = delivery.status
    delivery.status = new_status
    if new_status == Delivery.STATUS_OUT_FOR_DELIVERY and not delivery.shipped_at:
        delivery.shipped_at = datetime.utcnow()
    if new_status == Delivery.STATUS_DELIVERED:
        delivery.delivered_at = datetime.utcnow()
        for sale in delivery.sales:
            sale.order_status = "Delivered"
    if new_status == Delivery.STATUS_RETURNED:
        # Rejected by the customer.
        delivery.returned_at = datetime.utcnow()
        for sale in delivery.sales:
            if sale.order_status == "Delivered":
                sale.order_status = "Shipped"

    record_audit(
        "delivery.status",
        target_type="delivery",
        target_id=delivery.id,
        details={"from": old_status, "to": new_status, "sale_ids": [sale.id for sale in delivery.sales]},
    )
    db.session.commit()
    return delivery
