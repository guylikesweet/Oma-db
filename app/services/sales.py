"""
Sales business logic (simplified — no profit/loss tracking anywhere).

At creation:
  sales.subtotal_amount        = SUM(unit_price * qty)
  sales.estimated_shipping_cost = total_cbm * MonthlyShippingRate for the CURRENT month
                                   (a rough estimate only — recalculated for real at batch arrival)
  sales.total_amount           = subtotal_amount (goods only; shipping added once the batch arrives)
"""
from decimal import Decimal
from datetime import date, timedelta
import random
import string

from app import db
from app.models import Sale, SaleItem, Product, StockLog
from app.services.rates import get_rate_for_month

ORDER_ID_ALPHABET = string.ascii_uppercase + string.digits

SALE_TYPE_PREORDER = "preorder"
SALE_TYPE_STOCK = "stock"
ORDER_ID_PREFIX = {SALE_TYPE_PREORDER: "OMB-", SALE_TYPE_STOCK: "OMBSTK-"}


def generate_order_id(sale_type=SALE_TYPE_PREORDER):
    """OMB- (preorder) or OMBSTK- (stocked) + 6 random alphanumeric chars, checked for uniqueness."""
    prefix = ORDER_ID_PREFIX.get(sale_type, "OMB-")
    for _ in range(50):  # practically always succeeds on the first try
        candidate = prefix + "".join(random.choices(ORDER_ID_ALPHABET, k=6))
        if not Sale.query.filter_by(order_id=candidate).first():
            return candidate
    raise RuntimeError("Could not generate a unique order ID after 50 attempts.")


class SaleValidationError(Exception):
    """Raised for any problem that should stop sale creation (bad input, insufficient stock)."""


def create_sale(customer_name, customer_phone, customer_address, customer_state,
                 payment_status, notes, line_items, commit=True, sale_type=SALE_TYPE_PREORDER,
                 client_operation_id=None):
    """
    line_items: list of dicts: {"product_id": int, "qty": int, "unit_price": Decimal, "variant_note": str (optional)}
    Returns the created Sale. Raises SaleValidationError on any problem — nothing
    is written to the database if validation fails (atomic).

    commit: pass False to leave the transaction open (flushed but not committed) so
    the caller can add more rows — e.g. a MobileOperation idempotency record — and
    commit everything together atomically. Defaults to True for existing callers
    that expect create_sale() to commit on its own.
    """
    if sale_type not in ORDER_ID_PREFIX:
        raise SaleValidationError("Invalid sale type.")
    is_stock = sale_type == SALE_TYPE_STOCK
    if not line_items:
        raise SaleValidationError("A sale needs at least one product line.")

    products = {}
    for line in line_items:
        qty = line["qty"]
        if qty <= 0:
            raise SaleValidationError("Quantity must be greater than zero for every line.")

        product = Product.query.get(line["product_id"])
        if not product:
            raise SaleValidationError(f"Product id {line['product_id']} does not exist.")
        # Preorders are for goods still to be shipped in, so stock is irrelevant:
        # the quantity is simply what the customer asked for. Only stocked sales check it.
        if is_stock and product.stock < qty:
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
        sale_type=sale_type,
        client_operation_id=client_operation_id or None,
    )
    sale.order_id = generate_order_id(sale_type)
    sale.sale_date = date.today()
    if not is_stock:
        sale.estimated_arrival_start = sale.sale_date + timedelta(days=60)
        sale.estimated_arrival_end = sale.sale_date + timedelta(days=70)
    db.session.add(sale)
    db.session.flush()  # assigns sale.id, needed for stock_log "Sale #<id>" reason

    subtotal = Decimal("0")
    total_cbm = Decimal("0")

    for line in line_items:
        product = products[line["product_id"]]
        qty = line["qty"]
        unit_price = Decimal(str(line["unit_price"]))
        unit_cost = product.cost or Decimal("0")

        line_cbm = (product.cbm or Decimal("0")) * qty
        line_volumetric_kg = (product.volumetric_kg or Decimal("0")) * qty

        db.session.add(SaleItem(
            sale_id=sale.id,
            product_id=product.id,
            qty=qty,
            unit_cost=unit_cost,
            unit_price=unit_price,
            line_cbm=line_cbm,
            line_volumetric_kg=line_volumetric_kg,
            variant_note=line.get("variant_note") or None,
        ))

        # Only stocked sales draw down inventory (+ audit trail)
        if is_stock:
            product.stock -= qty
            db.session.add(StockLog(product_id=product.id, change_qty=-qty, reason=f"Sale {sale.order_id}"))

        subtotal += unit_price * qty
        total_cbm += line_cbm

    sale.subtotal_amount = subtotal
    if is_stock:
        sale.estimated_shipping_cost = None  # no shipping on stocked sales; delivery is settled off record
    else:
        rate = get_rate_for_month(date.today())
        sale.estimated_shipping_cost = total_cbm * rate  # rough estimate only
    sale.total_amount = subtotal  # goods only; actual shipping added once the batch arrives

    if commit:
        db.session.commit()
    else:
        db.session.flush()  # sale.id and all rows above are usable, just not committed yet
    return sale


def update_sale_status(sale_id, new_status):
    """
    Handles New -> Packed -> Cancelled (and further transitions for Shipped/Delivered).
    Cancelling a sale that hasn't already been cancelled restocks every line item and logs it.
    """
    sale = Sale.query.get(sale_id)
    if not sale:
        raise SaleValidationError("Sale not found.")

    valid_statuses = {"New", "Packed", "Shipped", "Delivered", "Cancelled"}
    if new_status not in valid_statuses:
        raise SaleValidationError(f"Invalid status '{new_status}'.")

    if new_status == "Cancelled" and sale.order_status != "Cancelled" and sale.is_stock_sale:
        # Only stocked sales deducted stock, so only they restock.
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


VALID_PAYMENT_STATUSES = {"Paid", "Pending", "Refunded"}


def update_sale_payment_status(sale_id, new_payment_status):
    """Marks a sale Paid / Pending / Refunded. This is independent of
    order_status (a sale can be Pending payment while already Packed, etc.)."""
    sale = Sale.query.get(sale_id)
    if not sale:
        raise SaleValidationError("Sale not found.")
    if new_payment_status not in VALID_PAYMENT_STATUSES:
        raise SaleValidationError(f"Invalid payment status '{new_payment_status}'.")
    sale.payment_status = new_payment_status
    db.session.commit()
    return sale
