from flask import redirect, url_for, request, flash
from flask_admin import Admin, AdminIndexView
from flask_admin.contrib.sqla import ModelView
from flask_admin import expose
from flask_admin.menu import MenuLink
from flask_login import current_user
from werkzeug.security import generate_password_hash
from markupsafe import Markup

from app import db
from app.models import (
    User,
    Product,
    Sale,
    SaleItem,
    StockLog,
    MonthlyShippingRate,
    ShipmentBatch,
    Delivery,
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
        "id", "name", "sku", "length_cm", "width_cm", "height_cm",
        "cbm", "volumetric_kg", "actual_weight_kg", "stock", "adjust_stock_link",
    )
    column_labels = {"adjust_stock_link": "Stock Adjustment"}
    form_columns = (
        "name", "sku", "cost", "length_cm", "width_cm", "height_cm", "actual_weight_kg",
    )
    column_sortable_list = ("id", "name", "sku", "stock")
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
# SALES / SALE ITEMS — created only through /sales/new so CBM, the shipping
# estimate, and stock deduction all happen atomically. No profit/loss tracked.
# ---------------------------------------------------------------------------
class SaleView(SecureModelView):
    column_list = (
        "id", "sale_date", "customer_name", "customer_state", "order_status",
        "subtotal_amount", "estimated_shipping_cost", "actual_shipping_cost",
        "shipping_payment_settled", "total_amount", "payment_status", "sale_link",
    )
    column_labels = {"sale_link": "Details"}
    column_searchable_list = ("customer_name", "customer_phone")
    column_filters = ("order_status", "payment_status", "customer_state", "sale_date")

    can_create = False
    can_edit = False
    can_delete = False

    def _sale_link_formatter(view, context, model, name):
        url = url_for("sales.sale_detail", sale_id=model.id)
        return Markup(f'<a href="{url}" class="btn btn-xs btn-primary">View / Update Status</a>')

    column_formatters = {"sale_link": _sale_link_formatter}


class SaleItemView(SecureModelView):
    column_list = ("id", "sale_id", "product_id", "qty", "unit_price", "variant_note", "line_cbm")
    can_create = False  # items are only ever written by app/services/sales.create_sale
    can_edit = False
    can_delete = False


class StockLogView(SecureModelView):
    column_list = ("id", "product_id", "change_qty", "reason", "created_at")
    can_create = False
    can_edit = False
    can_delete = False


# ---------------------------------------------------------------------------
# MONTHLY SHIPPING RATES — admin records the flat rate each month, looked up
# by app/services/rates.py for the sale-time estimate and the batch-arrival cost.
# ---------------------------------------------------------------------------
class MonthlyShippingRateView(SecureModelView):
    column_list = ("id", "month", "rate_per_cbm")
    form_columns = ("month", "rate_per_cbm")
    column_sortable_list = ("month",)
    column_default_sort = ("month", True)


# ---------------------------------------------------------------------------
# SHIPMENT BATCHES — creation is simple (name/notes); adding sales and
# transitioning status happens through the dedicated /batches/<id> page.
# ---------------------------------------------------------------------------
class ShipmentBatchView(SecureModelView):
    column_list = ("id", "name", "status", "arrived_at", "batch_link")
    column_labels = {"batch_link": "Manage"}
    form_columns = ("name", "notes")
    can_edit = False
    can_delete = False

    def _batch_link_formatter(view, context, model, name):
        url = url_for("batches.batch_detail", batch_id=model.id)
        return Markup(f'<a href="{url}" class="btn btn-xs btn-primary">Manage Sales / Status</a>')

    column_formatters = {"batch_link": _batch_link_formatter}


# ---------------------------------------------------------------------------
# DELIVERIES — created only via /delivery/create (individually or consolidated
# by phone/name); status changes only via the detail page.
# ---------------------------------------------------------------------------
class DeliveryView(SecureModelView):
    column_list = ("id", "method", "status", "is_consolidated", "consolidation_type", "delivered_at", "delivery_link")
    column_labels = {"delivery_link": "Manage"}
    can_create = False
    can_edit = False
    can_delete = False

    def _delivery_link_formatter(view, context, model, name):
        url = url_for("delivery.delivery_detail", delivery_id=model.id)
        return Markup(f'<a href="{url}" class="btn btn-xs btn-primary">View / Update Status</a>')

    column_formatters = {"delivery_link": _delivery_link_formatter}


def init_admin(app):
    admin = Admin(
        app,
        name="Inventory & Shipping Admin",
        template_mode="bootstrap4",
        index_view=SecureAdminIndexView(),
    )

    admin.add_view(ProductView(Product, db.session, name="Products", endpoint="product"))
    admin.add_link(MenuLink(name="+ New Sale", url="/sales/new"))
    admin.add_view(SaleView(Sale, db.session, name="Sales"))
    admin.add_view(SaleItemView(SaleItem, db.session, name="Sale Items"))
    admin.add_view(MonthlyShippingRateView(MonthlyShippingRate, db.session, name="Monthly Shipping Rates"))
    admin.add_view(ShipmentBatchView(ShipmentBatch, db.session, name="Shipment Batches", endpoint="shipmentbatch"))
    admin.add_view(DeliveryView(Delivery, db.session, name="Deliveries", endpoint="deliveryadmin"))
    admin.add_link(MenuLink(name="Ready for Delivery", url="/delivery/ready"))
    admin.add_link(MenuLink(name="Reports", url="/reports/"))
    admin.add_link(MenuLink(name="Clear Test Data", url="/data-tools/clear"))
    admin.add_view(StockLogView(StockLog, db.session, name="Stock Log"))
    admin.add_view(UserView(User, db.session, name="Admin Users"))

    return admin
