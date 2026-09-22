import base64
from decimal import Decimal, InvalidOperation

from flask import Blueprint, render_template, request, redirect, url_for, flash, send_file
from flask_login import login_required

from app.models import Delivery
from app.services.delivery import (
    get_ready_for_delivery_sales, find_phone_matches, find_name_matches,
    create_delivery, update_delivery_status, DeliveryValidationError,
)
from app.services.labels import get_label_context, generate_label_pdf, label_ready
from app import db

delivery_bp = Blueprint("delivery", __name__, url_prefix="/delivery", template_folder="templates/delivery")


@delivery_bp.route("/ready")
@login_required
def ready():
    sales = get_ready_for_delivery_sales()
    phone_matches = find_phone_matches()
    name_matches = find_name_matches()
    return render_template(
        "delivery/ready.html",
        sales=sales,
        phone_matches=phone_matches,
        name_matches=name_matches,
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


@delivery_bp.route("/<int:delivery_id>/label/prepare", methods=("GET", "POST"))
@login_required
def label_prepare(delivery_id):
    """Weight, dimensions, and remarks must be entered before a label can be
    generated — captured fresh here rather than pulled from product records,
    since the actual packed parcel may not match the original dimensions."""
    delivery = Delivery.query.get_or_404(delivery_id)

    if request.method == "POST":
        try:
            weight = Decimal(request.form.get("package_weight_kg", "").strip())
            if weight <= 0:
                raise ValueError
        except (InvalidOperation, ValueError, TypeError):
            flash("Enter a valid weight in kg (a number greater than 0).", "error")
            return redirect(url_for("delivery.label_prepare", delivery_id=delivery_id))

        dimensions = request.form.get("package_dimensions", "").strip()
        if not dimensions:
            flash("Enter the package dimensions.", "error")
            return redirect(url_for("delivery.label_prepare", delivery_id=delivery_id))

        delivery.package_weight_kg = weight
        delivery.package_dimensions = dimensions
        delivery.remarks = request.form.get("remarks", "").strip() or None
        db.session.commit()
        return redirect(url_for("delivery.label", delivery_id=delivery_id))

    return render_template("delivery/label_prepare.html", delivery=delivery)


@delivery_bp.route("/<int:delivery_id>/label")
@login_required
def label(delivery_id):
    delivery = Delivery.query.get_or_404(delivery_id)
    if not label_ready(delivery):
        flash("Enter weight and dimensions first.", "error")
        return redirect(url_for("delivery.label_prepare", delivery_id=delivery_id))

    ctx = get_label_context(delivery)
    barcode_b64 = base64.b64encode(ctx["barcode_png"]).decode("ascii") if ctx["barcode_png"] else None
    return render_template("delivery/label.html", barcode_b64=barcode_b64, **ctx)


@delivery_bp.route("/<int:delivery_id>/label.pdf")
@login_required
def label_pdf(delivery_id):
    delivery = Delivery.query.get_or_404(delivery_id)
    if not label_ready(delivery):
        flash("Enter weight and dimensions first.", "error")
        return redirect(url_for("delivery.label_prepare", delivery_id=delivery_id))

    pdf_buf = generate_label_pdf(delivery)
    return send_file(
        pdf_buf,
        mimetype="application/pdf",
        as_attachment=True,
        download_name=f"label-{delivery.sales[0].order_id if delivery.sales else delivery.id}.pdf",
    )
