from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required

from app.models import Sale, Shipping
from app.services.shipping import create_shipping, update_shipping, search_shipping, ShippingValidationError

shipping_bp = Blueprint("shipping", __name__, url_prefix="/shipping", template_folder="templates/shipping")


@shipping_bp.route("/new/<int:sale_id>", methods=("GET", "POST"))
@login_required
def new_shipping(sale_id):
    sale = Sale.query.get_or_404(sale_id)

    if request.method == "POST":
        try:
            shipping = create_shipping(
                sale_id=sale.id,
                courier=request.form.get("courier", "").strip(),
                tracking_number=request.form.get("tracking_number", "").strip(),
                notes=request.form.get("notes", "").strip(),
            )
            flash(f"Shipment created for Sale #{sale.id}. Chargeable weight: {shipping.chargeable_weight_kg}kg.", "success")
            return redirect(url_for("shipping.shipping_detail", shipping_id=shipping.id))
        except ShippingValidationError as e:
            flash(str(e), "error")
            return redirect(url_for("sales.sale_detail", sale_id=sale.id))

    return render_template("shipping/new.html", sale=sale)


@shipping_bp.route("/<int:shipping_id>")
@login_required
def shipping_detail(shipping_id):
    shipping = Shipping.query.get_or_404(shipping_id)
    return render_template("shipping/detail.html", shipping=shipping)


@shipping_bp.route("/<int:shipping_id>/update", methods=("POST",))
@login_required
def update(shipping_id):
    try:
        update_shipping(
            shipping_id,
            courier=request.form.get("courier"),
            tracking_number=request.form.get("tracking_number"),
            shipping_status=request.form.get("shipping_status"),
            notes=request.form.get("notes"),
        )
        flash("Shipment updated.", "success")
    except ShippingValidationError as e:
        flash(str(e), "error")
    return redirect(url_for("shipping.shipping_detail", shipping_id=shipping_id))


@shipping_bp.route("/search")
@login_required
def search():
    tracking_number = request.args.get("tracking_number", "").strip()
    state = request.args.get("state", "").strip()
    results = []
    if tracking_number or state:
        results = search_shipping(tracking_number=tracking_number or None, state=state or None)
    return render_template("shipping/search.html", results=results,
                            tracking_number=tracking_number, state=state)
