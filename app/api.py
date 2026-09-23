"""
JSON API for the offline-capable mobile app.

The browser UI continues to use the normal Flask routes. The mobile client uses
/api/v1/* with bearer-token authentication, a bootstrap snapshot, an append-only
sync feed, and idempotent write operations so a dropped connection cannot create
duplicate sales when the phone retries a request.

The older /api/products and /api/sales endpoints are kept for compatibility.
New mobile development should use /api/v1/*.
"""
import json
import secrets
from decimal import Decimal, InvalidOperation
from functools import wraps

from flask import Blueprint, request, jsonify, g
from werkzeug.security import check_password_hash

from app import db
from app.models import (
    User, Product, Sale, SaleItem, Shipping, Delivery, ShipmentBatch,
    CourierRate, MonthlyShippingRate, StockLog, ApiOperation, SyncChange,
)
from app.services.sales import create_sale, SaleValidationError

api_bp = Blueprint("api", __name__, url_prefix="/api")


# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------
def require_api_token(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "Missing or malformed Authorization header. Use 'Bearer <token>'."}), 401

        token = auth_header[len("Bearer "):].strip()
        user = User.query.filter_by(api_token=token).first() if token else None
        if not user:
            return jsonify({"error": "Invalid API token."}), 401

        g.api_user = user
        return f(*args, **kwargs)
    return wrapper


def _ensure_api_token(user):
    if not user.api_token:
        user.api_token = secrets.token_hex(32)
        db.session.commit()
    return user.api_token


@api_bp.route("/v1/auth/login", methods=("POST",))
def api_login():
    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""

    if not username or not password:
        return jsonify({"error": "Username and password are required."}), 400

    user = User.query.filter_by(username=username).first()
    if not user or not check_password_hash(user.password_hash, password):
        return jsonify({"error": "Invalid username or password."}), 401

    token = _ensure_api_token(user)
    return jsonify({
        "token": token,
        "user": {"id": user.id, "username": user.username},
    })


@api_bp.route("/v1/auth/me", methods=("GET",))
@require_api_token
def api_me():
    return jsonify({"id": g.api_user.id, "username": g.api_user.username})


# ---------------------------------------------------------------------------
# JSON serializers
# ---------------------------------------------------------------------------
def _product_json(p):
    return {
        "id": p.id,
        "name": p.name,
        "sku": p.sku,
        "cost": float(p.cost) if p.cost is not None else None,
        "length_cm": float(p.length_cm) if p.length_cm is not None else None,
        "width_cm": float(p.width_cm) if p.width_cm is not None else None,
        "height_cm": float(p.height_cm) if p.height_cm is not None else None,
        "cbm": float(p.cbm) if p.cbm is not None else None,
        "volumetric_kg": float(p.volumetric_kg) if p.volumetric_kg is not None else None,
        "actual_weight_kg": float(p.actual_weight_kg) if p.actual_weight_kg is not None else None,
        "stock": p.stock,
        "estimated_shipping_cost": float(p.estimated_shipping_cost) if p.estimated_shipping_cost is not None else None,
        "created_at": p.created_at.isoformat() if p.created_at else None,
    }


def _sale_json(s):
    return {
        "id": s.id,
        "order_id": s.order_id,
        "sale_date": s.sale_date.isoformat() if s.sale_date else None,
        "customer_name": s.customer_name,
        "customer_phone": s.customer_phone,
        "customer_address": s.customer_address,
        "customer_state": s.customer_state,
        "order_status": s.order_status,
        "payment_status": s.payment_status,
        "subtotal_amount": float(s.subtotal_amount) if s.subtotal_amount is not None else None,
        "estimated_shipping_cost": float(s.estimated_shipping_cost) if s.estimated_shipping_cost is not None else None,
        "actual_shipping_cost": float(s.actual_shipping_cost) if s.actual_shipping_cost is not None else None,
        "total_amount": float(s.total_amount) if s.total_amount is not None else None,
        "profit": float(s.profit) if s.profit is not None else None,
        "shipping_payment_settled": bool(s.shipping_payment_settled),
        "shipping_payment_settled_at": s.shipping_payment_settled_at.isoformat() if s.shipping_payment_settled_at else None,
        "estimated_arrival_start": s.estimated_arrival_start.isoformat() if s.estimated_arrival_start else None,
        "estimated_arrival_end": s.estimated_arrival_end.isoformat() if s.estimated_arrival_end else None,
        "batch_id": s.batch_id,
        "delivery_id": s.delivery_id,
        "notes": s.notes,
        "created_at": s.created_at.isoformat() if s.created_at else None,
        "items": [
            {
                "id": item.id,
                "product_id": item.product_id,
                "product_name": item.product.name if item.product else None,
                "qty": item.qty,
                "unit_cost": float(item.unit_cost) if item.unit_cost is not None else None,
                "unit_price": float(item.unit_price) if item.unit_price is not None else None,
                "line_cbm": float(item.line_cbm) if item.line_cbm is not None else None,
                "line_volumetric_kg": float(item.line_volumetric_kg) if item.line_volumetric_kg is not None else None,
                "line_shipping_estimate": float(item.line_shipping_estimate) if item.line_shipping_estimate is not None else None,
                "variant_note": item.variant_note,
            }
            for item in s.items
        ],
    }


