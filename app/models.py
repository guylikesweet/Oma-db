from datetime import datetime, date
from decimal import Decimal
from sqlalchemy import Computed, event
from sqlalchemy.orm import Session
from flask_login import UserMixin
from app import db


# ---------------------------------------------------------------------------
# 1. USERS
# ---------------------------------------------------------------------------
class User(db.Model, UserMixin):
    __tablename__ = "users"

    ROLE_ADMIN = "admin"
    ROLE_STAFF = "staff"

    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(50), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    # Used by the mobile app to authenticate against /api/* — a long random
    # string, not a password. See `flask api-token` CLI command.
    api_token = db.Column(db.String(64), unique=True, nullable=True)

    # "admin" can edit company settings, manage users, mark shipment batches
    # arrived, edit monthly shipping rates, and other sensitive actions.
    # Everyone else is "staff". is_primary_admin marks the very first account
    # ever created (the owner) — it can never be deleted, even by another
    # admin, though the primary admin can remove admins added after it.
    role = db.Column(db.String(20), nullable=False, default=ROLE_STAFF, server_default=ROLE_STAFF)
    is_primary_admin = db.Column(db.Boolean, nullable=False, default=False, server_default="false")

    @property
    def is_admin(self):
        return self.role == self.ROLE_ADMIN

    def __repr__(self):
        return f"<User {self.username}>"


# ---------------------------------------------------------------------------
# APP SETTINGS (Restored for invoice generation)
# ---------------------------------------------------------------------------
class AppSettings(db.Model):
    __tablename__ = "app_settings"

    id = db.Column(db.Integer, primary_key=True)
    company_name = db.Column(db.String(255), default="OmaBuy")
    company_address = db.Column(db.Text)
    company_phone = db.Column(db.String(50))
    company_email = db.Column(db.String(100))
    invoice_footer_notes = db.Column(db.Text)
    
    # Store dynamic key/value pairs if your system uses them, 
    # ensuring compatibility regardless of how settings are queried.
    setting_key = db.Column(db.String(100), unique=True, nullable=True)
    setting_value = db.Column(db.Text, nullable=True)

    def __repr__(self):
        return f"<AppSettings {self.id}>"


# ---------------------------------------------------------------------------
# 2. PRODUCTS
# ---------------------------------------------------------------------------
class Product(db.Model):
    __tablename__ = "products"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(255), nullable=False)
    sku = db.Column(db.String(100), unique=True)
    cost = db.Column(db.Numeric(12, 2), default=0.00)

    length_cm = db.Column(db.Numeric(10, 2))
    width_cm = db.Column(db.Numeric(10, 2))
    height_cm = db.Column(db.Numeric(10, 2))

    # DB-generated (STORED) columns — Postgres computes these, never set in Python
    cbm = db.Column(
        db.Numeric(12, 6),
        Computed(
            "(COALESCE(length_cm,0) * COALESCE(width_cm,0) * COALESCE(height_cm,0) / 1000000.0)",
            persisted=True,
        ),
    )
    volumetric_kg = db.Column(
        db.Numeric(12, 3),
        Computed(
            "(COALESCE(length_cm,0) * COALESCE(width_cm,0) * COALESCE(height_cm,0) / 5000.0)",
            persisted=True,
        ),
    )

    actual_weight_kg = db.Column(db.Numeric(10, 3))
    stock = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    # Stage 6: reference-only estimate using a flat default rate (not state-specific).
    # Recomputed in app code (not a Postgres GENERATED column) because it depends on
    # MonthlyShippingRate, a separate table — see app/services/rates.py.
    estimated_shipping_cost = db.Column(db.Numeric(12, 2))

    sale_items = db.relationship("SaleItem", backref="product", lazy=True)
    stock_logs = db.relationship("StockLog", backref="product", lazy=True)

    def __repr__(self):
        return f"<Product {self.sku or self.name}>"


