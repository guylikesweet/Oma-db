"""
Receipt downloads for the mobile app: the same receipt as a PNG or JPG photo
(for WhatsApp) or as a small 80 mm PDF.

Only PAID, non-cancelled orders get one; anything else answers 400 with a
plain explanation (the app shows it). See app/services/invoices.py.
"""
from flask import Blueprint, jsonify, send_file

from app.api import require_api_token
from app.models import Sale
from app.services.invoices import (
    ReceiptNotAllowed,
    generate_invoice_image,
    generate_invoice_pdf,
)

receipts_bp = Blueprint("receipts", __name__, url_prefix="/api")


def _file_name(sale, ext):
    return f"receipt-{sale.order_id or sale.id}.{ext}"


def _no_store(response):
    response.headers["Cache-Control"] = "private, no-store"
    return response


def _send_image(sale_id, fmt):
    sale = Sale.query.get_or_404(sale_id)
    try:
        buf, mimetype, ext = generate_invoice_image(sale, fmt)
    except ReceiptNotAllowed as exc:
        return jsonify({"error": str(exc)}), 400
    return _no_store(send_file(
        buf, mimetype=mimetype, as_attachment=True, download_name=_file_name(sale, ext),
    ))


@receipts_bp.route("/v1/sales/<int:sale_id>/receipt.png", methods=("GET",))
@require_api_token
def receipt_png(sale_id):
    return _send_image(sale_id, "png")


@receipts_bp.route("/v1/sales/<int:sale_id>/receipt.jpg", methods=("GET",))
@require_api_token
def receipt_jpg(sale_id):
    return _send_image(sale_id, "jpg")


@receipts_bp.route("/v1/sales/<int:sale_id>/receipt.pdf", methods=("GET",))
@require_api_token
def receipt_pdf(sale_id):
    sale = Sale.query.get_or_404(sale_id)
    try:
        pdf = generate_invoice_pdf(sale)
    except ReceiptNotAllowed as exc:
        return jsonify({"error": str(exc)}), 400
    return _no_store(send_file(
        pdf, mimetype="application/pdf", as_attachment=True,
        download_name=_file_name(sale, "pdf"),
    ))