def _shipping_json(s):
    return {
        "id": s.id,
        "sale_id": s.sale_id,
        "courier": s.courier,
        "tracking_number": s.tracking_number,
        "chargeable_weight_kg": float(s.chargeable_weight_kg) if s.chargeable_weight_kg is not None else None,
        "total_cbm": float(s.total_cbm) if s.total_cbm is not None else None,
        "shipping_status": s.shipping_status,
        "shipped_at": s.shipped_at.isoformat() if s.shipped_at else None,
        "delivered_at": s.delivered_at.isoformat() if s.delivered_at else None,
        "notes": s.notes,
    }


def _delivery_json(d):
    return {
        "id": d.id,
        "method": d.method,
        "status": d.status,
        "is_consolidated": bool(d.is_consolidated),
        "consolidation_type": d.consolidation_type,
        "delivery_address": d.delivery_address,
        "notes": d.notes,
        "created_at": d.created_at.isoformat() if d.created_at else None,
        "shipped_at": d.shipped_at.isoformat() if d.shipped_at else None,
        "delivered_at": d.delivered_at.isoformat() if d.delivered_at else None,
        "package_weight_kg": float(d.package_weight_kg) if d.package_weight_kg is not None else None,
        "package_dimensions": d.package_dimensions,
        "remarks": d.remarks,
        "sale_ids": [sale.id for sale in d.sales],
    }


def _batch_json(b):
    return {
        "id": b.id,
        "name": b.name,
        "status": b.status,
        "departed_at": b.departed_at.isoformat() if b.departed_at else None,
        "arrived_at": b.arrived_at.isoformat() if b.arrived_at else None,
        "payment_settled_at": b.payment_settled_at.isoformat() if b.payment_settled_at else None,
        "notes": b.notes,
        "created_at": b.created_at.isoformat() if b.created_at else None,
        "sale_ids": [sale.id for sale in b.sales],
    }


def _rate_json(r):
    return {
        "id": r.id,
        "state": r.state,
        "rate_per_cbm": float(r.rate_per_cbm) if r.rate_per_cbm is not None else None,
    }


def _monthly_rate_json(r):
    return {
        "id": r.id,
        "month": r.month.isoformat() if r.month else None,
        "rate_per_cbm": float(r.rate_per_cbm) if r.rate_per_cbm is not None else None,
    }


def _stock_log_json(row):
    return {
        "id": row.id,
        "product_id": row.product_id,
        "change_qty": row.change_qty,
        "reason": row.reason,
        "created_at": row.created_at.isoformat() if row.created_at else None,
    }


# ---------------------------------------------------------------------------
# Compatibility endpoints — existing mobile prototype API
# ---------------------------------------------------------------------------
@api_bp.route("/products", methods=("GET",))
@require_api_token
def list_products():
    products = Product.query.order_by(Product.name).all()
    return jsonify([_product_json(p) for p in products])


@api_bp.route("/sales", methods=("GET",))
@require_api_token
def list_sales():
    limit = request.args.get("limit", default=100, type=int)
    sales = Sale.query.order_by(Sale.id.desc()).limit(min(max(limit, 1), 500)).all()
    return jsonify([_sale_json(s) for s in sales])


@api_bp.route("/sales", methods=("POST",))
@require_api_token
def create_sale_api_legacy():
    return _create_sale_api(require_operation_id=False)


# ---------------------------------------------------------------------------
# Version 1 — foundation for the real offline client
# ---------------------------------------------------------------------------
@api_bp.route("/v1/bootstrap", methods=("GET",))
@require_api_token
def bootstrap():
    # Capture the cursor BEFORE reading the snapshot. Any changes that happen
    # while the snapshot is being assembled will have a larger id and will be
    # picked up by the next /sync call instead of being silently skipped.
    cursor = db.session.query(db.func.max(SyncChange.id)).scalar() or 0

    return jsonify({
        "cursor": int(cursor),
        "products": [_product_json(x) for x in Product.query.order_by(Product.id).all()],
        "sales": [_sale_json(x) for x in Sale.query.order_by(Sale.id).all()],
        "shipping": [_shipping_json(x) for x in Shipping.query.order_by(Shipping.id).all()],
        "deliveries": [_delivery_json(x) for x in Delivery.query.order_by(Delivery.id).all()],
        "shipment_batches": [_batch_json(x) for x in ShipmentBatch.query.order_by(ShipmentBatch.id).all()],
        "courier_rates": [_rate_json(x) for x in CourierRate.query.order_by(CourierRate.id).all()],
        "monthly_shipping_rates": [_monthly_rate_json(x) for x in MonthlyShippingRate.query.order_by(MonthlyShippingRate.id).all()],
        "stock_logs": [_stock_log_json(x) for x in StockLog.query.order_by(StockLog.id).all()],
    })


