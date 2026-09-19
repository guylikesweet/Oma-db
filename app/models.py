from datetime import datetime, date
from sqlalchemy import Computed
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
    delivered_at = db.Column(db.DateTime)

    sales = db.relationship("Sale", backref="delivery", lazy=True)

    def __repr__(self):
        return f"<Delivery #{self.id} {self.status}>"


# ---------------------------------------------------------------------------
# 4. SALES
# ---------------------------------------------------------------------------
class Sale(db.Model):
    __tablename__ = "sales"

    id = db.Column(db.Integer, primary_key=True)
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
