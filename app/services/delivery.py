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

from app import db
from app.models import Sale, Delivery


class DeliveryValidationError(Exception):
    pass


def get_ready_for_delivery_sales():
    """Sales whose OWN shipping payment has been settled, not cancelled, not yet in a delivery."""
    return (
        Sale.query.filter(
            Sale.shipping_payment_settled.is_(True),
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
    consolidation_type: 'phone', 'location', or None — for traceability only.
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
        if not sale.shipping_payment_settled:
            raise DeliveryValidationError(
                f"Sale #{sale.id} isn't ready for delivery yet — its shipping payment hasn't been settled."
            )

    if len(sales) > 1:
        phones = {s.customer_phone for s in sales if s.customer_phone}
        names = {(s.customer_name or "").strip().lower() for s in sales if s.customer_name}
        # Consolidation only makes sense for the SAME customer (matched by phone or name) —
        # the label shows one recipient for the whole parcel, so mixing different
        # customers here would silently ship someone else's items under the wrong name/address.
        if len(phones) > 1 and len(names) > 1:
            raise DeliveryValidationError(
                "These sales are for different customers (different name and phone) — "
                "a consolidated parcel needs one label with one recipient. "
                "Create separate deliveries instead."
            )

    delivery = Delivery(
        method=method.strip(),
        status=Delivery.STATUS_PENDING,
        is_consolidated=len(sales) > 1,
        consolidation_type=consolidation_type if len(sales) > 1 else None,
        delivery_address=delivery_address or sales[0].customer_address,
        notes=notes,
    )
    db.session.add(delivery)
    db.session.flush()

    for sale in sales:
        sale.delivery_id = delivery.id

    db.session.commit()
    return delivery


def update_delivery_status(delivery_id, new_status):
    delivery = Delivery.query.get(delivery_id)
    if not delivery:
        raise DeliveryValidationError("Delivery not found.")

    valid_statuses = {Delivery.STATUS_PENDING, Delivery.STATUS_OUT_FOR_DELIVERY, Delivery.STATUS_DELIVERED}
    if new_status not in valid_statuses:
        raise DeliveryValidationError(f"Invalid delivery status '{new_status}'.")

    delivery.status = new_status
    if new_status == Delivery.STATUS_OUT_FOR_DELIVERY and not delivery.shipped_at:
        delivery.shipped_at = datetime.utcnow()
    if new_status == Delivery.STATUS_DELIVERED:
        delivery.delivered_at = datetime.utcnow()
        for sale in delivery.sales:
            sale.order_status = "Delivered"

    db.session.commit()
    return delivery
