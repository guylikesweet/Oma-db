from datetime import date

from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required

from app.models import ShipmentBatch, Sale
from app.services.shipment_batches import (
    add_sale_to_batch, remove_sale_from_batch, mark_arrived, settle_sale_shipping, BatchValidationError,
)
from app.services.rates import get_rate_for_month

batches_bp = Blueprint("batches", __name__, url_prefix="/batches", template_folder="templates/batches")


def _attach_shipping_preview(batch):
    """
    For sales whose batch has arrived but aren't settled yet, attach a live,
    non-persisted preview of what their shipping cost would be right now —
    so there's something to bill against before committing to Settle.
    This is NOT saved anywhere; settle_sale_shipping recomputes it fresh
    (and locks it in) using whatever the rate is at the actual moment of settlement.
    """
    if batch.status != ShipmentBatch.STATUS_ARRIVED:
        return
    rate = get_rate_for_month(date.today())
    for sale in batch.sales:
        if not sale.shipping_payment_settled:
            total_cbm = sum((item.line_cbm or 0) for item in sale.items)
            sale.preview_shipping_cost = total_cbm * rate


@batches_bp.route("/<int:batch_id>")
@login_required
def batch_detail(batch_id):
    batch = ShipmentBatch.query.get_or_404(batch_id)
    _attach_shipping_preview(batch)
    # Sales eligible to be added: not cancelled, not already in a batch.
    eligible_sales = (
        Sale.query.filter(Sale.batch_id.is_(None), Sale.order_status != "Cancelled")
        .order_by(Sale.sale_date.desc())
        .limit(100)
        .all()
    )
    return render_template("batches/detail.html", batch=batch, eligible_sales=eligible_sales)


@batches_bp.route("/<int:batch_id>/add-sale", methods=("POST",))
@login_required
def add_sale(batch_id):
    sale_id = request.form.get("sale_id", type=int)
    try:
        if not sale_id:
            raise BatchValidationError("Pick a sale to add.")
        add_sale_to_batch(batch_id, sale_id)
        flash(f"Sale #{sale_id} added to batch.", "success")
    except BatchValidationError as e:
        flash(str(e), "error")
    return redirect(url_for("batches.batch_detail", batch_id=batch_id))


@batches_bp.route("/<int:batch_id>/remove-sale/<int:sale_id>", methods=("POST",))
@login_required
def remove_sale(batch_id, sale_id):
    try:
        remove_sale_from_batch(sale_id)
        flash(f"Sale #{sale_id} removed from batch.", "success")
    except BatchValidationError as e:
        flash(str(e), "error")
    return redirect(url_for("batches.batch_detail", batch_id=batch_id))


@batches_bp.route("/<int:batch_id>/mark-arrived", methods=("POST",))
@login_required
def mark_arrived_route(batch_id):
    try:
        batch = mark_arrived(batch_id)
        flash(f"Batch '{batch.name}' marked arrived. Settle each order's shipping payment individually below.", "success")
    except BatchValidationError as e:
        flash(str(e), "error")
    return redirect(url_for("batches.batch_detail", batch_id=batch_id))


@batches_bp.route("/<int:batch_id>/settle-sale/<int:sale_id>", methods=("POST",))
@login_required
def settle_sale_route(batch_id, sale_id):
    try:
        sale = settle_sale_shipping(sale_id)
        flash(
            f"Sale #{sale.id} shipping settled at {sale.actual_shipping_cost} "
            f"(this month's rate). Final profit: {sale.profit}.",
            "success",
        )
    except BatchValidationError as e:
        flash(str(e), "error")
    return redirect(url_for("batches.batch_detail", batch_id=batch_id))
