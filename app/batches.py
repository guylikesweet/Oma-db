from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required

from app.models import ShipmentBatch, Sale
from app.services.shipment_batches import (
    add_sale_to_batch, remove_sale_from_batch, mark_arrived, mark_payment_settled, BatchValidationError,
)

batches_bp = Blueprint("batches", __name__, url_prefix="/batches", template_folder="templates/batches")


@batches_bp.route("/<int:batch_id>")
@login_required
def batch_detail(batch_id):
    batch = ShipmentBatch.query.get_or_404(batch_id)
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
        flash(f"Batch '{batch.name}' marked arrived. Actual shipping cost locked in for {len(batch.sales)} sale(s).", "success")
    except BatchValidationError as e:
        flash(str(e), "error")
    return redirect(url_for("batches.batch_detail", batch_id=batch_id))


@batches_bp.route("/<int:batch_id>/mark-settled", methods=("POST",))
@login_required
def mark_settled_route(batch_id):
    try:
        mark_payment_settled(batch_id)
        flash("Batch marked as payment settled — ready for delivery.", "success")
    except BatchValidationError as e:
        flash(str(e), "error")
    return redirect(url_for("batches.batch_detail", batch_id=batch_id))
