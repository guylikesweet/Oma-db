"""
Reports logic. No profit/loss anywhere — subtotal, shipping estimate/actual,
and total only.
"""
from datetime import date, timedelta

from app.models import Sale, Product


def get_sales_in_range(start_date, end_date):
    return (
        Sale.query.filter(Sale.sale_date >= start_date, Sale.sale_date <= end_date)
        .order_by(Sale.sale_date.desc(), Sale.id.desc())
        .all()
    )


def sales_report(start_date=None, end_date=None):
    """Filtered sales list + aggregate totals for the Sales Report screen."""
    if not end_date:
        end_date = date.today()
    if not start_date:
        start_date = end_date - timedelta(days=29)

    sales = get_sales_in_range(start_date, end_date)

    totals = {
        "subtotal": sum((s.subtotal_amount or 0) for s in sales),
        "estimated_shipping": sum((s.estimated_shipping_cost or 0) for s in sales),
        "actual_shipping": sum((s.actual_shipping_cost or 0) for s in sales),
        "total": sum((s.total_amount or 0) for s in sales),
    }

    return {
        "sales": sales,
        "totals": totals,
        "start_date": start_date,
        "end_date": end_date,
    }


SALES_CSV_HEADERS = [
    "id", "order_id", "sale_date", "customer_name", "customer_phone", "customer_state",
    "order_status", "payment_status", "subtotal_amount", "estimated_shipping_cost",
    "actual_shipping_cost", "shipping_payment_settled", "total_amount",
    "cogs", "gross_profit", "gross_margin_percent", "net_profit",
]


def sales_csv_rows(start_date=None, end_date=None):
    if not end_date:
        end_date = date.today()
    if not start_date:
        start_date = end_date - timedelta(days=3650)  # effectively "all time" if unset

    for s in get_sales_in_range(start_date, end_date):
        cogs = sum((item.unit_cost or 0) * (item.qty or 0) for item in s.items)
        gross_profit = (s.subtotal_amount or 0) - cogs
        gross_margin = (gross_profit / s.subtotal_amount * 100) if s.subtotal_amount else 0
        yield [
            s.id, s.order_id, s.sale_date, s.customer_name, s.customer_phone, s.customer_state,
            s.order_status, s.payment_status, s.subtotal_amount, s.estimated_shipping_cost,
            s.actual_shipping_cost, s.shipping_payment_settled, s.total_amount,
            cogs, gross_profit, gross_margin, s.profit,
        ]


SHIPPING_CSV_HEADERS = [
    "sale_id", "customer_name", "batch_name", "batch_status",
    "estimated_shipping_cost", "actual_shipping_cost", "shipping_payment_settled",
]


def shipping_csv_rows():
    """Shipping-cost data sourced from Sale + its ShipmentBatch (the old, separate
    per-sale Shipping/tracking module has been removed — batches replaced it)."""
    for s in Sale.query.filter(Sale.batch_id.isnot(None)).order_by(Sale.id).all():
        yield [
            s.id, s.customer_name, s.batch.name if s.batch else "", s.batch.status if s.batch else "",
            s.estimated_shipping_cost, s.actual_shipping_cost, s.shipping_payment_settled,
        ]


INVENTORY_CSV_HEADERS = [
    "id", "name", "sku",
    "supplier_cost", "inbound_shipping_cost", "landed_cost",
    "markup_percent", "selling_price", "gross_profit_per_unit",
    "gross_margin_percent", "stock", "inventory_cost_value",
    "potential_sales_value", "potential_gross_profit",
    "length_cm", "width_cm", "height_cm",
    "cbm", "volumetric_kg", "actual_weight_kg",
]


def inventory_csv_rows():
    for p in Product.query.order_by(Product.name).all():
        landed = p.cost or 0
        selling = p.selling_price or 0
        gross_profit = selling - landed
        gross_margin = (gross_profit / selling * 100) if selling else 0
        stock = p.stock or 0
        yield [
            p.id, p.name, p.sku,
            p.supplier_cost or 0, p.inbound_shipping_cost or 0, landed,
            p.markup_percent or 0, selling, gross_profit, gross_margin,
            stock, landed * stock, selling * stock, gross_profit * stock,
            p.length_cm, p.width_cm, p.height_cm,
            p.cbm, p.volumetric_kg, p.actual_weight_kg,
        ]