# ---------------------------------------------------------------------------
# 3. COURIER_RATES
# ---------------------------------------------------------------------------
class CourierRate(db.Model):
    __tablename__ = "courier_rates"

    id = db.Column(db.Integer, primary_key=True)
    state = db.Column(db.String(100), nullable=False, unique=True)
    rate_per_cbm = db.Column(db.Numeric(12, 2), default=600000.00)

    def __repr__(self):
        return f"<CourierRate {self.state}: {self.rate_per_cbm}>"


# ---------------------------------------------------------------------------
# MONTHLY_SHIPPING_RATES — Stage 6. The flat CBM rate changes month to month;
# this table lets it be recorded per month so the correct historical rate can
# be looked up later (e.g. when a batch arrives and the final cost is locked in).
# ---------------------------------------------------------------------------
class MonthlyShippingRate(db.Model):
    __tablename__ = "monthly_shipping_rates"

    id = db.Column(db.Integer, primary_key=True)
    month = db.Column(db.Date, nullable=False, unique=True)  # always stored as the 1st of the month
    rate_per_cbm = db.Column(db.Numeric(12, 2), nullable=False)

    def __repr__(self):
        return f"<MonthlyShippingRate {self.month.strftime('%Y-%m')}: {self.rate_per_cbm}>"


# ---------------------------------------------------------------------------
# MONTHLY_AIR_RATES
# ---------------------------------------------------------------------------
class MonthlyAirRate(db.Model):
    __tablename__ = "monthly_air_rates"

    id = db.Column(db.Integer, primary_key=True)
    month = db.Column(db.Date, nullable=False, unique=True)  # always stored as the 1st of the month
    rate_per_kg = db.Column(db.Numeric(12, 2), nullable=False)

    def __repr__(self):
        return f"<MonthlyAirRate {self.month.strftime('%Y-%m')}: {self.rate_per_kg}>"


# ---------------------------------------------------------------------------
# SHIPMENT_BATCHES — Stage 6. An inbound consignment from the supplier
# containing many customers' sales, arriving together (60-70 day window).
# ---------------------------------------------------------------------------
class ShipmentBatch(db.Model):
    __tablename__ = "shipment_batches"

    STATUS_IN_TRANSIT = "In Transit"
    STATUS_ARRIVED = "Arrived - Awaiting Shipping Payment"
    # Stage 8: settlement moved to the individual Sale level (Sale.shipping_payment_settled).
    # This constant/column is kept for backward compatibility with pre-Stage-8 data only —
    # no new code sets a whole batch to this status.
    STATUS_SETTLED = "Payment Settled - Ready for Delivery"

    MODE_SEA = "Sea"
    MODE_AIR = "Air"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(255), nullable=False)
    
    transport_mode = db.Column(db.String(20), default=MODE_SEA, nullable=False, server_default="Sea")
    
    status = db.Column(db.String(50), default=STATUS_IN_TRANSIT)
    departed_at = db.Column(db.DateTime)
    arrived_at = db.Column(db.DateTime)
    payment_settled_at = db.Column(db.DateTime)
    notes = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    sales = db.relationship("Sale", backref="batch", lazy=True)

    def __repr__(self):
        return f"<ShipmentBatch {self.name} ({self.transport_mode}): {self.status}>"


# ---------------------------------------------------------------------------
# DELIVERIES — Stage 7. Created once a sale's batch is "Payment Settled -
# Ready for Delivery". One Delivery can cover multiple sales when consolidated
# (same customer phone across orders, or same destination state) into one parcel.
# ---------------------------------------------------------------------------
class Delivery(db.Model):
    __tablename__ = "deliveries"

    STATUS_PENDING = "Pending"
    STATUS_OUT_FOR_DELIVERY = "Out for Delivery"
    STATUS_DELIVERED = "Delivered"

    id = db.Column(db.Integer, primary_key=True)
    method = db.Column(db.String(100))  # e.g. Dispatch Rider, Self Pickup, Interstate Courier
    status = db.Column(db.String(50), default=STATUS_PENDING)

    is_consolidated = db.Column(db.Boolean, default=False)
    # 'phone', 'location', or None (single, unconsolidated sale)
    consolidation_type = db.Column(db.String(20))

    # Defaults to the (first) sale's address but is editable — useful when
    # consolidating by location, where the drop-off point may differ slightly.
    delivery_address = db.Column(db.Text)

    notes = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    # Set automatically the moment status becomes "Out for Delivery" — this is
    # the label's "date of shipment", not when the delivery record was created.
    shipped_at = db.Column(db.DateTime)
    delivered_at = db.Column(db.DateTime)

    # Captured fresh per label (not pulled from product records) — the actual
    # packed parcel may not match the original per-product dimensions.
    package_weight_kg = db.Column(db.Numeric(10, 3))
    package_dimensions = db.Column(db.String(100))
    remarks = db.Column(db.Text)

    sales = db.relationship("Sale", backref="delivery", lazy=True)

    def __repr__(self):
        return f"<Delivery #{self.id} {self.status}>"


