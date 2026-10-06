from flask import redirect, url_for, request, flash
from flask_admin import Admin, AdminIndexView
from flask_admin.contrib.sqla import ModelView
from flask_admin import expose
from flask_admin.menu import MenuLink
from flask_login import current_user
from werkzeug.security import generate_password_hash
from markupsafe import Markup
from sqlalchemy import inspect
from wtforms import PasswordField
from wtforms.validators import Optional, Length

from app import db
from app.access import admin_required, password_recently_confirmed, reauth_url
from app.services.audit import record_audit
from app.models import (
    User,
    Product,
    Sale,
    SaleItem,
    StockLog,
    MonthlyShippingRate,
    MonthlyAirRate,
    ShipmentBatch,
    Delivery,
    AuditLog,
)


# ---------------------------------------------------------------------------
# Access control mixin — every admin view requires a logged-in user
# ---------------------------------------------------------------------------
class SecureModelView(ModelView):
    def is_accessible(self):
        return current_user.is_authenticated

    def inaccessible_callback(self, name, **kwargs):
        return redirect(url_for("auth.login", next=request.url))

    def _handle_view(self, name, **kwargs):
        response = super()._handle_view(name, **kwargs)
        if response is not None:
            return response

        if name in {"create_view", "edit_view", "delete_view", "adjust_stock_view"}:
            if not password_recently_confirmed():
                return redirect(reauth_url(request.full_path))
        return None


class AdminOnlyModelView(SecureModelView):
    """Same as SecureModelView, but staff are blocked outright — used for
    views the owner said only admins should even see, like Users and the
    monthly shipping rate."""
    def is_accessible(self):
        return current_user.is_authenticated and current_user.is_admin

    def inaccessible_callback(self, name, **kwargs):
        if current_user.is_authenticated:
            flash("That page is restricted to admins.", "error")
            return redirect(url_for("classic_home"))
        return redirect(url_for("auth.login", next=request.url))


class SecureAdminIndexView(AdminIndexView):
    def is_accessible(self):
        return current_user.is_authenticated

    def inaccessible_callback(self, name, **kwargs):
        return redirect(url_for("auth.login", next=request.url))


