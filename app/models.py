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
    estimated_shipping_cost = db.Column(db.Numeric(12, 2), default=0.00)
    total_amount = db.Column(db.Numeric(12, 2), default=0.00)
    profit = db.Column(db.Numeric(12, 2), default=0.00)

    payment_status = db.Column(db.String(50), default="Paid")  # Paid, Pending, Refunded
    notes = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

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