# ---------------------------------------------------------------------------
# 4. SALES
# ---------------------------------------------------------------------------
class Sale(db.Model):
    __tablename__ = "sales"

    id = db.Column(db.Integer, primary_key=True)
    # Customer-facing ID shown everywhere instead of the raw numeric id —
    # "OMB-" + 6 random alphanumeric chars, not sequential (see
    # app/services/sales.py generate_order_id). Also doubles as the label's
    # tracking number.
    order_id = db.Column(db.String(20), unique=True, nullable=True)
    client_operation_id = db.Column(db.String(100), unique=True, nullable=True)
    sale_date = db.Column(db.Date, default=date.today)
    customer_name = db.Column(db.String(255))
    customer_phone = db.Column(db.String(50))
    customer_address = db.Column(db.Text)
    # Optional. Only used to suggest which deliveries can share a courier bag.
    customer_city = db.Column(db.String(100))
    customer_state = db.Column(db.String(100))

    order_status = db.Column(db.String(50), default="New")  # New, Packed, Shipped, Delivered, Cancelled

    # 'preorder' (OMB-, stock ignored, shipping settled on arrival) or
    # 'stock' (OMBSTK-, stock deducted, no shipping cost, delivery settled off record).
    sale_type = db.Column(db.String(20), default="preorder", nullable=False, server_default="preorder")

    subtotal_amount = db.Column(db.Numeric(12, 2), default=0.00)
    estimated_shipping_cost = db.Column(db.Numeric(12, 2))  # Stage 8: deprecated, no longer calculated
    total_amount = db.Column(db.Numeric(12, 2), default=0.00)
    profit = db.Column(db.Numeric(12, 2))  # Stage 8: NULL until shipping is settled (see services/sales.py)

    payment_status = db.Column(db.String(50), default="Paid")  # Paid, Pending, Refunded
    notes = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    # Stage 6
    estimated_arrival_start = db.Column(db.Date)  # sale_date + 60 days
    estimated_arrival_end = db.Column(db.Date)    # sale_date + 70 days
    batch_id = db.Column(db.Integer, db.ForeignKey("shipment_batches.id"), nullable=True)
    # Locked in only when the batch arrives, using that month's MonthlyShippingRate.
    # Distinct from estimated_shipping_cost (the by-state estimate made at order time).
    actual_shipping_cost = db.Column(db.Numeric(12, 2))
    # Stage 8: settlement is per-order, not per-batch — a batch arrives as one unit,
    # but each sale's shipping fee is settled (and its cost locked in) individually,
    # using whatever the monthly rate is at the moment IT is settled.
    shipping_payment_settled = db.Column(db.Boolean, default=False)
    shipping_payment_settled_at = db.Column(db.DateTime)
    # Stage 7: set once this sale is migrated into a Delivery record (possibly
    # consolidated with other sales sharing the same phone number or state).
    delivery_id = db.Column(db.Integer, db.ForeignKey("deliveries.id"), nullable=True)

    items = db.relationship("SaleItem", backref="sale", lazy=True, cascade="all, delete-orphan")
    shipping = db.relationship("Shipping", backref="sale", uselist=False, cascade="all, delete-orphan")

    @property
    def is_stock_sale(self):
        return self.sale_type == "stock"

    @property
    def ready_for_delivery(self):
        """Stock sales have no shipping to settle, so they are ready straight away."""
        return self.order_status != "Cancelled" and (self.is_stock_sale or bool(self.shipping_payment_settled))

    def __repr__(self):
        return f"<Sale #{self.id} {self.customer_name}>"