# ---------------------------------------------------------------------------
# USERS — never expose/edit password_hash directly; set via a plain field
# ---------------------------------------------------------------------------
class UserView(AdminOnlyModelView):
    column_list = ("id", "username", "role", "is_active", "is_primary_admin", "created_at")
    column_labels = {"is_primary_admin": "Original admin", "is_active": "Active"}
    form_columns = ("username", "password", "role", "is_active")
    form_extra_fields = {
        "password": PasswordField(
            "Password",
            validators=[Optional(), Length(min=8, message="Password must be at least 8 characters.")],
            description="Required when creating a user; leave blank when editing to keep the current password.",
        ),
    }
    form_choices = {"role": [("admin", "Admin"), ("staff", "Staff")]}

    def on_model_change(self, form, model, is_created):
        role_history = inspect(model).attrs.role.history
        old_role = (
            None
            if is_created
            else (role_history.deleted[0] if role_history.deleted else model.role)
        )

        password_value = getattr(form, "password", None)
        password = (password_value.data or "").strip() if password_value else ""
        if is_created:
            if len(password) < 8:
                raise ValueError("A password of at least 8 characters is required for a new user.")
            model.password_hash = generate_password_hash(password)
        elif password:
            model.password_hash = generate_password_hash(password)
            model.api_token = None
            model.api_last_activity_at = None
            model.biometric_credential_hash = None
        if model.is_primary_admin:
            model.role = "admin"
            model.is_active = True
        role_changed = (not is_created) and old_role != model.role
        if role_changed:
            if model.id == current_user.id and model.role != User.ROLE_ADMIN:
                raise Exception("You cannot demote your own account.")
            if old_role == User.ROLE_ADMIN and model.role == User.ROLE_STAFF and not current_user.is_primary_admin:
                raise Exception("Only the original admin can downgrade another admin to staff.")
        if not model.is_active:
            model.api_token = None
            model.api_last_activity_at = None
        record_audit(
            "user.create" if is_created else "user.update",
            target_type="user",
            target_id=model.id,
            details={
                "username": model.username,
                "role": model.role,
                "is_active": model.is_active,
                "role_changed": role_changed,
                "previous_role": old_role,
                "source": "admin",
            },
        )
        super().on_model_change(form, model, is_created)

    def on_model_delete(self, model):
        if model.is_primary_admin:
            raise Exception("The original admin account cannot be removed.")
        if model.id == current_user.id:
            raise Exception("You cannot remove your own account.")
        if model.is_admin and not current_user.is_primary_admin:
            raise Exception("Only the original admin can remove another admin account.")
        record_audit(
            "user.delete",
            target_type="user",
            target_id=model.id,
            details={"username": model.username, "role": model.role, "source": "admin"},
        )
        AuditLog.query.filter_by(user_id=model.id).update(
            {"user_id": None}, synchronize_session=False
        )


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

    def on_model_change(self, form, model, is_created):
        record_audit(
            "product.create" if is_created else "product.update",
            target_type="product",
            target_id=model.id,
            details={"name": model.name, "source": "admin"},
            user=current_user,
        )
        super().on_model_change(form, model, is_created)

    def on_model_delete(self, model):
        record_audit(
            "product.delete",
            target_type="product",
            target_id=model.id,
            details={"name": model.name, "source": "admin"},
            user=current_user,
        )
        super().on_model_delete(model)

    @expose("/adjust-stock/<int:product_id>", methods=("GET", "POST"))
    def adjust_stock_view(self, product_id):
        if not self.is_accessible():
            return self.inaccessible_callback("adjust_stock_view")

        product = Product.query.get_or_404(product_id)

        if request.method == "POST":
            # Re-read under a row lock so concurrent stock writers cannot
            # both validate against the same starting quantity.
            product = (
                Product.query
                .filter_by(id=product_id)
                .with_for_update()
                .first_or_404()
            )
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
                record_audit(
                    "stock.adjust",
                    target_type="product",
                    target_id=product.id,
                    details={"change_qty": change_qty, "reason": reason},
                )
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
        "id", "order_id", "sale_date", "customer_name", "customer_state", "order_status",
        "subtotal_amount", "estimated_shipping_cost", "actual_shipping_cost",
        "shipping_payment_settled", "total_amount", "payment_status", "sale_link",
    )
    column_labels = {"sale_link": "Details"}
    column_searchable_list = ("order_id", "customer_name", "customer_phone")
    column_filters = ("order_status", "payment_status", "customer_state", "sale_date")
    # Newest sales first — otherwise a brand-new sale is buried on the last
    # page behind everything ever created, and looks like it's missing.
    column_default_sort = ("id", True)
    # Quick inline edit (click the cell) instead of a full edit form, so
    # marking a sale Paid/Pending/Refunded doesn't need its own page.
    column_editable_list = ("payment_status",)

    can_create = False
    can_edit = False
    can_delete = True

    def on_model_delete(self, model):
        if model.delivery_id:
            raise Exception("Remove this sale from its delivery before deleting it.")
        if model.shipping_payment_settled:
            raise Exception("A sale with settled shipping cannot be deleted.")
        if model.is_stock_sale:
            for item in model.items:
                product = (
                    Product.query
                    .filter_by(id=item.product_id)
                    .with_for_update()
                    .first()
                )
                if product:
                    product.stock += item.qty
                    db.session.add(
                        StockLog(
                            product_id=product.id,
                            change_qty=item.qty,
                            reason=f"Deleted sale #{model.id}",
                        )
                    )
        record_audit(
            "sale.delete",
            target_type="sale",
            target_id=model.id,
            details={"order_id": model.order_id, "sale_type": model.sale_type},
        )

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


class AuditLogView(AdminOnlyModelView):
    column_list = (
        "id",
        "created_at",
        "username",
        "action",
        "target_type",
        "target_id",
        "outcome",
        "ip_address",
    )
    can_create = False
    can_edit = False
    can_delete = False
    can_export = True
    column_default_sort = ("created_at", True)


