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
from datetime import date, datetime, timedelta
from decimal import Decimal, InvalidOperation
from functools import wraps

from flask import Blueprint, request, jsonify, g
from werkzeug.security import check_password_hash, generate_password_hash

from app import db
from app.services.journey import journey_public, flow_for, manual_stages_for, stage_label, set_manual_stage_bulk, JourneyError
from app.access import require_admin_api
from app.models import (
    User, Product, Sale, SaleItem, Shipping, Delivery, ShipmentBatch,
    CourierRate, MonthlyShippingRate, MonthlyAirRate, StockLog, MobileOperation, MobileChange, AuditLog, PushDevice,
)
from app.services.sales import create_sale, SaleValidationError, shipping_cost_for_items
from app.services.rates import get_rate_for_month, get_volume_rate, get_rate_per_kg, RateMissingError
from app.services.delivery import check_consolidation, find_consolidation_groups
from app.services.audit import record_audit
from app.services.push_notifications import queue_batch_arrival, queue_user_notification, flush_outbox
from app.services.dashboard import get_kpis, get_sales_last_30_days
from app.services.shipment_batches import mark_unarrived, BatchValidationError

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
        if not user or not user.is_active:
            return jsonify({"error": "This user account is inactive or the session is invalid."}), 401

        now = datetime.utcnow()
        last = user.api_last_activity_at
        if last is not None and now - last >= timedelta(hours=6):
            record_audit(
                "logout.timeout",
                target_type="user",
                target_id=user.id,
                outcome="success",
                details={"source": "api", "timeout_minutes": 360},
                user=user,
            )
            user.api_token = None
            user.api_last_activity_at = None
            db.session.commit()
            return jsonify({"error": "Your session expired after 6 hours of inactivity. Please sign in again."}), 401

        user.api_last_activity_at = now
        db.session.commit()
        g.api_user = user
        return f(*args, **kwargs)
    return wrapper


def _ensure_api_token(user):
    if not user.api_token:
        user.api_token = secrets.token_hex(32)
        db.session.commit()
    return user.api_token


@api_bp.route("/v1/audit", methods=("GET",))
@require_api_token
def mobile_audit_log():
    if not g.api_user.is_admin:
        return jsonify({"error": "Admin access required."}), 403

    limit = min(max(int(request.args.get("limit", 100)), 1), 500)
    query = AuditLog.query.order_by(AuditLog.created_at.desc())

    action = (request.args.get("action") or "").strip()
    if action:
        query = query.filter(AuditLog.action == action)

    rows = query.limit(limit).all()
    return jsonify([
        {
            "id": row.id,
            "created_at": row.created_at.isoformat() if row.created_at else None,
            "user_id": row.user_id,
            "username": row.username,
            "action": row.action,
            "target_type": row.target_type,
            "target_id": row.target_id,
            "outcome": row.outcome,
            "details": json.loads(row.details_json) if row.details_json else None,
            "ip_address": row.ip_address,
        }
        for row in rows
    ])


@api_bp.route("/v1/auth/login", methods=("POST",))
def api_login():
    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""

    if not username or not password:
        return jsonify({"error": "Username and password are required."}), 400

    user = User.query.filter_by(username=username).first()
    if not user or not user.is_active or not check_password_hash(user.password_hash, password):
        return jsonify({"error": "Invalid username or password."}), 401

    token = secrets.token_hex(32)
    biometric_credential = secrets.token_urlsafe(48)
    user.api_token = token
    user.biometric_credential_hash = generate_password_hash(biometric_credential)
    user.api_last_activity_at = datetime.utcnow()
    record_audit(
        "login",
        target_type="user",
        target_id=user.id,
        details={"source": "api"},
        user=user,
    )
    db.session.commit()
    return jsonify({
        "token": token,
        "user": {
            "id": user.id, "username": user.username,
            "role": user.role, "is_admin": user.is_admin,
            "is_primary_admin": user.is_primary_admin,
            "is_active": user.is_active,
        },
        "biometric_credential": biometric_credential,
    })


@api_bp.route("/v1/auth/verify-password", methods=("POST",))
@require_api_token
def verify_password():
    """Verify the currently authenticated user's password without changing it."""
    data = request.get_json(silent=True) or {}
    password = str(data.get("password") or "")
    if not password or not check_password_hash(g.api_user.password_hash, password):
        record_audit(
            "security.password_verify",
            target_type="user",
            target_id=g.api_user.id,
            outcome="failure",
            details={"source": "mobile_approval"},
        )
        db.session.commit()
        return jsonify({"verified": False, "error": "Password is incorrect."}), 401

    record_audit(
        "security.password_verify",
        target_type="user",
        target_id=g.api_user.id,
        outcome="success",
        details={"source": "mobile_approval"},
    )
    db.session.commit()
    return jsonify({"verified": True})


@api_bp.route("/v1/auth/biometric-login", methods=("POST",))
def api_biometric_login():
    """Exchange a previously authenticated device token after local biometric verification."""
    data = request.get_json(silent=True) or {}
    username = str(data.get("username") or "").strip()
    credential = str(data.get("credential") or "").strip()
    if not username or not credential:
        return jsonify({"error": "Username and biometric credential are required."}), 400

    user = User.query.filter_by(username=username).first()
    if (
        not user
        or not user.is_active
        or not user.biometric_credential_hash
        or not check_password_hash(user.biometric_credential_hash, credential)
    ):
        return jsonify({"error": "This username does not have a valid biometric login on this device."}), 401

    token = secrets.token_hex(32)
    user.api_token = token
    user.api_last_activity_at = datetime.utcnow()

    record_audit(
        "login.biometric",
        target_type="user",
        target_id=user.id,
        details={"source": "mobile_biometric"},
        user=user,
    )
    db.session.commit()
    return jsonify({
        "token": token,
        "user": {
            "id": user.id,
            "username": user.username,
            "role": user.role,
            "is_admin": user.is_admin,
            "is_primary_admin": user.is_primary_admin,
        },
    })


@api_bp.route("/v1/auth/me", methods=("GET",))
@require_api_token
def api_me():
    u = g.api_user
    return jsonify({
        "id": u.id, "username": u.username,
        "role": u.role, "is_admin": u.is_admin,
        "is_primary_admin": u.is_primary_admin,
    })


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
    journey = journey_public(s)
    return {
        "id": s.id,
        "order_id": s.order_id,
        "client_operation_id": s.client_operation_id,
        "sale_type": s.sale_type or "preorder",
        "ready_for_delivery": s.ready_for_delivery,
        "sale_date": s.sale_date.isoformat() if s.sale_date else None,
        "customer_name": s.customer_name,
        "customer_phone": s.customer_phone,
        "customer_address": s.customer_address,
        "customer_city": s.customer_city,
        "customer_state": s.customer_state,
        "order_status": s.order_status,
        "journey_key": journey["current"],
        "journey_label": journey["current_label"],
        "journey_description": journey["current_description"],
        "journey_mode": journey["mode"],
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
        "estimated_shipping_sea": float(s.estimated_shipping_sea) if s.estimated_shipping_sea is not None else None,
        "estimated_shipping_air": float(s.estimated_shipping_air) if s.estimated_shipping_air is not None else None,
        "batch_transport_mode": s.batch.transport_mode if s.batch is not None else None,
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
                "line_weight_kg": float(item.line_weight_kg) if item.line_weight_kg is not None else None,
                "line_volumetric_kg": float(item.line_volumetric_kg) if item.line_volumetric_kg is not None else None,
                "line_shipping_estimate": float(item.line_shipping_estimate) if item.line_shipping_estimate is not None else None,
                "variant_note": item.variant_note,
            }
            for item in s.items
        ],
    }


