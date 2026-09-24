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

    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(50), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    # Used by the mobile app to authenticate against /api/* — a long random
    # string, not a password. See `flask api-token` CLI command.
    api_token = db.Column(db.String(64), unique=True, nullable=True)

    def __repr__(self):
        return f"<User {self.username}>"


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

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(255), nullable=False)
    status = db.Column(db.String(50), default=STATUS_IN_TRANSIT)
    departed_at = db.Column(db.DateTime)
    arrived_at = db.Column(db.DateTime)
    payment_settled_at = db.Column(db.DateTime)
    notes = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    sales = db.relationship("Sale", backref="batch", lazy=True)

    def __repr__(self):
        return f"<ShipmentBatch {self.name}: {self.status}>"


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
    customer_state = db.Column(db.String(100))

    order_status = db.Column(db.String(50), default="New")  # New, Packed, Shipped, Delivered, Cancelled

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
    product_id = db.Column(db.Integer, db.ForeignKey("products.id"), nullable=False)
    change_qty = db.Column(db.Integer, nullable=False)  # + stock in, - sale
    reason = db.Column(db.String(255))  # 'New Stock', 'Sale #123', 'Damaged'
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def __repr__(self):
        return f"<StockLog product={self.product_id} change={self.change_qty}>"


# ---------------------------------------------------------------------------
# MOBILE SYNC
# ---------------------------------------------------------------------------
class MobileChange(db.Model):
    """Append-only change feed consumed by the offline mobile client.

    Each committed ORM mutation to a mobile-relevant model creates one row.
    The monotonically increasing id is the mobile sync cursor.
    """
    __tablename__ = "mobile_changes"

    sequence = db.Column(db.BigInteger, primary_key=True, autoincrement=True)
    entity_type = db.Column(db.String(50), nullable=False)
    entity_id = db.Column(db.String(100), nullable=False)
    operation = db.Column(db.String(20), nullable=False)  # upsert, delete
    payload = db.Column(db.JSON, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)


class MobileOperation(db.Model):
    """Idempotency record for mobile write operations.

    A phone may retry the same operation after a dropped connection. The
    unique user/operation_id pair prevents the server from creating a second
    sale when the first request actually succeeded but its response was lost.
    """
    __tablename__ = "mobile_operations"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    operation_id = db.Column(db.String(100), nullable=False)
    operation_type = db.Column(db.String(100), nullable=False)
    status = db.Column(db.String(30), nullable=False, default="processing")
    response_code = db.Column(db.Integer)
    response_json = db.Column(db.JSON)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    completed_at = db.Column(db.DateTime)

    __table_args__ = (
        db.UniqueConstraint("operation_id", name="uq_mobile_operations_operation_id"),
    )


# ---------------------------------------------------------------------------
# APP_SETTINGS — single row (id always 1). Shipping label size, business
# info, and the logo image itself (stored as bytes, not a file on disk —
# Render's filesystem is wiped on every deploy, so a disk file wouldn't survive).
# ---------------------------------------------------------------------------
class AppSettings(db.Model):
    __tablename__ = "app_settings"

    id = db.Column(db.Integer, primary_key=True)
    label_width_mm = db.Column(db.Integer, default=100)
    label_height_mm = db.Column(db.Integer, default=150)
    business_name = db.Column(db.String(255))
    business_phone = db.Column(db.String(50))
    business_address = db.Column(db.Text)
    logo_data = db.Column(db.LargeBinary)
    logo_mimetype = db.Column(db.String(50))

    def __repr__(self):
        return f"<AppSettings {self.label_width_mm}x{self.label_height_mm}mm>"


# Models whose changes are useful to the offline mobile client. Sensitive
# account/settings data deliberately stays out of the mobile sync feed.
_SYNC_MODELS = (
    Product,
    CourierRate,
    MonthlyShippingRate,
    ShipmentBatch,
    Delivery,
    Sale,
    SaleItem,
    Shipping,
    StockLog,
)


def _json_value(value):
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    return value


def _model_payload(obj):
    return {
        column.name: _json_value(getattr(obj, column.name))
        for column in obj.__table__.columns
    }


@event.listens_for(Session, "after_flush")
def _record_mobile_sync_changes(session, flush_context):
    # Flask-SQLAlchemy's scoped session class is not guaranteed to be the same
    # class across SQLAlchemy versions, so this listener is intentionally kept
    # narrow. If the session is currently recording sync rows, do not record
    # the SyncChange rows themselves.
    if session.info.get("_recording_sync_changes"):
        return

    changes = []
    for obj in list(session.new):
        if isinstance(obj, _SYNC_MODELS):
            changes.append((obj, "created"))

    for obj in list(session.dirty):
        if isinstance(obj, _SYNC_MODELS) and session.is_modified(obj, include_collections=False):
            changes.append((obj, "updated"))

    for obj in list(session.deleted):
        if isinstance(obj, _SYNC_MODELS):
            changes.append((obj, "deleted"))

    if not changes:
        return

    session.info["_recording_sync_changes"] = True
    try:
        for obj, action in changes:
            entity_id = getattr(obj, "id", None)
            if entity_id is None:
                continue
            payload = None if action == "deleted" else _model_payload(obj)
            session.add(MobileChange(
                entity_type={
                    "products": "product", "sales": "sale", "sale_items": "sale_item",
                    "shipment_batches": "shipment_batch", "deliveries": "delivery",
                    "shipping": "shipping", "courier_rates": "courier_rate",
                    "monthly_shipping_rates": "monthly_shipping_rate", "stock_log": "stock_log",
                }.get(obj.__tablename__, obj.__tablename__),
                entity_id=str(entity_id),
                operation="delete" if action == "deleted" else "upsert",
                payload=payload,
            ))
    finally:
        session.info["_recording_sync_changes"] = False
