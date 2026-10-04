from itertools import zip_longest
from flask import Blueprint, render_template, request, redirect, url_for, flash, send_file
from flask_login import login_required, current_user

from app.models import Product, Sale
from app.services.sales import create_sale, update_sale_status, update_sale_payment_status, SaleValidationError
from app.services.invoices import generate_invoice_pdf
from app.services.journey import journey_for, current_stage_key, set_manual_stage_bulk, JourneyError, manual_stages_for

sales_bp = Blueprint("sales", __name__, url_prefix="/sales", template_folder="templates/sales")


@sales_bp.route("/new", methods=("GET", "POST"))
@login_required
def new_sale():
    sale_type = "stock" if (request.values.get("type") or "").lower() == "stock" else "preorder"
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
                return redirect(url_for("sales.new_sale", type=sale_type))

        try:
            sale = create_sale(
                customer_name=request.form.get("customer_name", "").strip(),
                customer_phone=request.form.get("customer_phone", "").strip(),
                customer_address=request.form.get("customer_address", "").strip(),
                customer_state=request.form.get("customer_state", "").strip(),
                payment_status=request.form.get("payment_status", "Paid"),
                notes=request.form.get("notes", "").strip(),
                line_items=line_items,
                sale_type=sale_type,
            )
            if sale.is_stock_sale:
                flash(f"Stock sale {sale.order_id} created.", "success")
            else:
                flash(f"Order {sale.order_id} created. Estimated shipping: {sale.estimated_shipping_cost}", "success")
            return redirect(url_for("sales.sale_detail", sale_id=sale.id))
        except SaleValidationError as e:
            flash(str(e), "error")
            return redirect(url_for("sales.new_sale", type=sale_type))

    products = Product.query.order_by(Product.name).all()
    return render_template("sales/new.html", products=products, sale_type=sale_type)


@sales_bp.route("/journey", methods=("GET", "POST"))
@login_required
def journey_board():
    if request.method == "POST":
        stage = (request.form.get("stage") or "").strip()
        sale_ids = [int(x) for x in request.form.getlist("sale_ids") if x.isdigit()]
        sales = Sale.query.filter(Sale.id.in_(sale_ids)).all() if sale_ids else []
        try:
            updated, unchanged, skipped = set_manual_stage_bulk(sales, stage, user_id=current_user.id)
            from app import db
            db.session.commit()
            message = f"{updated} order(s) moved"
            if unchanged: message += f", {unchanged} already there"
            if skipped: message += f"; {len(skipped)} skipped"
            flash(message + ".", "success" if not skipped else "error")
        except JourneyError as e:
            from app import db
            db.session.rollback()
            flash(str(e), "error")
        return redirect(url_for("sales.journey_board"))

    rows = []
    sales = Sale.query.filter(Sale.order_status != "Cancelled").order_by(Sale.created_at.desc()).all()
    for sale in sales:
        journey = journey_for(sale)
        rows.append({
            "sale": sale,
            "stage": journey["current_label"],
            "movable": bool(manual_stages_for(sale)) and journey["current"] in ("confirmed", "fulfilled", "cn_transit", "packing"),
        })
    return render_template("sales/journey.html", rows=rows)


@sales_bp.route("/<int:sale_id>")
@login_required
def sale_detail(sale_id):
    sale = Sale.query.get_or_404(sale_id)
    return render_template("sales/detail.html", sale=sale, journey=journey_for(sale), tracking_url=url_for("verify.track", tracking_code=sale.public_tracking_code, _external=True))


@sales_bp.route("/<int:sale_id>/invoice.pdf")
@login_required
def invoice_pdf(sale_id):
    sale = Sale.query.get_or_404(sale_id)
    pdf_buf = generate_invoice_pdf(sale)
    return send_file(
        pdf_buf,
        mimetype="application/pdf",
        as_attachment=False,
        download_name=f"invoice-{sale.order_id or sale.id}.pdf",
    )


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


@sales_bp.route("/<int:sale_id>/payment-status", methods=("POST",))
@login_required
def set_payment_status(sale_id):
    new_payment_status = request.form.get("payment_status", "")
    try:
        update_sale_payment_status(sale_id, new_payment_status)
        flash(f"Sale #{sale_id} payment marked {new_payment_status}.", "success")
    except SaleValidationError as e:
        flash(str(e), "error")
    return redirect(url_for("sales.sale_detail", sale_id=sale_id))
