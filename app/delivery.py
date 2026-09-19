from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required

from app.models import Delivery
from app.services.delivery import (
    get_ready_for_delivery_sales, find_phone_matches, find_name_matches, find_location_matches,
    create_delivery, update_delivery_status, DeliveryValidationError,
)

delivery_bp = Blueprint("delivery", __name__, url_prefix="/delivery", template_folder="templates/delivery")


@delivery_bp.route("/ready")
@login_required
def ready():
    sales = get_ready_for_delivery_sales()
    phone_matches = find_phone_matches()
    name_matches = find_name_matches()
    location_matches = find_location_matches()
    return render_template(
        "delivery/ready.html",
        sales=sales,
        phone_matches=phone_matches,
        name_matches=name_matches,
        location_matches=location_matches,
    )


@delivery_bp.route("/create", methods=("POST",))
@login_required
def create():
    sale_ids = [int(x) for x in request.form.getlist("sale_ids[]") if x]
    method = request.form.get("method", "").strip()
    consolidation_type = request.form.get("consolidation_type") or None
    delivery_address = request.form.get("delivery_address", "").strip() or None
    notes = request.form.get("notes", "").strip() or None

    try:
        delivery = create_delivery(
            sale_ids, method,
            consolidation_type=consolidation_type,
            delivery_address=delivery_address,
            notes=notes,
        )
        flash(f"Delivery #{delivery.id} created for {len(sale_ids)} sale(s).", "success")
        return redirect(url_for("delivery.delivery_detail", delivery_id=delivery.id))
    except DeliveryValidationError as e:
        flash(str(e), "error")
        return redirect(url_for("delivery.ready"))


@delivery_bp.route("/<int:delivery_id>")
@login_required
def delivery_detail(delivery_id):
    delivery = Delivery.query.get_or_404(delivery_id)
    return render_template("delivery/detail.html", delivery=delivery)


@delivery_bp.route("/<int:delivery_id>/status", methods=("POST",))
@login_required
def set_status(delivery_id):
    new_status = request.form.get("status", "")
    try:
        update_delivery_status(delivery_id, new_status)
        flash(f"Delivery #{delivery_id} status updated to {new_status}.", "success")
    except DeliveryValidationError as e:
        flash(str(e), "error")
    return redirect(url_for("delivery.delivery_detail", delivery_id=delivery_id))
