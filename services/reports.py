"""
Reports / Settings logic — Module F from the blueprint.
"""
from datetime import date, timedelta

from app.models import Sale, Shipping, Product


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
        "shipping": sum((s.estimated_shipping_cost or 0) for s in sales),
        "total": sum((s.total_amount or 0) for s in sales),
        "profit": sum((s.profit or 0) for s in sales),
    }

    return {
        "sales": sales,
        "totals": totals,
        "start_date": start_date,
        "end_date": end_date,
    }


SALES_CSV_HEADERS = [
    "id", "sale_date", "customer_name", "customer_phone", "customer_state",
    "order_status", "payment_status", "subtotal_amount", "estimated_shipping_cost",
    "total_amount", "profit",
]


def sales_csv_rows(start_date=None, end_date=None):
    if not end_date:
        end_date = date.today()
    if not start_date:
        start_date = end_date - timedelta(days=3650)  # effectively "all time" if unset

    for s in get_sales_in_range(start_date, end_date):
        yield [
            s.id, s.sale_date, s.customer_name, s.customer_phone, s.customer_state,
            s.order_status, s.payment_status, s.subtotal_amount, s.estimated_shipping_cost,
            s.total_amount, s.profit,
        ]


SHIPPING_CSV_HEADERS = [
    "id", "sale_id", "courier", "tracking_number", "chargeable_weight_kg",
    "total_cbm", "shipping_status", "shipped_at", "delivered_at",
]


def shipping_csv_rows():
    for s in Shipping.query.order_by(Shipping.id).all():
        yield [
            s.id, s.sale_id, s.courier, s.tracking_number, s.chargeable_weight_kg,
            s.total_cbm, s.shipping_status, s.shipped_at, s.delivered_at,
        ]


INVENTORY_CSV_HEADERS = [
    "id", "name", "sku", "cost", "length_cm", "width_cm", "height_cm",
    "cbm", "volumetric_kg", "actual_weight_kg", "stock",
]


def inventory_csv_rows():
    for p in Product.query.order_by(Product.name).all():
        yield [
            p.id, p.name, p.sku, p.cost, p.length_cm, p.width_cm, p.height_cm,
            p.cbm, p.volumetric_kg, p.actual_weight_kg, p.stock,
        ]
