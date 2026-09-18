"""
Sales business logic — Module D from the blueprint.

Implements the Key Logic Rules exactly:
  3. sale_items.line_cbm            = product.cbm * qty
  4. sale_items.line_shipping_estimate = line_cbm * courier_rates.rate_per_cbm (by customer_state)
  5. sales.estimated_shipping_cost  = SUM(line_shipping_estimate)
  6. sales.profit                   = subtotal_amount - SUM(unit_cost*qty) - estimated_shipping_cost
"""
from decimal import Decimal
from datetime import date, timedelta

from app import db
from app.models import Sale, SaleItem, Product, CourierRate, StockLog

DEFAULT_RATE_PER_CBM = Decimal("600000.00")


class SaleValidationError(Exception):
    """Raised for any problem that should stop sale creation (bad input, insufficient stock)."""


def _get_rate_for_state(state):
    rate_row = CourierRate.query.filter_by(state=state).first()
    return rate_row.rate_per_cbm if rate_row else DEFAULT_RATE_PER_CBM


def create_sale(customer_name, customer_phone, customer_address, customer_state,
                 payment_status, notes, line_items):
    """
    line_items: list of dicts: {"product_id": int, "qty": int, "unit_price": Decimal, "variant_note": str (optional)}
    Returns the created Sale. Raises SaleValidationError on any problem — nothing
    is written to the database if validation fails (atomic).
    """
    if not line_items:
        raise SaleValidationError("A sale needs at least one product line.")

    rate_per_cbm = _get_rate_for_state(customer_state)

    products = {}
    for line in line_items:
        qty = line["qty"]
        if qty <= 0:
            raise SaleValidationError("Quantity must be greater than zero for every line.")

        product = Product.query.get(line["product_id"])
        if not product:
            raise SaleValidationError(f"Product id {line['product_id']} does not exist.")
        if product.stock < qty:
            raise SaleValidationError(
                f"Not enough stock for '{product.name}' (have {product.stock}, need {qty})."
            )
        products[line["product_id"]] = product

    # --- Everything validated. Now build the sale. ---
    sale = Sale(
        customer_name=customer_name,
        customer_phone=customer_phone,
        customer_address=customer_address,
        customer_state=customer_state,
        payment_status=payment_status or "Paid",
        notes=notes,
        order_status="New",
    )
    sale.sale_date = date.today()
    sale.estimated_arrival_start = sale.sale_date + timedelta(days=60)
    sale.estimated_arrival_end = sale.sale_date + timedelta(days=70)
    db.session.add(sale)
    db.session.flush()  # assigns sale.id, needed for stock_log "Sale #<id>" reason

    subtotal = Decimal("0")
    total_cost = Decimal("0")
    total_shipping = Decimal("0")

    for line in line_items:
        product = products[line["product_id"]]
        qty = line["qty"]
        unit_price = Decimal(str(line["unit_price"]))
        unit_cost = product.cost or Decimal("0")

        line_cbm = (product.cbm or Decimal("0")) * qty
        line_volumetric_kg = (product.volumetric_kg or Decimal("0")) * qty
        line_shipping_estimate = line_cbm * rate_per_cbm

        db.session.add(SaleItem(
            sale_id=sale.id,
            product_id=product.id,
            qty=qty,
            unit_cost=unit_cost,
            unit_price=unit_price,
            line_cbm=line_cbm,
            line_volumetric_kg=line_volumetric_kg,
            line_shipping_estimate=line_shipping_estimate,
            variant_note=line.get("variant_note") or None,
        ))

        # Deduct stock + audit trail
        product.stock -= qty
        db.session.add(StockLog(product_id=product.id, change_qty=-qty, reason=f"Sale #{sale.id}"))

        subtotal += unit_price * qty
        total_cost += unit_cost * qty
        total_shipping += line_shipping_estimate

    sale.subtotal_amount = subtotal
    sale.estimated_shipping_cost = total_shipping
    sale.total_amount = subtotal + total_shipping
    sale.profit = subtotal - total_cost - total_shipping

    db.session.commit()
    return sale


def update_sale_status(sale_id, new_status):
    """
    Handles New -> Packed -> Cancelled (and further transitions in Stage 4 for Shipped/Delivered).
    Cancelling a sale that hasn't already been cancelled restocks every line item and logs it.
    """
    sale = Sale.query.get(sale_id)
    if not sale:
        raise SaleValidationError("Sale not found.")

    valid_statuses = {"New", "Packed", "Shipped", "Delivered", "Cancelled"}
    if new_status not in valid_statuses:
        raise SaleValidationError(f"Invalid status '{new_status}'.")

    if new_status == "Cancelled" and sale.order_status != "Cancelled":
        for item in sale.items:
            product = Product.query.get(item.product_id)
            if product:
                product.stock += item.qty
                db.session.add(StockLog(
                    product_id=product.id, change_qty=item.qty, reason=f"Sale #{sale.id} Cancelled"
                ))

    sale.order_status = new_status
    db.session.commit()
    return sale
