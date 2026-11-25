from datetime import datetime, timedelta
from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required, current_user

from app.access import admin_required, password_required
from app.models import ShipmentBatch, Sale
from app.services.shipment_batches import (
    create_batch, add_sale_to_batch, remove_sale_from_batch, update_batch_sales,
    mark_arrived, mark_unarrived, settle_sale_shipping, BatchValidationError,
)

batches_bp = Blueprint("batches", __name__, url_prefix="/batches", template_folder="templates/batches")


@batches_bp.route("/create", methods=("GET", "POST"))
@login_required
def create_batch_route():
    eligible_sales = (
        Sale.query.filter(
            Sale.batch_id.is_(None),
            Sale.order_status != "Cancelled",
            Sale.sale_type != "stock",
            Sale.shipping_payment_settled.is_(False),
            Sale.delivery_id.is_(None),
        )
        .order_by(Sale.sale_date.desc(), Sale.id.desc())
        .all()
    )
    if request.method == "POST":
        try:
            batch = create_batch(
                request.form.get("name", ""),
                notes=request.form.get("notes") or None,
                transport_mode=request.form.get("transport_mode", "sea"),
                sale_ids=request.form.getlist("sale_ids"),
                user=current_user,
            )
            flash(
                f"Shipment batch '{batch.name}' created and locked with {len(batch.sales)} sale(s).",
                "success",
            )
            return redirect(url_for("batches.batch_detail", batch_id=batch.id))
        except (BatchValidationError, ValueError) as e:
            flash(str(e), "error")
    return render_template("batches/create.html", eligible_sales=eligible_sales)


@batches_bp.route("/<int:batch_id>")
@login_required
def batch_detail(batch_id):
    batch = ShipmentBatch.query.get_or_404(batch_id)
    reminders_available_at = (
        batch.created_at + timedelta(days=45) if batch.created_at else None
    )
    reminders_available = bool(
        batch.status == ShipmentBatch.STATUS_IN_TRANSIT
        and reminders_available_at
        and datetime.utcnow() >= reminders_available_at
    )
    return render_template(
        "batches/detail.html",
        batch=batch,
        reminders_available=reminders_available,
        reminders_available_at=reminders_available_at,
    )


@batches_bp.route("/<int:batch_id>/remind-customers")
@login_required
def remind_customers(batch_id):
    from app.services.payments import build_batch_payment_reminders, PaymentError
    batch = ShipmentBatch.query.get_or_404(batch_id)
    try:
        notices = build_batch_payment_reminders(batch)
    except PaymentError as e:
        flash(str(e), "error")
        return redirect(url_for("batches.batch_detail", batch_id=batch.id))
    return render_template(
        "batches/notices.html",
        batch=batch,
        notices=notices,
        heading="Remind customers of shipping cost",
        intro="One WhatsApp reminder per normalized customer phone number within this batch.",
    )


@batches_bp.route("/<int:batch_id>/notify-customers")
@login_required
def notify_customers(batch_id):
    from app.services.notifications import build_batch_arrival_notices, NotificationError
    batch = ShipmentBatch.query.get_or_404(batch_id)
    try:
        notices = build_batch_arrival_notices(batch)
    except NotificationError as e:
        flash(str(e), "error")
        return redirect(url_for("batches.batch_detail", batch_id=batch.id))
    return render_template(
        "batches/notices.html",
        batch=batch,
        notices=notices,
        heading="Notify customers of arrival",
        intro="One arrival message per normalized customer phone number within this batch.",
    )


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


@batches_bp.route("/<int:batch_id>/bulk-sales", methods=("POST",))
@login_required
def bulk_sales(batch_id):
    try:
        add_ids = [
            int(x)
            for x in request.form.getlist("add_sale_ids")
            if str(x).strip()
        ]
        remove_ids = [
            int(x)
            for x in request.form.getlist("remove_sale_ids")
            if str(x).strip()
        ]
        if not add_ids and not remove_ids:
            raise BatchValidationError("Select at least one sale to add or remove.")
        update_batch_sales(
            batch_id,
            add_sale_ids=add_ids,
            remove_sale_ids=remove_ids,
        )
        flash(
            f"{len(add_ids)} sale(s) added and {len(remove_ids)} sale(s) removed.",
            "success",
        )
    except BatchValidationError as e:
        flash(str(e), "error")
    return redirect(url_for("batches.batch_detail", batch_id=batch_id))


@batches_bp.route("/<int:batch_id>/mark-arrived", methods=("POST",))
@admin_required
@password_required
def mark_arrived_route(batch_id):
    try:
        batch = mark_arrived(batch_id)
        flash(f"Batch '{batch.name}' marked arrived. Actual shipping cost calculated for {len(batch.sales)} sale(s). Settle each order's payment below.", "success")
    except BatchValidationError as e:
        flash(str(e), "error")
    return redirect(url_for("batches.batch_detail", batch_id=batch_id))


@batches_bp.route("/<int:batch_id>/undo-arrival", methods=("POST",))
@admin_required
@password_required
def undo_arrival_route(batch_id):
    try:
        batch = mark_unarrived(batch_id)
        flash(
            f"Batch '{batch.name}' returned to In Transit. "
            f"Sales are back on {batch.mode_label.lower()} tracking.",
            "success",
        )
    except BatchValidationError as e:
        flash(str(e), "error")
    return redirect(url_for("batches.batch_detail", batch_id=batch_id))


@batches_bp.route("/<int:batch_id>/settle-sale/<int:sale_id>", methods=("POST",))
@login_required
@password_required
def settle_sale_route(batch_id, sale_id):
    try:
        sale = settle_sale_shipping(sale_id)
        flash(f"Sale #{sale.id} shipping payment settled. It's now ready for delivery.", "success")
    except BatchValidationError as e:
        flash(str(e), "error")
    return redirect(url_for("batches.batch_detail", batch_id=batch_id))