# ---------------------------------------------------------------------------
# MONTHLY SHIPPING RATES — admin records the flat rate each month, looked up
# by app/services/rates.py for the sale-time estimate and the batch-arrival cost.
# ---------------------------------------------------------------------------
class MonthlyShippingRateView(AdminOnlyModelView):
    column_list = ("id", "month", "rate_per_cbm")
    form_columns = ("month", "rate_per_cbm")
    column_sortable_list = ("month",)
    column_default_sort = ("month", True)

    def on_model_change(self, form, model, is_created):
        # Always store as the 1st of the month, whatever day was picked in the
        # form — get_rate_for_month() matches by year+month regardless, but
        # normalizing here keeps the "one row per calendar month" unique
        # constraint meaningful (two different days in the same month would
        # otherwise both pass it as "different" dates).
        if model.month:
            model.month = model.month.replace(day=1)
        record_audit(
            "rate.sea.create" if is_created else "rate.sea.update",
            target_type="monthly_shipping_rate",
            target_id=model.id,
            details={"month": model.month, "source": "admin"},
            user=current_user,
        )
        super().on_model_change(form, model, is_created)
class MonthlyAirRateView(AdminOnlyModelView):
    column_list = ("id", "month", "rate_per_kg")
    form_columns = ("month", "rate_per_kg")
    column_sortable_list = ("month",)
    column_default_sort = ("month", True)

    def on_model_change(self, form, model, is_created):
        if model.month:
            model.month = model.month.replace(day=1)
        record_audit(
            "rate.air.create" if is_created else "rate.air.update",
            target_type="monthly_air_rate",
            target_id=model.id,
            details={"month": model.month, "source": "admin"},
            user=current_user,
        )
        super().on_model_change(form, model, is_created)



# ---------------------------------------------------------------------------
# SHIPMENT BATCHES — creation is simple (name/notes); adding sales and
# transitioning status happens through the dedicated /batches/<id> page.
# ---------------------------------------------------------------------------
class ShipmentBatchView(SecureModelView):
    column_list = ("id", "name", "transport_mode", "status", "arrived_at", "batch_link")
    column_labels = {"batch_link": "Manage"}
    form_columns = ("name", "transport_mode", "notes")
    form_args = {"transport_mode": {"choices": [("air", "Air"), ("sea", "Sea")]}}
    can_edit = False
    can_delete = True

    def on_model_delete(self, model):
        if model.status != ShipmentBatch.STATUS_IN_TRANSIT:
            raise Exception("Only an In Transit shipment batch can be deleted. Undo its arrival first.")
        if any(s.shipping_payment_settled or s.delivery_id for s in model.sales):
            raise Exception("This batch contains sales that are already settled or assigned to delivery.")
        sale_ids = [sale.id for sale in model.sales]
        for sale in model.sales:
            sale.batch_id = None
            sale.batch_assigned_at = None
        record_audit(
            "batch.delete",
            target_type="shipment_batch",
            target_id=model.id,
            details={"name": model.name, "sale_ids": sale_ids},
        )


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
    admin.add_view(MonthlyAirRateView(MonthlyAirRate, db.session, name="Monthly Air Rates", endpoint="monthlyairrate"))
    admin.add_view(ShipmentBatchView(ShipmentBatch, db.session, name="Shipment Batches", endpoint="shipmentbatch"))
    admin.add_view(DeliveryView(Delivery, db.session, name="Deliveries", endpoint="deliveryadmin"))
    admin.add_link(MenuLink(name="Ready for Delivery", url="/delivery/ready"))
    admin.add_link(MenuLink(name="Reports", url="/reports/"))
    admin.add_link(MenuLink(name="Clear Test Data", url="/data-tools/clear"))
    admin.add_view(StockLogView(StockLog, db.session, name="Stock Log"))
    admin.add_view(AuditLogView(AuditLog, db.session, name="Audit Log"))
    admin.add_view(UserView(User, db.session, name="Admin Users"))

    return admin