# ---------------------------------------------------------------------------
# 5. SALE_ITEMS
# ---------------------------------------------------------------------------
class SaleItem(db.Model):
    __tablename__ = "sale_items"

    id = db.Column(db.Integer, primary_key=True)
    sale_id = db.Column(db.Integer, db.ForeignKey("sales.id", ondelete="CASCADE"), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey("products.id"), nullable=False)
    qty = db.Column(db.Integer, nullable=False)

    # Snapshot pricing at time of sale
    unit_cost = db.Column(db.Numeric(12, 2))
    unit_price = db.Column(db.Numeric(12, 2))

    # Calculated in application logic (Stage 3), not DB-generated,
    # because they depend on courier_rates + sale.customer_state at save time
    line_cbm = db.Column(db.Numeric(12, 6))
    line_volumetric_kg = db.Column(db.Numeric(12, 3))
    # Actual weight of this line (product weight x qty) when the sale was made;
    # NULL on older sales, which fall back to the product's current weight.
    line_weight_kg = db.Column(db.Numeric(12, 3))
    line_shipping_estimate = db.Column(db.Numeric(12, 2))

    # Stage 6: which variant/color was ordered on this line, so the right
    # item reaches the right person. Carries through to Delivery in Stage 7.
    variant_note = db.Column(db.String(255))

    def __repr__(self):
        return f"<SaleItem sale={self.sale_id} product={self.product_id} qty={self.qty}>"


# ---------------------------------------------------------------------------
# 6. SHIPPING
# ---------------------------------------------------------------------------
class Shipping(db.Model):
    __tablename__ = "shipping"

    id = db.Column(db.Integer, primary_key=True)
    sale_id = db.Column(db.Integer, db.ForeignKey("sales.id", ondelete="CASCADE"), unique=True, nullable=False)
    courier = db.Column(db.String(100))
    tracking_number = db.Column(db.String(100))

    chargeable_weight_kg = db.Column(db.Numeric(10, 3))  # MAX(actual, volumetric)
    total_cbm = db.Column(db.Numeric(12, 6))

    shipping_status = db.Column(db.String(50), default="Processing")  # Processing, Shipped, In Transit, Delivered
    shipped_at = db.Column(db.DateTime)
    delivered_at = db.Column(db.DateTime)
    notes = db.Column(db.Text)

    def __repr__(self):
        return f"<Shipping sale={self.sale_id} status={self.shipping_status}>"


# ---------------------------------------------------------------------------
# 7. STOCK_LOG
# ---------------------------------------------------------------------------
class StockLog(db.Model):
    __tablename__ = "stock_log"

    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey("products.id", ondelete="CASCADE"), nullable=False)

    # e.g. "Restock", "Sale", "Manual Adjustment"
    transaction_type = db.Column(db.String(50), nullable=False)

    # Note: Using Integer here requires Python side handling if floats happen.
    qty_change = db.Column(db.Integer, nullable=False)
    balance_after = db.Column(db.Integer)

    # Could link to the Sale if transaction_type == "Sale"
    reference = db.Column(db.String(255))
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)

    def __repr__(self):
        return f"<StockLog prod={self.product_id} change={self.qty_change} bal={self.balance_after}>"


# ---------------------------------------------------------------------------
# EVENT HOOKS FOR OFFLINE SYNC (STAGE 10)
#
# Listens for any INSERT, UPDATE, or DELETE on configured models.
# Writes a simplified JSON-compatible payload into _sync_queue for background processing.
# ---------------------------------------------------------------------------
_sync_queue = []

_SYNC_MODELS = (
    Product,
    CourierRate,
    MonthlyShippingRate,
    MonthlyAirRate,
    ShipmentBatch,
    Delivery,
    Sale,
    SaleItem,
    Shipping,
    StockLog,
)


