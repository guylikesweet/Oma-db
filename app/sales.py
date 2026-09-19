from itertools import zip_longest
from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required

from app.models import Product, Sale
from app.services.sales import create_sale, update_sale_status, SaleValidationError

sales_bp = Blueprint("sales", __name__, url_prefix="/sales", template_folder="templates/sales")


@sales_bp.route("/new", methods=("GET", "POST"))
@login_required
def new_sale():
    if request.method == "POST":
        product_ids = request.form.getlist("product_id[]")
        qtys = request.form.getlist("qty[]")
        unit_prices = request.form.getlist("unit_price[]")
        variant_notes = request.form.getlist("variant_note[]")

        line_items = []
        for pid, qty, price, variant_note in zip_longest(product_ids, qtys, unit_prices, variant_notes, fillvalue=""):
            if not pid:
                continue
            try:
                line_items.append({
                    "product_id": int(pid),
                    "qty": int(qty),
                    "unit_price": price,
                    "variant_note": variant_note.strip() if variant_note else None,
                })
            except (ValueError, TypeError):
                flash("Every line needs a valid quantity and price.", "error")
                return redirect(url_for("sales.new_sale"))

        try:
            sale = create_sale(
                customer_name=request.form.get("customer_name", "").strip(),
                customer_phone=request.form.get("customer_phone", "").strip(),
                customer_address=request.form.get("customer_address", "").strip(),
                customer_state=request.form.get("customer_state", "").strip(),
                payment_status=request.form.get("payment_status", "Paid"),
                notes=request.form.get("notes", "").strip(),
                line_items=line_items,
            )
            flash(f"Sale #{sale.id} created. Estimated shipping: {sale.estimated_shipping_cost}", "success")
            return redirect(url_for("sales.sale_detail", sale_id=sale.id))
        except SaleValidationError as e:
            flash(str(e), "error")
            return redirect(url_for("sales.new_sale"))

    products = Product.query.order_by(Product.name).all()
    return render_template("sales/new.html", products=products)


@sales_bp.route("/<int:sale_id>")
@login_required
def sale_detail(sale_id):
    sale = Sale.query.get_or_404(sale_id)
    return render_template("sales/detail.html", sale=sale)


@sales_bp.route("/<int:sale_id>/status", methods=("POST",))
@login_required
def set_status(sale_id):
    new_status = request.form.get("order_status", "")
    try:
        update_sale_status(sale_id, new_status)
        flash(f"Sale #{sale_id} status updated to {new_status}.", "success")
    except SaleValidationError as e:
        flash(str(e), "error")
    return redirect(url_for("sales.sale_detail", sale_id=sale_id))
