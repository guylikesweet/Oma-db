"""
Sales business logic (simplified — no profit/loss tracking anywhere).

At creation:
  sales.subtotal_amount        = SUM(unit_price * qty)
  sales.estimated_shipping_cost = sum over lines of (CBM x MonthlyShippingRate for the CURRENT month + kg x per-kg rate)
                                   (a rough estimate only — recalculated for real at batch arrival)
  sales.total_amount           = subtotal_amount (goods only; shipping added once the batch arrives)
"""
from decimal import Decimal
from datetime import date, timedelta
import random
import string

from app import db
from app.models import Sale, SaleItem, Product, StockLog
from app.services.rates import get_rate_for_month, get_rate_per_kg

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


def line_shipping_cost(line_cbm, line_kg, cbm_rate, kg_rate):
    """
    One product line's shipping: its CBM x the CBM rate, PLUS its weight in kg
    x the per-kg rate. The single formula behind every shipping figure.
    """
    return (
        (line_cbm or Decimal("0")) * cbm_rate
        + (line_kg or Decimal("0")) * kg_rate
    )


def item_weight_kg(item):
    """A line's weight: the snapshot taken at sale time, or (older sales
    that predate it) the product's current weight x qty."""
    if item.line_weight_kg is not None:
        return item.line_weight_kg
    product_kg = (item.product.actual_weight_kg if item.product else None) or Decimal("0")
    return product_kg * (item.qty or 0)


def shipping_cost_for_items(items, rate, kg_rate=None):
    """
    Shipping for a sale = each product line's cost calculated separately
    (CBM x rate + kg x per-kg rate), then added up. Used for the estimate at
    order time and the actual cost at batch arrival, so they never drift apart.
    """
    if kg_rate is None:
        kg_rate = get_rate_per_kg()
    total = Decimal("0")
    for item in items:
        total += line_shipping_cost(item.line_cbm, item_weight_kg(item), rate, kg_rate)
    return total


class SaleValidationError(Exception):
    """Raised for any problem that should stop sale creation (bad input, insufficient stock)."""


def create_sale(customer_name, customer_phone, customer_address, customer_state,
                 payment_status, notes, line_items, commit=True, sale_type=SALE_TYPE_PREORDER,
                 client_operation_id=None, customer_city=None):
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
    requested = {}  # product_id -> total qty across ALL lines (one product can be on several lines, e.g. two colours)
    for line in line_items:
        qty = line["qty"]
        if qty <= 0:
            raise SaleValidationError("Quantity must be greater than zero for every line.")

        product = Product.query.get(line["product_id"])
        if not product:
            raise SaleValidationError(f"Product id {line['product_id']} does not exist.")
        products[line["product_id"]] = product
        requested[line["product_id"]] = requested.get(line["product_id"], 0) + qty

    # Preorders are for goods still to be shipped in, so stock is irrelevant:
    # the quantity is simply what the customer asked for. Only stocked sales check it.
    if is_stock:
        for product_id, total_qty in requested.items():
            product = products[product_id]
            if product.stock < total_qty:
                raise SaleValidationError(
                    f"Not enough stock for '{product.name}' (have {product.stock}, need {total_qty})."
                )

    # --- Everything validated. Now build the sale. ---
    sale = Sale(
        customer_name=customer_name,
        customer_phone=customer_phone,
        customer_address=customer_address,
        customer_city=(customer_city or "").strip() or None,
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
    estimate_rate = None if is_stock else get_rate_for_month(date.today())
    estimate_kg_rate = None if is_stock else get_rate_per_kg()
    estimated_shipping = Decimal("0")

    for line in line_items:
        product = products[line["product_id"]]
        qty = line["qty"]
        unit_price = Decimal(str(line["unit_price"]))
        unit_cost = product.cost or Decimal("0")

        line_cbm = (product.cbm or Decimal("0")) * qty
        line_volumetric_kg = (product.volumetric_kg or Decimal("0")) * qty
        line_weight_kg = (product.actual_weight_kg or Decimal("0")) * qty

        # Each product's own shipping estimate (its CBM x this month's rate
        # + its weight x the per-kg rate); the sale's estimate is the sum.
        line_estimate = (
            None if is_stock
            else line_shipping_cost(line_cbm, line_weight_kg, estimate_rate, estimate_kg_rate)
        )

        db.session.add(SaleItem(
            sale_id=sale.id,
            product_id=product.id,
            qty=qty,
            unit_cost=unit_cost,
            unit_price=unit_price,
            line_cbm=line_cbm,
            line_volumetric_kg=line_volumetric_kg,
            line_weight_kg=line_weight_kg,
            line_shipping_estimate=line_estimate,
            variant_note=line.get("variant_note") or None,
        ))

        # Only stocked sales draw down inventory (+ audit trail)
        if is_stock:
            product.stock -= qty
            db.session.add(StockLog(product_id=product.id, change_qty=-qty, reason=f"Sale {sale.order_id}"))

        subtotal += unit_price * qty
        if line_estimate is not None:
            estimated_shipping += line_estimate

    sale.subtotal_amount = subtotal
    if is_stock:
        sale.estimated_shipping_cost = None  # no shipping on stocked sales; delivery is settled off record
    else:
        sale.estimated_shipping_cost = estimated_shipping  # rough estimate only: sum of each line's (CBM x rate + kg x per-kg rate)
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