def _model_payload(obj, deleted=False):
    """
    Converts a SQLAlchemy model instance into a simple dict mapping
    column names to their primitive values (dates cast to ISO 8601 strings,
    decimals to floats), for easy consumption by the mobile app's local SQLite.
    """
    mapper = obj.__mapper__
    payload = {}
    for column in mapper.columns:
        # If the row is deleted, only pass the ID (other cols aren't safely queryable)
        if deleted and column.name != "id":
            continue
        val = getattr(obj, column.key)
        if isinstance(val, date) or isinstance(val, datetime):
            val = val.isoformat()
        elif isinstance(val, Decimal):
            val = float(val)
        payload[column.name] = val
    return payload


def _record_mobile_sync_changes(session, flush_context, instances):
    """
    Iterate all objects modified in this flush. If they are in _SYNC_MODELS,
    push a message onto the memory queue indicating the table, row id,
    action (INSERT/UPDATE/DELETE), and current payload.
    """
    for obj in session.new:
        if isinstance(obj, _SYNC_MODELS):
            _sync_queue.append(
                {
                    "action": "INSERT",
                    "table": obj.__tablename__,
                    "id": obj.id,
                    "payload": _model_payload(obj),
                }
            )

    for obj in session.dirty:
        if isinstance(obj, _SYNC_MODELS):
            _sync_queue.append(
                {
                    "action": "UPDATE",
                    "table": obj.__tablename__,
                    "id": obj.id,
                    "payload": _model_payload(obj),
                }
            )

    for obj in session.deleted:
        if isinstance(obj, _SYNC_MODELS):
            _sync_queue.append(
                {
                    "action": "DELETE",
                    "table": obj.__tablename__,
                    "id": obj.id,
                    "payload": _model_payload(obj, deleted=True),
                }
            )


@event.listens_for(Session, "after_flush")
def trigger_mobile_sync_after_flush(session, flush_context):
    """
    Hook tied to every SQLAlchemy flush, which aggregates changes into `_sync_queue`.
    It does *not* broadcast yet, because a flush might still be rolled back
    if the outer transaction fails.
    """
    _record_mobile_sync_changes(session, flush_context, None)


@event.listens_for(Session, "after_commit")
def trigger_mobile_sync_after_commit(session):
    """
    Hook tied to the successful COMMIT of a transaction.
    Takes everything staged in `_sync_queue` and pushes it via WebSockets
    to all connected mobile clients.
    """
    global _sync_queue
    if not _sync_queue:
        return

    # To avoid circular imports between models.py and app.py (where socketio lives),
    # we import socketio locally here.
    from app import socketio

    # Group all changes in this single commit block into one event payload.
    # We rename tablenames dynamically to match the mobile app's model conventions
    # (plural to singular), though ideally both ends should share exact names.
    table_map = {
        "products": "product",
        "courier_rates": "courier_rate",
        "monthly_shipping_rates": "monthly_shipping_rate",
        "monthly_air_rates": "monthly_air_rate",
        "shipment_batches": "shipment_batch",
        "deliveries": "delivery",
        "sales": "sale",
        "sale_items": "sale_item",
        "shipping": "shipping",
        "stock_log": "stock_log",
    }

    payload = []
    for op in _sync_queue:
        mobile_table = table_map.get(op["table"], op["table"])
        payload.append(
            {
                "action": op["action"],
                "model": mobile_table,
                "id": op["id"],
                "data": op["payload"],
            }
        )

    # Empty the queue since we've processed it
    _sync_queue = []

    # Emit standard message that the Flutter app is actively listening for.
    # If the app is offline, this gets missed, but it will fetch all missing
    # delta records upon reconnection anyway via a separate REST endpoint.
    socketio.emit("sync_update", payload, namespace="/sync")


@event.listens_for(Session, "after_rollback")
def clear_mobile_sync_after_rollback(session):
    """
    If the transaction failed and rolled back, discard any staged sync events.
    """
    global _sync_queue
    _sync_queue = []
