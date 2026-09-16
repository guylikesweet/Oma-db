"""
Dashboard logic — Module B from the blueprint.
"""
from datetime import date, timedelta
from decimal import Decimal

from sqlalchemy import func

from app import db
from app.models import Sale, Product, Shipping

LOW_STOCK_THRESHOLD = 5


def get_kpis():
    today = date.today()

    sales_today_row = (
        db.session.query(
            func.coalesce(func.sum(Sale.total_amount), 0),
            func.coalesce(func.sum(Sale.profit), 0),
        )
        .filter(Sale.sale_date == today, Sale.order_status != "Cancelled")
        .first()
    )
    sales_today_total = sales_today_row[0] or Decimal("0")
    profit_today_total = sales_today_row[1] or Decimal("0")

    pending_shipments = (
        Shipping.query.filter(Shipping.shipping_status != "Delivered").count()
    )

    low_stock_products = (
        Product.query.filter(Product.stock < LOW_STOCK_THRESHOLD)
        .order_by(Product.stock.asc())
        .all()
    )

    return {
        "sales_today": sales_today_total,
        "profit_today": profit_today_total,
        "pending_shipments": pending_shipments,
        "low_stock_products": low_stock_products,
        "low_stock_count": len(low_stock_products),
    }


def get_sales_last_30_days():
    start_date = date.today() - timedelta(days=29)

    rows = (
        db.session.query(Sale.sale_date, func.coalesce(func.sum(Sale.total_amount), 0))
        .filter(Sale.sale_date >= start_date, Sale.order_status != "Cancelled")
        .group_by(Sale.sale_date)
        .all()
    )
    totals_by_date = {row[0]: float(row[1]) for row in rows}

    labels = []
    values = []
    for i in range(30):
        d = start_date + timedelta(days=i)
        labels.append(d.strftime("%b %d"))
        values.append(totals_by_date.get(d, 0))

    return labels, values