def _journey_json(s):
    data = journey_public(s)
    data["tracking_url"] = f"/track/{s.public_tracking_code}" if s.public_tracking_code else None
    return data


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
        "returned_at": d.returned_at.isoformat() if d.returned_at else None,
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
        "transport_mode": b.transport_mode,
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
    cursor = db.session.query(db.func.max(MobileChange.sequence)).scalar() or 0

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

    rows = (MobileChange.query
            .filter(MobileChange.sequence > cursor)
            .order_by(MobileChange.sequence.asc())
            .limit(limit + 1)
            .all())

    has_more = len(rows) > limit
    rows = rows[:limit]
    next_cursor = rows[-1].sequence if rows else cursor

    return jsonify({
        "cursor": cursor,
        "next_cursor": int(next_cursor),
        "has_more": has_more,
        "changes": [
            {
                "id": int(row.sequence),
                "entity": row.entity_type,
                "entity_id": row.entity_id,
                "action": "deleted" if row.operation == "delete" else "updated",
                "payload": row.payload,
                "entity_type": row.entity_type,
                "operation": row.operation,
                "created_at": row.created_at.isoformat() if row.created_at else None,
            }
            for row in rows
        ],
    })


@api_bp.route("/v1/dashboard", methods=("GET",))
@require_api_token
def mobile_dashboard():
    kpis = get_kpis()
    labels, values = get_sales_last_30_days()
    return jsonify({
        "sales_today": float(kpis["sales_today"]),
        "profit_today": float(kpis["profit_today"]),
        "pending_shipments": kpis["pending_shipments"],
        "shipping_owed": float(kpis["shipping_owed"]),
        "low_stock_count": kpis["low_stock_count"],
        "batches_in_transit": kpis["batches_in_transit"],
        "sync_exceptions": kpis["sync_exceptions"],
        "journey_counts": kpis["journey_counts"],
        "sales_last_30_days": {"labels": labels, "values": values},
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
        existing = MobileOperation.query.filter_by(
            user_id=g.api_user.id,
            operation_id=operation_id,
        ).first()
        if existing:
            return jsonify(existing.response_json if isinstance(existing.response_json, dict) else json.loads(existing.response_json)), existing.response_code

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
            customer_city=(data.get("customer_city") or "").strip(),
            customer_state=(data.get("customer_state") or "").strip(),
            payment_status=data.get("payment_status") or "Paid",
            notes=(data.get("notes") or "").strip(),
            line_items=line_items,
            commit=False,
            sale_type=(data.get("sale_type") or "preorder").strip().lower(),
            client_operation_id=operation_id or None,
        )

        payload = _sale_json(sale)
        if operation_id:
            db.session.add(MobileOperation(
                user_id=g.api_user.id,
                operation_id=operation_id,
                operation_type="create_sale",
                status="completed",
                response_code=201,
                response_json=payload,
                completed_at=datetime.utcnow(),
            ))
        db.session.commit()
        return jsonify(payload), 201
    except SaleValidationError as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400
    except Exception:
        db.session.rollback()
        raise


# ---------------------------------------------------------------------------
# Complete website-parity mobile endpoints
# ---------------------------------------------------------------------------
def _mobile_operation(data):
    op = str((data or {}).get("operation_id") or "").strip()
    if op and not 8 <= len(op) <= 64:
        raise ValueError("operation_id must be between 8 and 64 characters.")
    if not op:
        op = secrets.token_hex(16)
    existing = MobileOperation.query.filter_by(user_id=g.api_user.id, operation_id=op).first()
    return op, existing


def _mobile_finish(op, kind, status, payload):
    # Offline-first writes carry this marker from the mobile queue. Once the
    # server successfully commits the queued operation, notify that same user
    # so they know the offline change has reached the server.
    request_data = request.get_json(silent=True) or {}
    offline_origin = bool(request_data.get("offline_origin"))

    db.session.add(MobileOperation(
        user_id=g.api_user.id,
        operation_id=op,
        operation_type=kind,
        status="completed",
        response_code=status,
        response_json=payload,
        completed_at=datetime.utcnow(),
    ))

    if offline_origin and status < 400:
        queue_user_notification(
            g.api_user.id,
            event_type="offline_sync_complete",
            title="Offline changes synced",
            body="Your offline change has been successfully synced.",
            data={
                "type": "offline_sync_complete",
                "sound": "scanner_beep",
                "operation_id": op,
                "operation_type": kind,
            },
        )

    db.session.commit()

    try:
        flush_outbox()
    except Exception:
        # Business writes must never fail because Firebase is unavailable.
        pass

    return jsonify(payload), status


def _mobile_replay(existing):
    return jsonify(existing.response_json if isinstance(existing.response_json, dict) else json.loads(existing.response_json)), existing.response_code


@api_bp.route("/v1/auth/change-password", methods=("POST",))
@require_api_token
def mobile_change_password():
    data = request.get_json(silent=True) or {}
    if not check_password_hash(g.api_user.password_hash, str(data.get("current_password") or "")):
        return jsonify({"error": "Current password is incorrect."}), 400
    new = str(data.get("new_password") or "")
    if len(new) < 8:
        return jsonify({"error": "New password must be at least 8 characters."}), 400
    g.api_user.password_hash = generate_password_hash(new)
    g.api_user.api_token = secrets.token_hex(32)
    g.api_user.biometric_credential_hash = None
    record_audit(
        "password.change",
        target_type="user",
        target_id=g.api_user.id,
        details={"source": "api"},
        user=g.api_user,
    )
    db.session.commit()
    return jsonify({"ok": True, "token": g.api_user.api_token})


@api_bp.route("/v1/auth/change-username", methods=("POST",))
@require_api_token
def mobile_change_username():
    data = request.get_json(silent=True) or {}
    new_username = str(data.get("new_username") or "").strip()
    if not new_username:
        return jsonify({"error": "Enter a new username."}), 400
    if User.query.filter(User.username == new_username, User.id != g.api_user.id).first():
        return jsonify({"error": "Username already exists."}), 400
    old_username = g.api_user.username
    g.api_user.username = new_username
    record_audit(
        "username.change",
        target_type="user",
        target_id=g.api_user.id,
        details={"from": old_username, "to": new_username, "source": "api"},
        user=g.api_user,
    )
    db.session.commit()
    return jsonify({"id": g.api_user.id, "username": g.api_user.username})


@api_bp.route("/v1/notifications/register-device", methods=("POST",))
@require_api_token
def register_push_device():
    data = request.get_json(silent=True) or {}
    token = str(data.get("token") or "").strip()
    platform = str(data.get("platform") or "android").strip().lower()
    if not token:
        return jsonify({"error": "Push token is required."}), 400
    if platform not in {"android", "ios", "web"}:
        return jsonify({"error": "Unsupported notification platform."}), 400

    device = PushDevice.query.filter_by(token=token).first()
    if device is None:
        device = PushDevice(
            user_id=g.api_user.id,
            token=token,
            platform=platform,
            enabled=True,
            last_seen_at=datetime.utcnow(),
        )
        db.session.add(device)
    else:
        device.user_id = g.api_user.id
        device.platform = platform
        device.enabled = True
        device.last_seen_at = datetime.utcnow()

    db.session.commit()
    try:
        from app.services.push_notifications import flush_outbox
        flush_outbox()
    except Exception:
        pass
    return jsonify({"registered": True})


@api_bp.route("/v1/notifications/unregister-device", methods=("POST",))
@require_api_token
def unregister_push_device():
    data = request.get_json(silent=True) or {}
    token = str(data.get("token") or "").strip()
    if token:
        PushDevice.query.filter_by(
            token=token,
            user_id=g.api_user.id,
        ).update({"enabled": False})
        db.session.commit()
    return jsonify({"registered": False})


@api_bp.route("/v1/auth/logout", methods=("POST",))
@require_api_token
def mobile_logout():
    user = g.api_user
    record_audit(
        "logout",
        target_type="user",
        target_id=user.id,
        details={"source": "api"},
        user=user,
    )
    user.api_token = None
    user.api_last_activity_at = None
    db.session.commit()
    return jsonify({"ok": True})


@api_bp.route("/v1/stock/adjust", methods=("POST",))
@require_api_token
def mobile_stock_adjust():
    data = request.get_json(silent=True) or {}
    try:
        op, existing = _mobile_operation(data)
        if existing: return _mobile_replay(existing)
        product = Product.query.get(int(data["product_id"]))
        if not product: raise ValueError("Product not found.")
        change = int(data["change_qty"])
        if change == 0 or product.stock + change < 0: raise ValueError("Invalid stock adjustment.")
        product.stock += change
        db.session.add(StockLog(product_id=product.id, change_qty=change, reason=str(data.get("reason") or "Manual adjustment")))
        payload = _product_json(product)
        return _mobile_finish(op, "stock_adjust", 200, payload)
    except (ValueError, TypeError, KeyError) as e:
        db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/stock-log", methods=("GET",))
@require_api_token
def mobile_stock_log():
    rows = StockLog.query.order_by(StockLog.id.desc()).limit(2000).all()
    return jsonify([_stock_log_json(x) for x in rows])


@api_bp.route("/v1/products", methods=("POST",))
@require_api_token
def mobile_create_product():
    data = request.get_json(silent=True) or {}
    try:
        op, existing = _mobile_operation(data)
        if existing: return _mobile_replay(existing)
        name = str(data.get("name") or "").strip()
        if not name: raise ValueError("Product name is required.")
        p = Product(name=name, sku=(str(data.get("sku") or "").strip() or None),
                    cost=Decimal(str(data.get("cost") or "0")),
                    length_cm=data.get("length_cm"), width_cm=data.get("width_cm"),
                    height_cm=data.get("height_cm"), actual_weight_kg=data.get("actual_weight_kg"),
                    stock=int(data.get("stock") or 0))
        if p.stock < 0: raise ValueError("Stock cannot be negative.")
        db.session.add(p); db.session.flush()
        return _mobile_finish(op, "create_product", 201, _product_json(p))
    except (ValueError, TypeError, InvalidOperation) as e:
        db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/products/<int:product_id>", methods=("PUT", "PATCH"))
@require_api_token
def mobile_update_product(product_id):
    data = request.get_json(silent=True) or {}
    try:
        op, existing = _mobile_operation(data)
        if existing: return _mobile_replay(existing)
        p = Product.query.get_or_404(product_id)
        for f in ("name", "sku", "cost", "length_cm", "width_cm", "height_cm", "actual_weight_kg"):
            if f in data:
                value = data[f]
                if f == "sku": value = str(value or "").strip() or None
                setattr(p, f, value)
        return _mobile_finish(op, "update_product", 200, _product_json(p))
    except (ValueError, TypeError, InvalidOperation) as e:
        db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/products/<int:product_id>", methods=("DELETE",))
@require_api_token
def mobile_delete_product(product_id):
    data = request.get_json(silent=True) or {}
    try:
        op, existing = _mobile_operation(data)
        if existing: return _mobile_replay(existing)
        p = Product.query.get_or_404(product_id)
        if p.sale_items: raise ValueError("A product used in sales cannot be deleted.")
        db.session.delete(p)
        return _mobile_finish(op, "delete_product", 200, {"ok": True, "id": product_id})
    except ValueError as e:
        db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/sales/<int:sale_id>", methods=("GET",))
@require_api_token
def mobile_sale_detail(sale_id):
    return jsonify(_sale_json(Sale.query.get_or_404(sale_id)))


@api_bp.route("/v1/sales/<int:sale_id>/journey", methods=("GET",))
@require_api_token
def mobile_sale_journey(sale_id):
    sale = Sale.query.get_or_404(sale_id)
    data = _journey_json(sale)
    data["manual_stages"] = [
        {"key": key, "label": stage_label(key)}
        for key in flow_for(sale)
    ]
    data["estimated_shipping_sea"] = float(sale.estimated_shipping_sea) if sale.estimated_shipping_sea is not None else None
    data["estimated_shipping_air"] = float(sale.estimated_shipping_air) if sale.estimated_shipping_air is not None else None
    data["batch_transport_mode"] = sale.batch.transport_mode if sale.batch is not None else None
    return jsonify(data)


@api_bp.route("/v1/sales/<int:sale_id>/status", methods=("POST",))
@require_api_token
def mobile_sale_status(sale_id):
    data = request.get_json(silent=True) or {}
    try:
        op, existing = _mobile_operation(data)
        if existing: return _mobile_replay(existing)
        sale = Sale.query.get_or_404(sale_id)
        status = data.get("status") or data.get("order_status")
        payment_status = data.get("payment_status")
        if status is None and payment_status is None:
            raise ValueError("Nothing to update.")
        if status is not None:
            status = str(status)
            if status not in {"New", "Packed", "Shipped", "Delivered", "Cancelled"}: raise ValueError("Invalid order status.")
            if status == "Cancelled" and sale.order_status != "Cancelled" and sale.is_stock_sale:
                for item in sale.items:
                    product = Product.query.get(item.product_id)
                    if product:
                        product.stock += item.qty
                        db.session.add(StockLog(product_id=product.id, change_qty=item.qty, reason=f"Sale #{sale.id} Cancelled"))
            old_status = sale.order_status
            sale.order_status = status
            record_audit(
                "sale.status",
                target_type="sale",
                target_id=sale.id,
                details={"from": old_status, "to": status, "source": "api"},
                user=g.api_user,
            )
        if payment_status is not None:
            payment_status = str(payment_status)
            if payment_status not in {"Paid", "Pending", "Refunded"}: raise ValueError("Invalid payment status.")
            old_payment = sale.payment_status
            sale.payment_status = payment_status
            record_audit(
                "sale.payment_status",
                target_type="sale",
                target_id=sale.id,
                details={"from": old_payment, "to": payment_status, "source": "api"},
                user=g.api_user,
            )
        return _mobile_finish(op, "sale_status", 200, _sale_json(sale))
    except ValueError as e:
        db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/sales/<int:sale_id>/settle-shipping", methods=("POST",))
@require_api_token
def mobile_settle_shipping(sale_id):
    data = request.get_json(silent=True) or {}
    try:
        op, existing = _mobile_operation(data)
        if existing: return _mobile_replay(existing)
        sale = Sale.query.get_or_404(sale_id)
        if sale.is_stock_sale: raise ValueError("Stocked sales have no shipping to settle.")
        if not sale.batch_id or not sale.batch: raise ValueError("Sale is not in a batch.")
        if sale.batch.status != ShipmentBatch.STATUS_ARRIVED: raise ValueError("Batch must be arrived first.")
        sale.shipping_payment_settled = True
        sale.shipping_payment_settled_at = datetime.utcnow()
        record_audit(
            'shipping.settle', target_type='sale', target_id=sale.id,
            details={'shipping_amount': str(sale.actual_shipping_cost or 0), 'source': 'api'},
            user=g.api_user,
        )
        return _mobile_finish(op, "settle_shipping", 200, _sale_json(sale))
    except ValueError as e:
        db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/sales/<int:sale_id>/arrival-notice", methods=("GET",))
@require_api_token
def mobile_arrival_notice(sale_id):
    """The "your goods have arrived" WhatsApp message for one sale, plus the wa.me link that opens it."""
    from app.services.notifications import build_arrival_notice, NotificationError
    sale = Sale.query.get_or_404(sale_id)
    try:
        return jsonify(build_arrival_notice(sale))
    except NotificationError as e:
        return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/sales/<int:sale_id>/invoice.pdf", methods=("GET",))
@require_api_token
def mobile_invoice_pdf(sale_id):
    from app.services.invoices import generate_invoice_pdf
    from flask import send_file
    sale = Sale.query.get_or_404(sale_id)
    pdf = generate_invoice_pdf(sale)
    name = sale.order_id or str(sale.id)
    return send_file(pdf, mimetype="application/pdf", as_attachment=True, download_name=f"invoice-{name}.pdf")


@api_bp.route("/v1/batches", methods=("GET",))
@require_api_token
def mobile_batches():
    return jsonify([_batch_json(x) for x in ShipmentBatch.query.order_by(ShipmentBatch.id.desc()).all()])


@api_bp.route("/v1/batches", methods=("POST",))
@require_api_token
def mobile_create_batch():
    data = request.get_json(silent=True) or {}
    try:
        op, existing = _mobile_operation(data)
        if existing: return _mobile_replay(existing)
        name = str(data.get("name") or "").strip()
        if not name: raise ValueError("Batch needs a name.")
        transport_mode = str(data.get("transport_mode") or ShipmentBatch.MODE_SEA).strip().lower()
        if transport_mode not in ShipmentBatch.MODES:
            raise ValueError("Choose how this batch travels: Air or Sea.")
        b = ShipmentBatch(
            name=name,
            notes=str(data.get("notes") or "").strip() or None,
            status=ShipmentBatch.STATUS_IN_TRANSIT,
            transport_mode=transport_mode,
        )
        db.session.add(b); db.session.flush()
        record_audit(
            "batch.create",
            target_type="shipment_batch",
            target_id=b.id,
            details={"name": b.name, "transport_mode": b.transport_mode, "source": "api"},
            user=g.api_user,
        )
        return _mobile_finish(op, "create_batch", 201, _batch_json(b))
    except ValueError as e:
        db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/batches/<int:batch_id>/sales/<int:sale_id>", methods=("POST",))
@require_api_token
def mobile_batch_sale(batch_id, sale_id):
    data = request.get_json(silent=True) or {}
    try:
        op, existing = _mobile_operation(data)
        if existing: return _mobile_replay(existing)
        b, s = ShipmentBatch.query.get_or_404(batch_id), Sale.query.get_or_404(sale_id)
        action = str(data.get("action") or "add")
        if action == "remove":
            if s.batch_id != b.id: raise ValueError("Sale is not in this batch.")
            s.batch_id = None
            s.batch_assigned_at = None
            record_audit(
                "batch.remove_sale",
                target_type="sale",
                target_id=s.id,
                details={"batch_id": b.id, "source": "api"},
                user=g.api_user,
            )
        else:
            if s.is_stock_sale: raise ValueError("Stocked sales are not shipped in batches.")
            if b.status != ShipmentBatch.STATUS_IN_TRANSIT: raise ValueError("Batch is no longer in transit.")
            if s.order_status == "Cancelled": raise ValueError("Cancelled sales cannot be added.")
            s.batch_id = b.id
            s.batch_assigned_at = datetime.utcnow()
            record_audit(
                "batch.add_sale",
                target_type="sale",
                target_id=s.id,
                details={"batch_id": b.id, "transport_mode": b.transport_mode, "source": "api"},
                user=g.api_user,
            )
        return _mobile_finish(op, "batch_sale", 200, _batch_json(b))
    except ValueError as e:
        db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/batches/<int:batch_id>/arrive", methods=("POST",))
@require_api_token
@require_admin_api
def mobile_batch_arrive(batch_id):
    data = request.get_json(silent=True) or {}
    try:
        op, existing = _mobile_operation(data)
        if existing: return _mobile_replay(existing)
        b = ShipmentBatch.query.get_or_404(batch_id)
        if b.status != ShipmentBatch.STATUS_IN_TRANSIT: raise ValueError("Batch must be In Transit.")
        if not b.sales: raise ValueError("Batch has no sales assigned.")
        volume_rate = get_volume_rate(b.transport_mode, date.today())
        kg_rate = get_rate_per_kg()
        for s in b.sales:
            s.actual_shipping_cost = shipping_cost_for_items(
                s.items, b.transport_mode, volume_rate, kg_rate
            )
            s.total_amount = (s.subtotal_amount or Decimal("0")) + s.actual_shipping_cost
        b.arrived_at = datetime.utcnow()
        b.status = ShipmentBatch.STATUS_ARRIVED
        record_audit(
            'batch.arrive', target_type='shipment_batch', target_id=b.id,
            details={'transport_mode': b.transport_mode, 'sale_count': len(b.sales), 'name': b.name, 'source': 'api'},
            user=g.api_user,
        )
        queue_batch_arrival(b, exclude_user_id=g.api_user.id)
        result = _mobile_finish(op, "batch_arrive", 200, _batch_json(b))
        db.session.flush()
        db.session.commit()
        try:
            flush_outbox()
        except Exception:
            pass
        return result
    except (ValueError, RateMissingError) as e:
        db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/batches/<int:batch_id>/undo-arrival", methods=("POST",))
@require_api_token
@require_admin_api
def mobile_batch_undo_arrival(batch_id):
    data = request.get_json(silent=True) or {}
    try:
        op, existing = _mobile_operation(data)
        if existing:
            return _mobile_replay(existing)
        batch = mark_unarrived(batch_id, user_id=g.api_user.id)
        payload = _batch_json(batch)
        return _mobile_finish(op, "batch_undo_arrival", 200, payload)
    except BatchValidationError as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/deliveries", methods=("GET",))
@require_api_token
def mobile_deliveries():
    return jsonify([_delivery_json(x) for x in Delivery.query.order_by(Delivery.id.desc()).all()])


@api_bp.route("/v1/deliveries/ready", methods=("GET",))
@require_api_token
def mobile_ready_deliveries():
    from sqlalchemy import or_
    rows = Sale.query.filter(or_(Sale.shipping_payment_settled.is_(True), Sale.sale_type == "stock"), Sale.delivery_id.is_(None), Sale.order_status != "Cancelled").order_by(Sale.id.desc()).all()
    return jsonify([_sale_json(x) for x in rows])


@api_bp.route("/v1/deliveries/suggestions", methods=("GET",))
@require_api_token
def mobile_delivery_suggestions():
    """Groups of ready sales that could share one courier bag (same phone, name, city or state).
    Purely a suggestion list — consolidating is always the person's choice."""
    return jsonify(find_consolidation_groups())


@api_bp.route("/v1/deliveries", methods=("POST",))
@require_api_token
def mobile_create_delivery():
    data = request.get_json(silent=True) or {}
    try:
        op, existing = _mobile_operation(data)
        if existing: return _mobile_replay(existing)
        ids = [int(x) for x in data.get("sale_ids") or []]
        if not ids: raise ValueError("Select at least one sale.")
        sales = Sale.query.filter(Sale.id.in_(ids)).all()
        if len(sales) != len(ids): raise ValueError("One or more sales were not found.")
        for s in sales:
            if s.delivery_id is not None: raise ValueError(f"Sale #{s.id} is already assigned to a delivery.")
            if not s.ready_for_delivery: raise ValueError(f"Sale #{s.id} is not ready for delivery.")
        consolidation_type = check_consolidation(sales)
        method=str(data.get("method") or "").strip()
        if not method: raise ValueError("Delivery method is required.")
        d=Delivery(method=method,status=Delivery.STATUS_PENDING,is_consolidated=len(sales)>1,consolidation_type=consolidation_type,delivery_address=str(data.get("delivery_address") or "").strip() or sales[0].customer_address,notes=str(data.get("notes") or "").strip() or None)
        db.session.add(d); db.session.flush()
        for s in sales: s.delivery_id=d.id
        record_audit(
            "delivery.create",
            target_type="delivery",
            target_id=d.id,
            details={"sale_ids": [s.id for s in sales], "method": method, "source": "api"},
            user=g.api_user,
        )
        return _mobile_finish(op,"create_delivery",201,_delivery_json(d))
    except ValueError as e:
        db.session.rollback(); return jsonify({"error":str(e)}),400


@api_bp.route("/v1/deliveries/<int:delivery_id>/status", methods=("POST",))
@require_api_token
def mobile_delivery_status(delivery_id):
    data=request.get_json(silent=True) or {}
    try:
        op,existing=_mobile_operation(data)
        if existing:return _mobile_replay(existing)
        d=Delivery.query.get_or_404(delivery_id); status=str(data.get("status") or "")
        if status not in {Delivery.STATUS_PENDING,Delivery.STATUS_OUT_FOR_DELIVERY,Delivery.STATUS_DELIVERED,Delivery.STATUS_RETURNED}:raise ValueError("Invalid delivery status.")
        old_status = d.status
        d.status=status
        if status==Delivery.STATUS_OUT_FOR_DELIVERY and not d.shipped_at:d.shipped_at=datetime.utcnow()
        if status==Delivery.STATUS_DELIVERED:
            d.delivered_at=datetime.utcnow()
            for s in d.sales:s.order_status="Delivered"
        record_audit(
            "delivery.status",
            target_type="delivery",
            target_id=d.id,
            details={"from": old_status, "to": status, "sale_ids": [s.id for s in d.sales], "source": "api"},
            user=g.api_user,
        )
        return _mobile_finish(op,"delivery_status",200,_delivery_json(d))
    except ValueError as e:
        db.session.rollback();return jsonify({"error":str(e)}),400


@api_bp.route("/v1/deliveries/<int:delivery_id>/label", methods=("POST",))
@require_api_token
def mobile_prepare_label(delivery_id):
    data=request.get_json(silent=True) or {}
    try:
        op,existing=_mobile_operation(data)
        if existing:return _mobile_replay(existing)
        d=Delivery.query.get_or_404(delivery_id);weight=Decimal(str(data.get("package_weight_kg") or "0"));dims=str(data.get("package_dimensions") or "").strip()
        if weight<=0 or not dims:raise ValueError("Package weight and dimensions are required.")
        d.package_weight_kg=weight;d.package_dimensions=dims;d.remarks=str(data.get("remarks") or "").strip() or None
        return _mobile_finish(op,"prepare_label",200,_delivery_json(d))
    except (ValueError,InvalidOperation) as e:
        db.session.rollback();return jsonify({"error":str(e)}),400


@api_bp.route("/v1/deliveries/<int:delivery_id>/label.pdf", methods=("GET",))
@require_api_token
def mobile_label_pdf(delivery_id):
    from app.services.labels import label_ready, generate_label_pdf
    delivery = Delivery.query.get_or_404(delivery_id)
    if not label_ready(delivery):
        return jsonify({"error": "Enter package weight and dimensions before generating the label."}), 400
    pdf = generate_label_pdf(delivery)
    name = delivery.sales[0].order_id if delivery.sales else str(delivery.id)
    from flask import send_file
    return send_file(pdf, mimetype="application/pdf", as_attachment=True, download_name=f"label-{name}.pdf")




@api_bp.route("/v1/sales/journey", methods=("POST",))
@require_api_token
def mobile_update_journey():
    data = request.get_json(silent=True) or {}
    try:
        op, existing = _mobile_operation(data)
        if existing:
            return _mobile_replay(existing)
        ids = [int(x) for x in (data.get("sale_ids") or [])]
        if not ids:
            raise ValueError("Select at least one sale.")
        stage = str(data.get("stage") or "").strip()
        sales = Sale.query.filter(Sale.id.in_(ids)).all()
        found_ids = {sale.id for sale in sales}
        missing_ids = [sale_id for sale_id in ids if sale_id not in found_ids]
        if missing_ids:
            raise ValueError(
                "One or more selected sales were not found: "
                + ", ".join(str(x) for x in missing_ids)
                + "."
            )
        updated, unchanged, skipped = set_manual_stage_bulk(sales, stage, user_id=g.api_user.id)
        if updated:
            changed_ids = [
                sale.id
                for sale in sales
                if sale.id in found_ids
            ]
            record_audit(
                "journey.update",
                target_type="sale",
                target_id=",".join(str(x) for x in changed_ids),
                details={"stage": stage, "sale_ids": [x.id for x in sales], "updated": updated},
                user=g.api_user,
            )
        payload = {"updated": updated, "unchanged": unchanged, "skipped": skipped, "sales": [_journey_json(s) for s in sales]}
        return _mobile_finish(op, "update_journey", 200, payload)
    except (ValueError, JourneyError) as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/shipping", methods=("GET",))
@require_api_token
def mobile_shipping():
    q=Shipping.query.join(Sale,Shipping.sale_id==Sale.id);tracking=str(request.args.get('tracking_number') or '').strip();state=str(request.args.get('state') or '').strip()
    if tracking:q=q.filter(Shipping.tracking_number.ilike(f'%{tracking}%'))
    if state:q=q.filter(Sale.customer_state.ilike(f'%{state}%'))
    return jsonify([_shipping_json(x) for x in q.order_by(Shipping.id.desc()).all()])


@api_bp.route("/v1/shipping", methods=("POST",))
@require_api_token
def mobile_create_shipping():
    data=request.get_json(silent=True) or {}
    try:
        op,existing=_mobile_operation(data)
        if existing:return _mobile_replay(existing)
        sale=Sale.query.get(int(data['sale_id']))
        if not sale:raise ValueError('Sale not found.')
        if sale.order_status!='Packed':raise ValueError("Sale must be Packed before shipping.")
        if sale.shipping:raise ValueError('This sale already has a shipment.')
        cbm=sum((i.line_cbm or Decimal('0')) for i in sale.items);actual=sum(((i.product.actual_weight_kg if i.product else Decimal('0')) or Decimal('0'))*i.qty for i in sale.items);vol=sum((i.line_volumetric_kg or Decimal('0')) for i in sale.items)
        s=Shipping(sale_id=sale.id,courier=str(data.get('courier') or '').strip(),tracking_number=str(data.get('tracking_number') or '').strip(),total_cbm=cbm,chargeable_weight_kg=max(actual,vol),shipping_status='Shipped',shipped_at=datetime.utcnow(),notes=str(data.get('notes') or '').strip() or None)
        db.session.add(s);sale.order_status='Shipped';db.session.flush();return _mobile_finish(op,'create_shipping',201,_shipping_json(s))
    except (ValueError,KeyError) as e:
        db.session.rollback();return jsonify({'error':str(e)}),400


@api_bp.route("/v1/shipping/<int:shipping_id>", methods=("POST","PUT","PATCH"))
@require_api_token
def mobile_update_shipping(shipping_id):
    data=request.get_json(silent=True) or {}
    try:
        op,existing=_mobile_operation(data)
        if existing:return _mobile_replay(existing)
        s=Shipping.query.get_or_404(shipping_id)
        for f in ('courier','tracking_number','notes'):
            if f in data:setattr(s,f,str(data[f] or '').strip() or None)
        if data.get('shipping_status'):
            st=str(data['shipping_status'])
            if st not in {'Processing','Shipped','In Transit','Delivered'}:raise ValueError('Invalid shipping status.')
            s.shipping_status=st
            if st=='Shipped' and not s.shipped_at:s.shipped_at=datetime.utcnow()
            if st=='Delivered':
                s.delivered_at=datetime.utcnow();sale=Sale.query.get(s.sale_id)
                if sale:sale.order_status='Delivered'
        return _mobile_finish(op,'update_shipping',200,_shipping_json(s))
    except ValueError as e:
        db.session.rollback();return jsonify({'error':str(e)}),400


@api_bp.route("/v1/courier-rates", methods=("GET",))
@require_api_token
def mobile_courier_rates():return jsonify([_rate_json(x) for x in CourierRate.query.order_by(CourierRate.state).all()])

@api_bp.route("/v1/courier-rates", methods=("POST",))
@require_api_token
@require_admin_api
def mobile_create_courier_rate():
    data=request.get_json(silent=True) or {}
    try:
        op,existing=_mobile_operation(data)
        if existing:return _mobile_replay(existing)
        r=CourierRate(state=str(data.get('state') or '').strip(),rate_per_cbm=Decimal(str(data.get('rate_per_cbm'))));db.session.add(r);db.session.flush();return _mobile_finish(op,'create_courier_rate',201,_rate_json(r))
    except (ValueError,InvalidOperation) as e:db.session.rollback();return jsonify({'error':str(e)}),400

@api_bp.route("/v1/courier-rates/<int:rate_id>", methods=("PUT","PATCH","DELETE"))
@require_api_token
@require_admin_api
def mobile_update_courier_rate(rate_id):
    data=request.get_json(silent=True) or {}
    try:
        op,existing=_mobile_operation(data)
        if existing:return _mobile_replay(existing)
        r=CourierRate.query.get_or_404(rate_id)
        if request.method=='DELETE':db.session.delete(r);payload={'ok':True,'id':rate_id}
        else:
            if 'state' in data:r.state=str(data['state']).strip()
            if 'rate_per_cbm' in data:r.rate_per_cbm=Decimal(str(data['rate_per_cbm']))
            payload=_rate_json(r)
        return _mobile_finish(op,'update_courier_rate',200,payload)
    except (ValueError,InvalidOperation) as e:db.session.rollback();return jsonify({'error':str(e)}),400

@api_bp.route("/v1/monthly-air-rates", methods=("GET",))
@require_api_token
def mobile_monthly_air_rates():
    return jsonify([{"id": x.id, "month": x.month.isoformat() if x.month else None, "rate_per_kg": float(x.rate_per_kg)} for x in MonthlyAirRate.query.order_by(MonthlyAirRate.month.desc()).all()])

@api_bp.route("/v1/monthly-air-rates", methods=("POST",))
@require_api_token
@require_admin_api
def mobile_create_monthly_air_rate():
    data=request.get_json(silent=True) or {}
    try:
        op,existing=_mobile_operation(data)
        if existing:return _mobile_replay(existing)
        month=date.fromisoformat(str(data.get("month"))[:10]).replace(day=1)
        rate=Decimal(str(data.get("rate_per_kg")))
        if rate < 0: raise ValueError("Air rate cannot be negative.")
        row=MonthlyAirRate(month=month,rate_per_kg=rate);db.session.add(row);db.session.flush()
        return _mobile_finish(op,"create_monthly_air_rate",201,{"id":row.id,"month":row.month.isoformat(),"rate_per_kg":float(row.rate_per_kg)})
    except (ValueError,InvalidOperation) as e:db.session.rollback();return jsonify({"error":str(e)}),400

@api_bp.route("/v1/monthly-air-rates/<int:rate_id>", methods=("PUT","PATCH","DELETE"))
@require_api_token
@require_admin_api
def mobile_update_monthly_air_rate(rate_id):
    data=request.get_json(silent=True) or {}
    try:
        op,existing=_mobile_operation(data)
        if existing:return _mobile_replay(existing)
        row=MonthlyAirRate.query.get_or_404(rate_id)
        if request.method=="DELETE":db.session.delete(row);payload={"ok":True,"id":rate_id}
        else:
            if "month" in data:row.month=date.fromisoformat(str(data["month"])[:10]).replace(day=1)
            if "rate_per_kg" in data:row.rate_per_kg=Decimal(str(data["rate_per_kg"]))
            payload={"id":row.id,"month":row.month.isoformat(),"rate_per_kg":float(row.rate_per_kg)}
        return _mobile_finish(op,"update_monthly_air_rate",200,payload)
    except (ValueError,InvalidOperation) as e:db.session.rollback();return jsonify({"error":str(e)}),400

@api_bp.route("/v1/monthly-shipping-rates", methods=("GET",))
@require_api_token
def mobile_monthly_rates():return jsonify([_monthly_rate_json(x) for x in MonthlyShippingRate.query.order_by(MonthlyShippingRate.month.desc()).all()])

@api_bp.route("/v1/monthly-shipping-rates", methods=("POST",))
@require_api_token
@require_admin_api
def mobile_create_monthly_rate():
    data=request.get_json(silent=True) or {}
    try:
        op,existing=_mobile_operation(data)
        if existing:return _mobile_replay(existing)
        month=date.fromisoformat(str(data.get('month'))[:10]).replace(day=1);r=MonthlyShippingRate(month=month,rate_per_cbm=Decimal(str(data.get('rate_per_cbm'))));db.session.add(r);db.session.flush();return _mobile_finish(op,'create_monthly_rate',201,_monthly_rate_json(r))
    except (ValueError,InvalidOperation) as e:db.session.rollback();return jsonify({'error':str(e)}),400

@api_bp.route("/v1/monthly-shipping-rates/<int:rate_id>", methods=("PUT","PATCH","DELETE"))
@require_api_token
@require_admin_api
def mobile_update_monthly_rate(rate_id):
    data=request.get_json(silent=True) or {}
    try:
        op,existing=_mobile_operation(data)
        if existing:return _mobile_replay(existing)
        r=MonthlyShippingRate.query.get_or_404(rate_id)
        if request.method=='DELETE':db.session.delete(r);payload={'ok':True,'id':rate_id}
        else:
            if 'month' in data:r.month=date.fromisoformat(str(data['month'])[:10]).replace(day=1)
            if 'rate_per_cbm' in data:r.rate_per_cbm=Decimal(str(data['rate_per_cbm']))
            payload=_monthly_rate_json(r)
        return _mobile_finish(op,'update_monthly_rate',200,payload)
    except (ValueError,InvalidOperation) as e:db.session.rollback();return jsonify({'error':str(e)}),400


def _settings_json(s):
    return {
        'id': s.id, 'label_width_mm': s.label_width_mm, 'label_height_mm': s.label_height_mm,
        'business_name': s.business_name, 'business_phone': s.business_phone,
        'business_address': s.business_address,
        'bank_name': s.bank_name, 'bank_account_number': s.bank_account_number,
        'bank_account_name': s.bank_account_name,
        'shipping_rate_per_kg': float(s.shipping_rate_per_kg) if s.shipping_rate_per_kg is not None else 1115.0,
        'has_logo': bool(s.logo_data), 'logo_mimetype': s.logo_mimetype,
    }


@api_bp.route("/v1/settings", methods=("GET",))
@require_api_token
def mobile_settings_get():
    from app.services.settings import get_settings
    return jsonify(_settings_json(get_settings()))

@api_bp.route("/v1/settings", methods=("POST","PUT","PATCH"))
@require_api_token
@require_admin_api
def mobile_settings_update():
    from app.services.settings import get_settings
    data=request.get_json(silent=True) or {}
    try:
        op,existing=_mobile_operation(data)
        if existing:return _mobile_replay(existing)
        s=get_settings()
        for f in ('business_name','business_phone','business_address','bank_name','bank_account_number','bank_account_name'):
            if f in data:setattr(s,f,str(data[f] or '').strip() or None)
        for f in ('label_width_mm','label_height_mm'):
            if f in data:setattr(s,f,int(data[f]))
        if str(data.get('shipping_rate_per_kg') if data.get('shipping_rate_per_kg') is not None else '').strip():
            try:kg=Decimal(str(data['shipping_rate_per_kg']).replace(',','').strip())
            except InvalidOperation:raise ValueError('Per-kg shipping rate must be a number.')
            if kg<0:raise ValueError('Per-kg shipping rate cannot be negative.')
            s.shipping_rate_per_kg=kg
        if data.get('logo_base64'):
            import base64
            s.logo_data=base64.b64decode(data['logo_base64']);s.logo_mimetype=str(data.get('logo_mimetype') or 'image/png')
        record_audit(
            "settings.update",
            target_type="app_settings",
            target_id=s.id,
            details={"source": "api"},
            user=g.api_user,
        )
        payload=_settings_json(s)
        return _mobile_finish(op,'update_settings',200,payload)
    except (ValueError,TypeError) as e:db.session.rollback();return jsonify({'error':str(e)}),400


@api_bp.route("/v1/users", methods=("GET",))
@require_api_token
def mobile_users():
    return jsonify([{
        'id': u.id, 'username': u.username, 'role': u.role,
        'is_admin': u.is_admin, 'is_primary_admin': u.is_primary_admin,
        'is_active': u.is_active,
        'created_at': u.created_at.isoformat() if u.created_at else None,
    } for u in User.query.order_by(User.username).all()])

@api_bp.route("/v1/users", methods=("POST",))
@require_api_token
@require_admin_api
def mobile_create_user():
    data=request.get_json(silent=True) or {}
    try:
        op,existing=_mobile_operation(data)
        if existing:return _mobile_replay(existing)
        username=str(data.get('username') or '').strip();password=str(data.get('password') or '')
        role = str(data.get('role') or User.ROLE_STAFF).strip().lower()
        if role not in (User.ROLE_ADMIN, User.ROLE_STAFF):raise ValueError('Role must be admin or staff.')
        if not username or len(password)<8:raise ValueError('Username and password (8+ characters) are required.')
        if User.query.filter_by(username=username).first():raise ValueError('Username already exists.')
        u=User(username=username,password_hash=generate_password_hash(password),role=role);db.session.add(u);db.session.flush()
        record_audit(
            "user.create",
            target_type="user",
            target_id=u.id,
            details={"username": u.username, "role": u.role, "source": "api"},
            user=g.api_user,
        )
        return _mobile_finish(op,'create_user',201,{'id':u.id,'username':u.username,'role':u.role,'is_admin':u.is_admin,'is_primary_admin':u.is_primary_admin,'is_active':u.is_active,'created_at':u.created_at.isoformat() if u.created_at else None})
    except ValueError as e:db.session.rollback();return jsonify({'error':str(e)}),400

@api_bp.route("/v1/users/<int:user_id>", methods=("PUT","PATCH"))
@require_api_token
def mobile_update_user(user_id):
    data=request.get_json(silent=True) or {}
    try:
        op,existing=_mobile_operation(data)
        if existing:return _mobile_replay(existing)
        u=User.query.get_or_404(user_id)
        # Staff (and admins) can always edit their own username/password —
        # that's plain self-service, same as the change-password screen.
        # Editing someone ELSE's account is an admin-only action.
        if u.id != g.api_user.id and not g.api_user.is_admin:
            raise PermissionError('You can only edit your own account.')
        if data.get('username'):
            n=str(data['username']).strip()
            if User.query.filter(User.username==n,User.id!=u.id).first():raise ValueError('Username already exists.')
            u.username=n
        if data.get('password'):
            if len(str(data['password']))<8:raise ValueError('Password must be at least 8 characters.')
            u.password_hash=generate_password_hash(str(data['password']))
            u.biometric_credential_hash = None
            u.api_token = None
            u.api_last_activity_at = None
        if 'is_active' in data and g.api_user.is_admin:
            if u.is_primary_admin and not bool(data['is_active']):
                raise ValueError('The original admin cannot be deactivated.')
            u.is_active = bool(data['is_active'])
            if not u.is_active:
                u.api_token = None
                u.api_last_activity_at = None
        if data.get('role') and g.api_user.is_admin:
            role = str(data['role']).strip().lower()
            if role not in (User.ROLE_ADMIN, User.ROLE_STAFF):raise ValueError('Role must be admin or staff.')
            if u.is_primary_admin and role != User.ROLE_ADMIN:raise ValueError('The original admin cannot be demoted.')
            u.role=role
        record_audit(
            "user.update",
            target_type="user",
            target_id=u.id,
            details={"source": "api"},
            user=g.api_user,
        )
        return _mobile_finish(op,'update_user',200,{'id':u.id,'username':u.username,'role':u.role,'is_admin':u.is_admin,'is_primary_admin':u.is_primary_admin,'is_active':u.is_active,'created_at':u.created_at.isoformat() if u.created_at else None})
    except ValueError as e:db.session.rollback();return jsonify({'error':str(e)}),400
    except PermissionError as e:db.session.rollback();return jsonify({'error':str(e)}),403

@api_bp.route("/v1/users/<int:user_id>", methods=("DELETE",))
@require_api_token
@require_admin_api
def mobile_delete_user(user_id):
    u=User.query.get_or_404(user_id)
    if u.is_primary_admin:
        return jsonify({'error':'The original admin account cannot be removed.'}),400
    if u.id==g.api_user.id:
        return jsonify({'error':'You cannot remove your own account.'}),400
    if u.is_admin and not g.api_user.is_primary_admin:
        return jsonify({'error':'Only the original admin can remove another admin account.'}),403
    record_audit(
        "user.delete",
        target_type="user",
        target_id=u.id,
        details={"username": u.username, "role": u.role, "source": "api"},
        user=g.api_user,
    )
    AuditLog.query.filter_by(user_id=u.id).update({"user_id": None}, synchronize_session=False)
    db.session.delete(u)
    db.session.commit()
    return jsonify({'ok':True,'id':user_id})


@api_bp.route("/v1/admin/sales/<int:sale_id>", methods=("DELETE",))
@require_api_token
@require_admin_api
def mobile_delete_sale(sale_id):
    sale = Sale.query.get_or_404(sale_id)
    if sale.delivery_id:
        return jsonify({"error": "Remove the sale from its delivery before deleting it."}), 400
    if sale.shipping_payment_settled:
        return jsonify({"error": "A sale with settled shipping cannot be deleted."}), 400

    try:
        if sale.is_stock_sale:
            for item in sale.items:
                product = Product.query.get(item.product_id)
                if product:
                    product.stock += item.qty
                    db.session.add(
                        StockLog(
                            product_id=product.id,
                            change_qty=item.qty,
                            reason=f"Deleted sale #{sale.id}",
                        )
                    )
        record_audit(
            "sale.delete",
            target_type="sale",
            target_id=sale.id,
            details={"order_id": sale.order_id, "sale_type": sale.sale_type},
            user=g.api_user,
        )
        db.session.delete(sale)
        db.session.commit()
        return jsonify({"ok": True, "id": sale_id})
    except Exception:
        db.session.rollback()
        raise


@api_bp.route("/v1/admin/batches/<int:batch_id>", methods=("DELETE",))
@require_api_token
@require_admin_api
def mobile_delete_batch(batch_id):
    batch = ShipmentBatch.query.get_or_404(batch_id)
    if batch.status != ShipmentBatch.STATUS_IN_TRANSIT:
        return jsonify({"error": "Only an In Transit shipment batch can be deleted. Undo its arrival first."}), 400
    if any(s.shipping_payment_settled or s.delivery_id for s in batch.sales):
        return jsonify({"error": "This batch contains sales that are already settled or assigned to delivery."}), 400
    sale_ids = [sale.id for sale in batch.sales]
    for sale in batch.sales:
        sale.batch_id = None
        sale.batch_assigned_at = None
    record_audit(
        "batch.delete",
        target_type="shipment_batch",
        target_id=batch.id,
        details={"name": batch.name, "sale_ids": sale_ids},
        user=g.api_user,
    )
    db.session.delete(batch)
    db.session.commit()
    return jsonify({"ok": True, "id": batch_id, "detached_sale_ids": sale_ids})


@api_bp.route("/v1/reports/sales", methods=("GET",))
@require_api_token
def mobile_sales_report():
    from datetime import timedelta
    def parse(v):
        try:return date.fromisoformat(v) if v else None
        except ValueError:return None
    end=parse(request.args.get('end_date')) or date.today();start=parse(request.args.get('start_date')) or end-timedelta(days=29)
    sales=Sale.query.filter(Sale.sale_date>=start,Sale.sale_date<=end).order_by(Sale.sale_date.desc(),Sale.id.desc()).all()
    totals={'subtotal':sum((s.subtotal_amount or 0) for s in sales),'estimated_shipping':sum((s.estimated_shipping_cost or 0) for s in sales),'actual_shipping':sum((s.actual_shipping_cost or 0) for s in sales),'total':sum((s.total_amount or 0) for s in sales)}
    return jsonify({'start_date':start.isoformat(),'end_date':end.isoformat(),'totals':{k:float(v) for k,v in totals.items()},'sales':[_sale_json(s) for s in sales]})

@api_bp.route("/v1/reports/shipping", methods=("GET",))
@require_api_token
def mobile_shipping_report():
    return jsonify([{'sale_id':s.id,'customer_name':s.customer_name,'batch_name':s.batch.name if s.batch else '','batch_status':s.batch.status if s.batch else '','estimated_shipping_cost':float(s.estimated_shipping_cost or 0),'actual_shipping_cost':float(s.actual_shipping_cost or 0),'shipping_payment_settled':bool(s.shipping_payment_settled)} for s in Sale.query.filter(Sale.batch_id.isnot(None)).order_by(Sale.id).all()])

@api_bp.route("/v1/reports/inventory", methods=("GET",))
@require_api_token
def mobile_inventory_report():return jsonify([_product_json(x) for x in Product.query.order_by(Product.name).all()])

@api_bp.route("/v1/admin/clear-test-data", methods=("POST",))
@require_api_token
@require_admin_api
def mobile_clear_test_data():
    from app.services.data_tools import clear_test_data, CONFIRMATION_PHRASE
    data=request.get_json(silent=True) or {}
    if data.get('confirmation')!=CONFIRMATION_PHRASE:return jsonify({'error':f'Type exactly: {CONFIRMATION_PHRASE}'}),400
    try:
        counts=clear_test_data(data.get('confirmation'))
    except ValueError as e:
        return jsonify({'error':str(e)}),400
    return jsonify({'ok':True,'counts':counts}),
