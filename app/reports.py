import csv
import io
from datetime import date, datetime

from flask import Blueprint, render_template, request, Response
from flask_login import login_required

from app.services.reports import (
    sales_report,
    sales_csv_rows, SALES_CSV_HEADERS,
    shipping_csv_rows, SHIPPING_CSV_HEADERS,
    inventory_csv_rows, INVENTORY_CSV_HEADERS,
)

reports_bp = Blueprint("reports", __name__, url_prefix="/reports", template_folder="templates/reports")


def _parse_date(value):
    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        return None


def _csv_response(headers, rows, filename):
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(headers)
    for row in rows:
        writer.writerow(row)
    return Response(
        buf.getvalue(),
        mimetype="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )


@reports_bp.route("/")
@login_required
def index():
    start_date = _parse_date(request.args.get("start_date"))
    end_date = _parse_date(request.args.get("end_date"))
    data = sales_report(start_date=start_date, end_date=end_date)
    return render_template("reports/index.html", **data)


@reports_bp.route("/sales.csv")
@login_required
def sales_csv():
    start_date = _parse_date(request.args.get("start_date"))
    end_date = _parse_date(request.args.get("end_date"))
    filename = f"sales_report_{date.today().isoformat()}.csv"
    return _csv_response(SALES_CSV_HEADERS, sales_csv_rows(start_date, end_date), filename)


@reports_bp.route("/shipping.csv")
@login_required
def shipping_csv():
    filename = f"shipping_report_{date.today().isoformat()}.csv"
    return _csv_response(SHIPPING_CSV_HEADERS, shipping_csv_rows(), filename)


@reports_bp.route("/inventory.csv")
@login_required
def inventory_csv():
    filename = f"inventory_report_{date.today().isoformat()}.csv"
    return _csv_response(INVENTORY_CSV_HEADERS, inventory_csv_rows(), filename)