@api_bp.route("/v1/sync", methods=("GET",))
@require_api_token
def sync():
    try:
        cursor = max(int(request.args.get("cursor", 0)), 0)
    except (TypeError, ValueError):
        return jsonify({"error": "cursor must be a non-negative integer."}), 400

    try:
        limit = min(max(int(request.args.get("limit", 500)), 1), 1000)
    except (TypeError, ValueError):
        return jsonify({"error": "limit must be between 1 and 1000."}), 400

    rows = (SyncChange.query
            .filter(SyncChange.id > cursor)
            .order_by(SyncChange.id.asc())
            .limit(limit + 1)
            .all())

    has_more = len(rows) > limit
    rows = rows[:limit]
    next_cursor = rows[-1].id if rows else cursor

    return jsonify({
        "cursor": cursor,
        "next_cursor": int(next_cursor),
        "has_more": has_more,
        "changes": [
            {
                "id": int(row.id),
                "entity": row.entity,
                "entity_id": row.entity_id,
                "action": row.action,
                "payload": row.payload,
                "created_at": row.created_at.isoformat() if row.created_at else None,
            }
            for row in rows
        ],
    })


@api_bp.route("/v1/products", methods=("GET",))
@require_api_token
def v1_products():
    return jsonify([_product_json(p) for p in Product.query.order_by(Product.name).all()])


@api_bp.route("/v1/sales", methods=("GET",))
@require_api_token
def v1_sales():
    limit = request.args.get("limit", default=100, type=int)
    sales = Sale.query.order_by(Sale.id.desc()).limit(min(max(limit, 1), 500)).all()
    return jsonify([_sale_json(s) for s in sales])


@api_bp.route("/v1/sales", methods=("POST",))
@require_api_token
def create_sale_api_v1():
    return _create_sale_api(require_operation_id=True)


def _create_sale_api(require_operation_id):
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "Request body must be a JSON object."}), 400

    operation_id = (data.get("operation_id") or "").strip()
    if require_operation_id and not operation_id:
        return jsonify({"error": "operation_id is required for offline-safe sale creation."}), 400
    if operation_id and (len(operation_id) < 8 or len(operation_id) > 64):
        return jsonify({"error": "operation_id must be between 8 and 64 characters."}), 400

    # If the phone is retrying an operation whose response was lost, return the
    # original response instead of creating a second sale.
    if operation_id:
        existing = ApiOperation.query.filter_by(
            user_id=g.api_user.id,
            operation_id=operation_id,
        ).first()
        if existing:
            return jsonify(json.loads(existing.response_json)), existing.status_code

    raw_items = data.get("items") or []
    line_items = []
    for line in raw_items:
        try:
            line_items.append({
                "product_id": int(line["product_id"]),
                "qty": int(line["qty"]),
                "unit_price": Decimal(str(line["unit_price"])),
                "variant_note": line.get("variant_note") or None,
            })
        except (KeyError, TypeError, ValueError, InvalidOperation):
            return jsonify({"error": "Each item needs product_id, qty, and unit_price."}), 400

    try:
        # create_sale(commit=False) keeps the sale, stock deductions, audit rows,
        # and idempotency record in one database transaction.
        sale = create_sale(
            customer_name=(data.get("customer_name") or "").strip(),
            customer_phone=(data.get("customer_phone") or "").strip(),
            customer_address=(data.get("customer_address") or "").strip(),
            customer_state=(data.get("customer_state") or "").strip(),
            payment_status=data.get("payment_status") or "Paid",
            notes=(data.get("notes") or "").strip(),
            line_items=line_items,
            commit=False,
        )

        payload = _sale_json(sale)
        if operation_id:
            db.session.add(ApiOperation(
                user_id=g.api_user.id,
                operation_id=operation_id,
                operation_type="create_sale",
                status_code=201,
                response_json=json.dumps(payload),
            ))
        db.session.commit()
        return jsonify(payload), 201
    except SaleValidationError as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400
    except Exception:
        db.session.rollback()
        raise
