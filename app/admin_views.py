from flask import redirect, url_for, request, flash
from flask_admin import Admin, AdminIndexView, expose
from flask_admin.contrib.sqla import ModelView
from flask_login import current_user
from werkzeug.security import generate_password_hash
from markupsafe import Markup

from app import db
from app.models import (
    User,
    Product,
    CourierRate,
    Sale,
    SaleItem,
    Shipping,
    StockLog,
)


# ---------------------------------------------------------------------------
# Access control mixin — every admin view requires a logged-in user
# ---------------------------------------------------------------------------
class SecureModelView(ModelView):
    def is_accessible(self):
        return current_user.is_authenticated

    def inaccessible_callback(self, name, **kwargs):
        return redirect(url_for("auth.login", next=request.url))


class SecureAdminIndexView(AdminIndexView):
    def is_accessible(self):
        return current_user.is_authenticated

    def inaccessible_callback(self, name, **kwargs):
        return redirect(url_for("auth.login", next=request.url))


# ---------------------------------------------------------------------------
# USERS — never expose/edit password_hash directly; set via a plain field
# ---------------------------------------------------------------------------
class UserView(SecureModelView):
    column_list = ("id", "username", "created_at")
    form_columns = ("username",)
    form_extra_fields = {}

    can_view_details = True

    def on_model_change(self, form, model, is_created):
        # New users are created with a default password they must change on first login.
        if is_created:
            model.password_hash = generate_password_hash("changeme123")
        super().on_model_change(form, model, is_created)


# ---------------------------------------------------------------------------
# PRODUCTS — cbm / volumetric_kg are DB-generated (read-only). Stock is
# adjusted only through the dedicated adjust-stock route so every change
# is written to stock_log (audit trail), never edited directly.
# ---------------------------------------------------------------------------
class ProductView(SecureModelView):
    column_list = (
        "id", "name", "sku", "cost", "length_cm", "width_cm", "height_cm",
        "cbm", "volumetric_kg", "actual_weight_kg", "stock", "adjust_stock_link",
    )
    column_labels = {"adjust_stock_link": "Stock Adjustment"}
    form_columns = (
        "name", "sku", "cost", "length_cm", "width_cm", "height_cm", "actual_weight_kg",
    )
    column_sortable_list = ("id", "name", "sku", "cost", "stock")
    column_searchable_list = ("name", "sku")

    def _adjust_stock_formatter(view, context, model, name):
        url = url_for("product.adjust_stock_view", product_id=model.id)
        return Markup(f'<a href="{url}" class="btn btn-xs btn-primary">Adjust Stock</a>')

    column_formatters = {"adjust_stock_link": _adjust_stock_formatter}

    @expose("/adjust-stock/<int:product_id>", methods=("GET", "POST"))
    def adjust_stock_view(self, product_id):
        if not self.is_accessible():
            return self.inaccessible_callback("adjust_stock_view")

        product = Product.query.get_or_404(product_id)

        if request.method == "POST":
            try:
                change_qty = int(request.form.get("change_qty", "0"))
            except ValueError:
                change_qty = 0
            reason = request.form.get("reason", "").strip() or "Manual adjustment"

            if change_qty == 0:
                flash("Enter a non-zero quantity (positive to add stock, negative to remove).", "error")
            elif product.stock + change_qty < 0:
                flash(f"Cannot reduce stock below zero (current stock: {product.stock}).", "error")
            else:
                product.stock += change_qty
                db.session.add(StockLog(product_id=product.id, change_qty=change_qty, reason=reason))
                db.session.commit()
                flash(f"Stock updated: {product.name} is now {product.stock}.", "success")
                return redirect(url_for("product.index_view"))

        logs = (
            StockLog.query.filter_by(product_id=product.id)
            .order_by(StockLog.created_at.desc())
            .limit(20)
            .all()
        )
        return self.render("admin/adjust_stock.html", product=product, logs=logs)


# ---------------------------------------------------------------------------
# COURIER RATES
# ---------------------------------------------------------------------------
class CourierRateView(SecureModelView):
    column_list = ("id", "state", "rate_per_cbm")
    form_columns = ("state", "rate_per_cbm")
    column_sortable_list = ("state", "rate_per_cbm")


# ---------------------------------------------------------------------------
# SALES, SALE ITEMS, SHIPPING, STOCK LOG — generic secured CRUD for now.
# Sale-creation business logic (auto totals, stock deduction) lands in Stage 3.
# ---------------------------------------------------------------------------
class SaleView(SecureModelView):
    column_list = (
        "id", "sale_date", "customer_name", "customer_state", "order_status",
        "subtotal_amount", "estimated_shipping_cost", "total_amount", "profit", "payment_status",
    )
    column_searchable_list = ("customer_name", "customer_phone")
    column_filters = ("order_status", "payment_status", "customer_state", "sale_date")
    # Full item-line creation logic (Module D) arrives in Stage 3.
    form_columns = (
        "customer_name", "customer_phone", "customer_address", "customer_state",
        "order_status", "payment_status", "notes",
    )


class SaleItemView(SecureModelView):
    column_list = ("id", "sale_id", "product_id", "qty", "unit_cost", "unit_price", "line_shipping_estimate")
    form_columns = ("sale_id", "product_id", "qty", "unit_cost", "unit_price")


class ShippingView(SecureModelView):
    column_list = (
        "id", "sale_id", "courier", "tracking_number",
        "chargeable_weight_kg", "total_cbm", "shipping_status", "shipped_at", "delivered_at",
    )
    form_columns = ("sale_id", "courier", "tracking_number", "shipping_status", "notes")
    column_filters = ("shipping_status",)
    column_searchable_list = ("tracking_number",)


class StockLogView(SecureModelView):
    column_list = ("id", "product_id", "change_qty", "reason", "created_at")
    can_create = False  # entries are only written by adjust_stock_view / future sale logic
    can_edit = False
    can_delete = False


def init_admin(app):
    admin = Admin(
        app,
        name="Inventory & Shipping Admin",
        template_mode="bootstrap4",
        index_view=SecureAdminIndexView(),
    )

    admin.add_view(ProductView(Product, db.session, name="Products", endpoint="product"))
    admin.add_view(SaleView(Sale, db.session, name="Sales"))
    admin.add_view(SaleItemView(SaleItem, db.session, name="Sale Items"))
    admin.add_view(ShippingView(Shipping, db.session, name="Shipping"))
    admin.add_view(CourierRateView(CourierRate, db.session, name="Courier Rates"))
    admin.add_view(StockLogView(StockLog, db.session, name="Stock Log"))
    admin.add_view(UserView(User, db.session, name="Admin Users"))

    return admin
