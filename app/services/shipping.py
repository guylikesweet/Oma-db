"""
Shipping business logic — Module E from the blueprint.

Key Logic Rule 7:
  shipping.chargeable_weight_kg = MAX(SUM(actual_weight_kg*qty), SUM(volumetric_kg*qty))
"""
from datetime import datetime
from decimal import Decimal

from app import db
from app.models import Sale, Shipping, Product


class ShippingValidationError(Exception):
    pass


def create_shipping(sale_id, courier, tracking_number, notes=None):
    sale = Sale.query.get(sale_id)
    if not sale:
        raise ShippingValidationError("Sale not found.")
    if sale.order_status != "Packed":
        raise ShippingValidationError(
            f"Sale must be 'Packed' before shipping can be created (currently '{sale.order_status}')."
        )
    if sale.shipping:
        raise ShippingValidationError("This sale already has a shipment.")
    if not sale.items:
        raise ShippingValidationError("Sale has no line items — nothing to ship.")

    total_cbm = Decimal("0")
    total_actual_weight = Decimal("0")
    total_volumetric_weight = Decimal("0")

    for item in sale.items:
        product = Product.query.get(item.product_id)
        qty = item.qty
        total_cbm += item.line_cbm or Decimal("0")
        total_actual_weight += (product.actual_weight_kg or Decimal("0")) * qty if product else Decimal("0")
        total_volumetric_weight += item.line_volumetric_kg or Decimal("0")

    chargeable_weight_kg = max(total_actual_weight, total_volumetric_weight)

    shipping = Shipping(
        sale_id=sale.id,
        courier=courier,
        tracking_number=tracking_number,
        total_cbm=total_cbm,
        chargeable_weight_kg=chargeable_weight_kg,
        shipping_status="Shipped",
        shipped_at=datetime.utcnow(),
        notes=notes,
    )
    db.session.add(shipping)

    sale.order_status = "Shipped"
    db.session.commit()
    return shipping


def update_shipping(shipping_id, courier=None, tracking_number=None, shipping_status=None, notes=None):
    shipping = Shipping.query.get(shipping_id)
    if not shipping:
        raise ShippingValidationError("Shipment not found.")

    valid_statuses = {"Processing", "Shipped", "In Transit", "Delivered"}

    if courier is not None:
        shipping.courier = courier
    if tracking_number is not None:
        shipping.tracking_number = tracking_number
    if notes is not None:
        shipping.notes = notes

    if shipping_status:
        if shipping_status not in valid_statuses:
            raise ShippingValidationError(f"Invalid shipping status '{shipping_status}'.")

        if shipping_status == "Shipped" and not shipping.shipped_at:
            shipping.shipped_at = datetime.utcnow()

        if shipping_status == "Delivered":
            shipping.delivered_at = datetime.utcnow()
            sale = Sale.query.get(shipping.sale_id)
            if sale:
                sale.order_status = "Delivered"

        shipping.shipping_status = shipping_status

    db.session.commit()
    return shipping


def search_shipping(tracking_number=None, state=None):
    query = Shipping.query.join(Sale, Shipping.sale_id == Sale.id)
    if tracking_number:
        query = query.filter(Shipping.tracking_number.ilike(f"%{tracking_number}%"))
    if state:
        query = query.filter(Sale.customer_state.ilike(f"%{state}%"))
    return query.order_by(Shipping.id.desc()).all()
