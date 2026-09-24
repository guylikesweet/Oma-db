"""Mobile API: the mobile client uses the same business services as the website.
All endpoints are under /api/v1.  The API is intentionally a thin transport
layer so business rules do not fork between web and mobile.
"""
from functools import wraps
from decimal import Decimal, InvalidOperation
from datetime import date, datetime
import secrets

from flask import Blueprint, request, jsonify, g, send_file, Response
from werkzeug.security import check_password_hash, generate_password_hash
from sqlalchemy import event
from sqlalchemy.orm import Session

from app import db
from app.models import (
    User, Product, Sale, SaleItem, StockLog, CourierRate,
    MonthlyShippingRate, ShipmentBatch, Delivery, Shipping,
    AppSettings, MobileOperation, MobileChange,
)
from app.services.sales import create_sale, update_sale_status, SaleValidationError
from app.services.shipment_batches import (
    create_batch, add_sale_to_batch, remove_sale_from_batch,
    mark_arrived, settle_sale_shipping, BatchValidationError,
)
from app.services.delivery import (
    get_ready_for_delivery_sales, find_phone_matches, find_name_matches,
    create_delivery, update_delivery_status, DeliveryValidationError,
)
from app.services.shipping import create_shipping, update_shipping, search_shipping, ShippingValidationError
from app.services.rates import get_rate_for_month
from app.services.settings import get_settings, update_settings
from app.services.dashboard import get_kpis, get_sales_last_30_days
from app.services.reports import sales_report, sales_csv_rows, shipping_csv_rows, inventory_csv_rows
from app.services.data_tools import clear_test_data, get_row_counts, CONFIRMATION_PHRASE
from app.services.labels import generate_label_pdf, label_ready

api_bp = Blueprint("api", __name__, url_prefix="/api")


def _json_decimal(value):
    return float(value) if value is not None else None


def _dt(value):
    return value.isoformat() if value else None


def _product_json(p):
    return {"id": p.id, "name": p.name, "sku": p.sku, "cost": _json_decimal(p.cost),
            "length_cm": _json_decimal(p.length_cm), "width_cm": _json_decimal(p.width_cm),
            "height_cm": _json_decimal(p.height_cm), "cbm": _json_decimal(p.cbm),
            "volumetric_kg": _json_decimal(p.volumetric_kg), "actual_weight_kg": _json_decimal(p.actual_weight_kg),
            "stock": p.stock, "estimated_shipping_cost": _json_decimal(p.estimated_shipping_cost), "created_at": _dt(p.created_at)}


def _sale_json(s):
    return {"id": s.id, "order_id": s.order_id, "client_operation_id": s.client_operation_id, "sale_date": s.sale_date.isoformat() if s.sale_date else None,
            "customer_name": s.customer_name, "customer_phone": s.customer_phone, "customer_address": s.customer_address,
            "customer_state": s.customer_state, "order_status": s.order_status, "payment_status": s.payment_status,
            "notes": s.notes, "subtotal_amount": _json_decimal(s.subtotal_amount),
            "estimated_shipping_cost": _json_decimal(s.estimated_shipping_cost), "actual_shipping_cost": _json_decimal(s.actual_shipping_cost),
            "shipping_payment_settled": bool(s.shipping_payment_settled), "shipping_payment_settled_at": _dt(s.shipping_payment_settled_at),
            "total_amount": _json_decimal(s.total_amount), "profit": _json_decimal(s.profit), "batch_id": s.batch_id, "delivery_id": s.delivery_id,
            "estimated_arrival_start": s.estimated_arrival_start.isoformat() if s.estimated_arrival_start else None,
            "estimated_arrival_end": s.estimated_arrival_end.isoformat() if s.estimated_arrival_end else None,
            "items": [{"id": i.id, "product_id": i.product_id, "product_name": i.product.name if i.product else None,
                       "qty": i.qty, "unit_cost": _json_decimal(i.unit_cost), "unit_price": _json_decimal(i.unit_price),
                       "variant_note": i.variant_note, "line_cbm": _json_decimal(i.line_cbm),
                       "line_volumetric_kg": _json_decimal(i.line_volumetric_kg),
                       "line_shipping_estimate": _json_decimal(i.line_shipping_estimate)} for i in s.items],
            "shipping": _shipping_json(s.shipping) if s.shipping else None}


def _shipping_json(x):
    return {"id": x.id, "sale_id": x.sale_id, "courier": x.courier, "tracking_number": x.tracking_number,
            "chargeable_weight_kg": _json_decimal(x.chargeable_weight_kg), "total_cbm": _json_decimal(x.total_cbm),
            "shipping_status": x.shipping_status, "shipped_at": _dt(x.shipped_at), "delivered_at": _dt(x.delivered_at), "notes": x.notes}


def _batch_json(b):
    return {"id": b.id, "name": b.name, "status": b.status, "departed_at": _dt(b.departed_at),
            "arrived_at": _dt(b.arrived_at), "payment_settled_at": _dt(b.payment_settled_at), "notes": b.notes,
            "created_at": _dt(b.created_at), "sale_ids": [s.id for s in b.sales], "sales": [_sale_json(s) for s in b.sales]}


def _delivery_json(d):
    return {"id": d.id, "method": d.method, "status": d.status, "is_consolidated": bool(d.is_consolidated),
            "consolidation_type": d.consolidation_type, "delivery_address": d.delivery_address, "notes": d.notes,
            "created_at": _dt(d.created_at), "shipped_at": _dt(d.shipped_at), "delivered_at": _dt(d.delivered_at),
            "package_weight_kg": _json_decimal(d.package_weight_kg), "package_dimensions": d.package_dimensions,
            "remarks": d.remarks, "sale_ids": [s.id for s in d.sales], "sales": [_sale_json(s) for s in d.sales]}


def _rate_json(r):
    return {"id": r.id, "state": r.state, "rate_per_cbm": _json_decimal(r.rate_per_cbm)}


def _monthly_json(r):
    return {"id": r.id, "month": r.month.isoformat() if r.month else None, "rate_per_cbm": _json_decimal(r.rate_per_cbm)}


def _settings_json(s):
    return {"id": s.id, "label_width_mm": s.label_width_mm, "label_height_mm": s.label_height_mm,
            "business_name": s.business_name, "business_phone": s.business_phone, "business_address": s.business_address,
            "has_logo": bool(s.logo_data), "logo_mimetype": s.logo_mimetype}


def _user_json(u):
    return {"id": u.id, "username": u.username, "created_at": _dt(u.created_at)}


def require_api_token(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return jsonify({"error": "Missing Authorization header."}), 401
        token = header[7:].strip()
        user = User.query.filter_by(api_token=token).first() if token else None
        if not user:
            return jsonify({"error": "Invalid API token."}), 401
        g.api_user = user
        return f(*args, **kwargs)
    return wrapper


def _admin_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        # The existing website has a single authenticated admin area. Preserve
        # that permission model for mobile rather than inventing a new role system.
        return f(*args, **kwargs)
    return wrapper


def _operation_response(operation_id):
    if not operation_id:
        return None
    row = MobileOperation.query.filter_by(operation_id=operation_id).first()
    if not row or row.status != "completed" or not row.response_json:
        return None
    return jsonify(row.response_json), row.response_code or 200


def _remember_operation(operation_id, operation_type, status_code, payload):
    if not operation_id:
        return
    row = MobileOperation.query.filter_by(operation_id=operation_id).first()
    if not row:
        row = MobileOperation(operation_id=operation_id, user_id=g.api_user.id, operation_type=operation_type,
                              status="completed", response_code=status_code, response_json=payload,
                              created_at=datetime.utcnow(), completed_at=datetime.utcnow())
        db.session.add(row)
    else:
        row.status = "completed"; row.response_code = status_code; row.response_json = payload; row.completed_at = datetime.utcnow()


def _write_json(payload, status=200, operation_type=None, operation_id=None):
    if operation_type and operation_id:
        _remember_operation(operation_id, operation_type, status, payload)
        db.session.commit()
    return jsonify(payload), status


@api_bp.route("/v1/auth/login", methods=("POST",))
def login():
    data = request.get_json(silent=True) or {}
    username, password = (data.get("username") or "").strip(), data.get("password") or ""
    user = User.query.filter_by(username=username).first()
    if not user or not check_password_hash(user.password_hash, password):
        return jsonify({"error": "Invalid username or password."}), 401
    if not user.api_token:
        user.api_token = secrets.token_urlsafe(48)[:64]
        db.session.commit()
    return jsonify({"token": user.api_token, "user": _user_json(user)})


@api_bp.route("/v1/auth/me", methods=("GET",))
@require_api_token
def auth_me():
    return jsonify({"user": _user_json(g.api_user)})


@api_bp.route("/v1/auth/logout", methods=("POST",))
@require_api_token
def auth_logout():
    return jsonify({"ok": True})


@api_bp.route("/v1/bootstrap", methods=("GET",))
@require_api_token
def bootstrap():
    return jsonify({"products": [_product_json(x) for x in Product.query.order_by(Product.name).all()],
                    "sales": [_sale_json(x) for x in Sale.query.order_by(Sale.id.desc()).limit(500).all()],
                    "batches": [_batch_json(x) for x in ShipmentBatch.query.order_by(ShipmentBatch.id.desc()).all()],
                    "deliveries": [_delivery_json(x) for x in Delivery.query.order_by(Delivery.id.desc()).all()],
                    "shipping": [_shipping_json(x) for x in Shipping.query.order_by(Shipping.id.desc()).limit(500).all()],
                    "courier_rates": [_rate_json(x) for x in CourierRate.query.order_by(CourierRate.state).all()],
                    "monthly_rates": [_monthly_json(x) for x in MonthlyShippingRate.query.order_by(MonthlyShippingRate.month.desc()).all()],
                    "settings": _settings_json(get_settings())})


@api_bp.route("/v1/sync", methods=("GET",))
@require_api_token
def sync():
    cursor = request.args.get("cursor", 0, type=int) or 0
    limit = min(max(request.args.get("limit", 250, type=int) or 250, 1), 1000)
    rows = MobileChange.query.filter(MobileChange.sequence > cursor).order_by(MobileChange.sequence).limit(limit + 1).all()
    has_more = len(rows) > limit
    rows = rows[:limit]
    return jsonify({"changes": [{"sequence": x.sequence, "entity_type": x.entity_type, "entity_id": x.entity_id,
                                  "operation": x.operation, "payload": x.payload, "created_at": _dt(x.created_at)} for x in rows],
                    "cursor": rows[-1].sequence if rows else cursor, "has_more": has_more})


@api_bp.route("/v1/products", methods=("GET", "POST"))
@require_api_token
def products():
    if request.method == "GET":
        return jsonify([_product_json(x) for x in Product.query.order_by(Product.name).all()])
    data = request.get_json(silent=True) or {}; op = data.get("operation_id")
    cached = _operation_response(op)
    if cached: return cached
    try:
        p = Product(name=(data.get("name") or "").strip(), sku=(data.get("sku") or None), cost=Decimal(str(data.get("cost", 0) or 0)),
                    length_cm=data.get("length_cm"), width_cm=data.get("width_cm"), height_cm=data.get("height_cm"), actual_weight_kg=data.get("actual_weight_kg"), stock=int(data.get("stock", 0) or 0))
        if not p.name: raise ValueError("Product name is required.")
        db.session.add(p); db.session.flush(); payload = _product_json(p); return _write_json(payload, 201, "create_product", op)
    except Exception as e:
        db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/products/<int:product_id>", methods=("GET", "PATCH", "DELETE"))
@require_api_token
def product_detail(product_id):
    p = Product.query.get_or_404(product_id)
    if request.method == "GET": return jsonify(_product_json(p))
    if request.method == "DELETE":
        try: db.session.delete(p); db.session.commit(); return jsonify({"ok": True, "id": product_id})
        except Exception as e: db.session.rollback(); return jsonify({"error": str(e)}), 400
    data = request.get_json(silent=True) or {}
    for key in ("name", "sku", "length_cm", "width_cm", "height_cm", "actual_weight_kg", "cost"):
        if key in data: setattr(p, key, data[key])
    db.session.commit(); return jsonify(_product_json(p))


@api_bp.route("/v1/stock/adjust", methods=("POST",))
@require_api_token
def stock_adjust():
    data = request.get_json(silent=True) or {}; op = data.get("operation_id"); cached = _operation_response(op)
    if cached: return cached
    try:
        p = Product.query.get(int(data["product_id"])); change = int(data["change_qty"])
        if not p: raise ValueError("Product not found.")
        if change == 0 or p.stock + change < 0: raise ValueError("Invalid stock adjustment.")
        p.stock += change; db.session.add(StockLog(product_id=p.id, change_qty=change, reason=(data.get("reason") or "Mobile adjustment").strip()))
        db.session.flush(); payload = _product_json(p); return _write_json(payload, 200, "stock_adjust", op)
    except Exception as e: db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/sales", methods=("GET", "POST"))
@require_api_token
def sales():
    if request.method == "GET":
        limit = min(request.args.get("limit", 500, type=int) or 500, 1000)
        return jsonify([_sale_json(x) for x in Sale.query.order_by(Sale.id.desc()).limit(limit).all()])
    data = request.get_json(silent=True) or {}; op = data.get("operation_id"); cached = _operation_response(op)
    if cached: return cached
    if op:
        existing = Sale.query.filter_by(client_operation_id=op).first()
        if existing:
            return jsonify(_sale_json(existing)), 200
    try:
        items = []
        for line in data.get("items") or []:
            items.append({"product_id": int(line["product_id"]), "qty": int(line["qty"]), "unit_price": Decimal(str(line["unit_price"])), "variant_note": line.get("variant_note")})
        sale = create_sale((data.get("customer_name") or "").strip(), (data.get("customer_phone") or "").strip(),
                           (data.get("customer_address") or "").strip(), (data.get("customer_state") or "").strip(),
                           data.get("payment_status") or "Paid", (data.get("notes") or "").strip(), items)
        if op: sale.client_operation_id = op
        db.session.flush(); payload = _sale_json(sale); return _write_json(payload, 201, "create_sale", op)
    except (SaleValidationError, KeyError, ValueError, InvalidOperation) as e: db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/sales/<int:sale_id>", methods=("GET",))
@require_api_token
def sale_detail(sale_id): return jsonify(_sale_json(Sale.query.get_or_404(sale_id)))


@api_bp.route("/v1/sales/<int:sale_id>/status", methods=("POST",))
@require_api_token
def sale_status(sale_id):
    data = request.get_json(silent=True) or {}; op = data.get("operation_id"); cached = _operation_response(op)
    if cached: return cached
    try:
        s = update_sale_status(sale_id, data.get("status") or ""); payload = _sale_json(s); return _write_json(payload, 200, "sale_status", op)
    except SaleValidationError as e: db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/sales/<int:sale_id>/settle-shipping", methods=("POST",))
@require_api_token
def settle_shipping(sale_id):
    data = request.get_json(silent=True) or {}; op = data.get("operation_id"); cached = _operation_response(op)
    if cached: return cached
    try:
        s = settle_sale_shipping(sale_id); return _write_json(_sale_json(s), 200, "settle_shipping", op)
    except BatchValidationError as e: db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/batches", methods=("GET", "POST"))
@require_api_token
def batches():
    if request.method == "GET": return jsonify([_batch_json(x) for x in ShipmentBatch.query.order_by(ShipmentBatch.id.desc()).all()])
    data = request.get_json(silent=True) or {}; op = data.get("operation_id"); cached = _operation_response(op)
    if cached: return cached
    try: b = create_batch(data.get("name"), data.get("notes")); return _write_json(_batch_json(b), 201, "create_batch", op)
    except BatchValidationError as e: db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/batches/<int:batch_id>", methods=("GET",))
@require_api_token
def batch_detail(batch_id): return jsonify(_batch_json(ShipmentBatch.query.get_or_404(batch_id)))


@api_bp.route("/v1/batches/<int:batch_id>/sales/<int:sale_id>", methods=("POST", "DELETE"))
@require_api_token
def batch_sale(batch_id, sale_id):
    data = request.get_json(silent=True) or {}
    op = data.get("operation_id") or request.headers.get("X-Operation-ID")
    cached = _operation_response(op)
    if cached:
        return cached
    try:
        if request.method == "DELETE":
            remove_sale_from_batch(sale_id)
            payload = _batch_json(ShipmentBatch.query.get_or_404(batch_id))
        else:
            payload = _batch_json(add_sale_to_batch(batch_id, sale_id))
        return _write_json(payload, 200, "batch_remove_sale" if request.method == "DELETE" else "batch_add_sale", op)
    except BatchValidationError as e:
        db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/batches/<int:batch_id>/arrive", methods=("POST",))
@require_api_token
def batch_arrive(batch_id):
    data = request.get_json(silent=True) or {}; op = data.get("operation_id"); cached = _operation_response(op)
    if cached: return cached
    try: b = mark_arrived(batch_id); return _write_json(_batch_json(b), 200, "batch_arrive", op)
    except BatchValidationError as e: db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/deliveries", methods=("GET", "POST"))
@require_api_token
def deliveries():
    if request.method == "GET": return jsonify([_delivery_json(x) for x in Delivery.query.order_by(Delivery.id.desc()).all()])
    data = request.get_json(silent=True) or {}; op = data.get("operation_id"); cached = _operation_response(op)
    if cached: return cached
    try:
        d = create_delivery([int(x) for x in data.get("sale_ids") or []], data.get("method"), data.get("consolidation_type"), data.get("delivery_address"), data.get("notes"))
        return _write_json(_delivery_json(d), 201, "create_delivery", op)
    except DeliveryValidationError as e: db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/deliveries/ready", methods=("GET",))
@require_api_token
def ready_deliveries():
    return jsonify({"sales": [_sale_json(x) for x in get_ready_for_delivery_sales()],
                    "phone_matches": {k: [_sale_json(x) for x in v] for k,v in find_phone_matches().items()},
                    "name_matches": {k: [_sale_json(x) for x in v] for k,v in find_name_matches().items()}})


@api_bp.route("/v1/deliveries/<int:delivery_id>", methods=("GET",))
@require_api_token
def delivery_detail(delivery_id): return jsonify(_delivery_json(Delivery.query.get_or_404(delivery_id)))


@api_bp.route("/v1/deliveries/<int:delivery_id>/status", methods=("POST",))
@require_api_token
def delivery_status(delivery_id):
    data = request.get_json(silent=True) or {}; op = data.get("operation_id"); cached = _operation_response(op)
    if cached: return cached
    try: d = update_delivery_status(delivery_id, data.get("status") or ""); return _write_json(_delivery_json(d), 200, "delivery_status", op)
    except DeliveryValidationError as e: db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/deliveries/<int:delivery_id>/label-data", methods=("POST",))
@require_api_token
def delivery_label_data(delivery_id):
    d = Delivery.query.get_or_404(delivery_id); data = request.get_json(silent=True) or {}
    op = data.get("operation_id") or request.headers.get("X-Operation-ID")
    cached = _operation_response(op)
    if cached:
        return cached
    try:
        weight = Decimal(str(data.get("package_weight_kg"))); dimensions = (data.get("package_dimensions") or "").strip()
        if weight <= 0 or not dimensions: raise ValueError("Valid weight and dimensions are required.")
        d.package_weight_kg = weight; d.package_dimensions = dimensions; d.remarks = (data.get("remarks") or "").strip() or None
        db.session.flush()
        return _write_json(_delivery_json(d), 200, "delivery_label_data", op)
    except Exception as e: db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/deliveries/<int:delivery_id>/label.pdf", methods=("GET",))
@require_api_token
def delivery_label_pdf(delivery_id):
    d = Delivery.query.get_or_404(delivery_id)
    if not label_ready(d): return jsonify({"error": "Enter package weight and dimensions first."}), 400
    return send_file(generate_label_pdf(d), mimetype="application/pdf", as_attachment=False, download_name=f"label-{delivery_id}.pdf")


@api_bp.route("/v1/shipping", methods=("GET", "POST"))
@require_api_token
def shipping():
    if request.method == "GET":
        rows = Shipping.query.order_by(Shipping.id.desc()).all(); return jsonify([_shipping_json(x) for x in rows])
    data = request.get_json(silent=True) or {}; op = data.get("operation_id"); cached = _operation_response(op)
    try:
        x = create_shipping(int(data["sale_id"]), (data.get("courier") or "").strip(), (data.get("tracking_number") or "").strip(), data.get("notes")); return _write_json(_shipping_json(x), 201, "create_shipping", op)
    except (ShippingValidationError, KeyError, ValueError) as e: db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/shipping/<int:shipping_id>", methods=("GET", "POST"))
@require_api_token
def shipping_detail_api(shipping_id):
    x = Shipping.query.get_or_404(shipping_id)
    if request.method == "GET": return jsonify(_shipping_json(x))
    data = request.get_json(silent=True) or {}; op = data.get("operation_id"); cached = _operation_response(op)
    try: x = update_shipping(shipping_id, data.get("courier"), data.get("tracking_number"), data.get("shipping_status"), data.get("notes")); return _write_json(_shipping_json(x), 200, "update_shipping", op)
    except ShippingValidationError as e: db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/shipping/search", methods=("GET",))
@require_api_token
def shipping_search():
    rows = search_shipping(request.args.get("tracking_number"), request.args.get("state")); return jsonify([_shipping_json(x) for x in rows])


@api_bp.route("/v1/rates/courier", methods=("GET", "POST"))
@require_api_token
def courier_rates():
    if request.method == "GET": return jsonify([_rate_json(x) for x in CourierRate.query.order_by(CourierRate.state).all()])
    data=request.get_json(silent=True) or {}; r=CourierRate(state=data.get("state"), rate_per_cbm=data.get("rate_per_cbm")); db.session.add(r); db.session.commit(); return jsonify(_rate_json(r)),201


@api_bp.route("/v1/rates/courier/<int:rate_id>", methods=("PATCH", "DELETE"))
@require_api_token
def courier_rate_detail(rate_id):
    r=CourierRate.query.get_or_404(rate_id)
    if request.method=="DELETE": db.session.delete(r); db.session.commit(); return jsonify({"ok":True})
    data=request.get_json(silent=True) or {}; r.state=data.get("state",r.state); r.rate_per_cbm=data.get("rate_per_cbm",r.rate_per_cbm); db.session.commit(); return jsonify(_rate_json(r))


@api_bp.route("/v1/rates/monthly", methods=("GET", "POST"))
@require_api_token
def monthly_rates():
    if request.method=="GET": return jsonify([_monthly_json(x) for x in MonthlyShippingRate.query.order_by(MonthlyShippingRate.month.desc()).all()])
    data=request.get_json(silent=True) or {}; month=date.fromisoformat(str(data["month"])[:10]).replace(day=1); r=MonthlyShippingRate(month=month, rate_per_cbm=data["rate_per_cbm"]); db.session.add(r); db.session.commit(); return jsonify(_monthly_json(r)),201


@api_bp.route("/v1/rates/monthly/<int:rate_id>", methods=("PATCH", "DELETE"))
@require_api_token
def monthly_rate_detail(rate_id):
    r=MonthlyShippingRate.query.get_or_404(rate_id)
    if request.method=="DELETE": db.session.delete(r); db.session.commit(); return jsonify({"ok":True})
    data=request.get_json(silent=True) or {}; r.month=date.fromisoformat(str(data.get("month",r.month))[:10]).replace(day=1) if data.get("month") else r.month; r.rate_per_cbm=data.get("rate_per_cbm",r.rate_per_cbm); db.session.commit(); return jsonify(_monthly_json(r))


@api_bp.route("/v1/dashboard", methods=("GET",))
@require_api_token
def dashboard():
    k=get_kpis(); labels, values=get_sales_last_30_days(); return jsonify({"sales_today":float(k["sales_today"]),"profit_today":float(k["profit_today"]),"pending_shipments":k["pending_shipments"],"low_stock_count":k["low_stock_count"],"low_stock_products":[_product_json(x) for x in k["low_stock_products"]],"last_30_days":{"labels":labels,"values":values}})


@api_bp.route("/v1/reports/sales", methods=("GET",))
@require_api_token
def sales_report_api():
    def parse(v): return date.fromisoformat(v) if v else None
    d=sales_report(parse(request.args.get("start_date")),parse(request.args.get("end_date")))
    return jsonify({"start_date":d["start_date"].isoformat(),"end_date":d["end_date"].isoformat(),"totals":{k:float(v or 0) for k,v in d["totals"].items()},"sales":[_sale_json(x) for x in d["sales"]]})


@api_bp.route("/v1/reports/shipping", methods=("GET",))
@require_api_token
def shipping_report_api():
    return jsonify([list(x) for x in shipping_csv_rows()])


@api_bp.route("/v1/reports/inventory", methods=("GET",))
@require_api_token
def inventory_report_api():
    return jsonify([list(x) for x in inventory_csv_rows()])


@api_bp.route("/v1/reports/sales.csv", methods=("GET",))
@require_api_token
def sales_csv_api():
    import csv, io
    def parse(v): return date.fromisoformat(v) if v else None
    buf = io.StringIO(); w = csv.writer(buf)
    from app.services.reports import SALES_CSV_HEADERS
    w.writerow(SALES_CSV_HEADERS)
    for row in sales_csv_rows(parse(request.args.get("start_date")), parse(request.args.get("end_date"))): w.writerow(row)
    return Response(buf.getvalue(), mimetype="text/csv", headers={"Content-Disposition": "attachment; filename=sales_report.csv"})


@api_bp.route("/v1/reports/shipping.csv", methods=("GET",))
@require_api_token
def shipping_csv_api():
    import csv, io
    from app.services.reports import SHIPPING_CSV_HEADERS
    buf = io.StringIO(); w = csv.writer(buf); w.writerow(SHIPPING_CSV_HEADERS)
    for row in shipping_csv_rows(): w.writerow(row)
    return Response(buf.getvalue(), mimetype="text/csv", headers={"Content-Disposition": "attachment; filename=shipping_report.csv"})


@api_bp.route("/v1/reports/inventory.csv", methods=("GET",))
@require_api_token
def inventory_csv_api():
    import csv, io
    from app.services.reports import INVENTORY_CSV_HEADERS
    buf = io.StringIO(); w = csv.writer(buf); w.writerow(INVENTORY_CSV_HEADERS)
    for row in inventory_csv_rows(): w.writerow(row)
    return Response(buf.getvalue(), mimetype="text/csv", headers={"Content-Disposition": "attachment; filename=inventory_report.csv"})


@api_bp.route("/v1/settings", methods=("GET", "PATCH"))
@require_api_token
def settings_api():
    if request.method == "GET":
        return jsonify(_settings_json(get_settings()))
    data = request.get_json(silent=True) or {}
    op = data.get("operation_id") or request.headers.get("X-Operation-ID")
    cached = _operation_response(op)
    if cached:
        return cached
    import base64
    logo_data = None
    logo_mimetype = data.get("logo_mimetype")
    if data.get("logo_base64"):
        try:
            logo_data = base64.b64decode(data["logo_base64"], validate=True)
            if not logo_data or len(logo_data) > 5 * 1024 * 1024:
                raise ValueError("Logo must be smaller than 5 MB.")
        except Exception as e:
            return jsonify({"error": f"Invalid logo: {e}"}), 400
    s = update_settings(label_width_mm=data.get("label_width_mm"), label_height_mm=data.get("label_height_mm"),
                         business_name=data.get("business_name"), business_phone=data.get("business_phone"),
                         business_address=data.get("business_address"), logo_data=logo_data, logo_mimetype=logo_mimetype)
    return _write_json(_settings_json(s), 200, "update_settings", op)


@api_bp.route("/v1/auth/change-password", methods=("POST",))
@require_api_token
def auth_change_password():
    data = request.get_json(silent=True) or {}
    current = data.get("current_password") or ""
    new = data.get("new_password") or ""
    if not check_password_hash(g.api_user.password_hash, current):
        return jsonify({"error": "Current password is incorrect."}), 400
    if len(new) < 8:
        return jsonify({"error": "New password must be at least 8 characters."}), 400
    g.api_user.password_hash = generate_password_hash(new)
    # Rotate the mobile token so a stolen old token stops working.
    g.api_user.api_token = secrets.token_urlsafe(48)[:64]
    db.session.commit()
    return jsonify({"ok": True, "token": g.api_user.api_token})


@api_bp.route("/v1/settings/logo", methods=("GET",))
@require_api_token
def settings_logo():
    s = get_settings()
    if not s.logo_data:
        return jsonify({"error": "No logo has been uploaded."}), 404
    return Response(s.logo_data, mimetype=s.logo_mimetype or "image/png")


@api_bp.route("/v1/users", methods=("GET", "POST"))
@require_api_token
def users():
    if request.method=="GET": return jsonify([_user_json(x) for x in User.query.order_by(User.id).all()])
    from werkzeug.security import generate_password_hash
    data=request.get_json(silent=True) or {}; username=(data.get("username") or "").strip(); password=data.get("password") or ""
    if not username or len(password)<6: return jsonify({"error":"Username and password (minimum 6 characters) are required."}),400
    if User.query.filter_by(username=username).first(): return jsonify({"error":"Username already exists."}),400
    u=User(username=username,password_hash=generate_password_hash(password)); db.session.add(u); db.session.commit(); return jsonify(_user_json(u)),201


@api_bp.route("/v1/users/<int:user_id>", methods=("DELETE",))
@require_api_token
def user_delete(user_id):
    u=User.query.get_or_404(user_id)
    if u.id == User.query.order_by(User.id).first().id: return jsonify({"error":"The original admin cannot be removed."}),400
    if u.id == g.api_user.id: return jsonify({"error":"You cannot remove your own account."}),400
    db.session.delete(u); db.session.commit(); return jsonify({"ok":True})


@api_bp.route("/v1/clear-test-data", methods=("GET", "POST"))
@require_api_token
def clear_data():
    if request.method=="GET": return jsonify({"confirmation":CONFIRMATION_PHRASE,"counts":dict(get_row_counts())})
    data=request.get_json(silent=True) or {}
    try: return jsonify({"deleted":clear_test_data(data.get("confirmation"))})
    except Exception as e: db.session.rollback(); return jsonify({"error":str(e)}),400


# Track website-originated ORM changes so an already-installed mobile client
# can pull changes made from the web. This is deliberately in the API module
# so it is installed whenever the API blueprint is registered by app/__init__.py.
_TRACKED = {Product:"product", Sale:"sale", SaleItem:"sale_item", StockLog:"stock_log", Shipping:"shipping",
            ShipmentBatch:"shipment_batch", Delivery:"delivery", CourierRate:"courier_rate", MonthlyShippingRate:"monthly_rate"}


def _change_payload(obj):
    if isinstance(obj, Product): return _product_json(obj)
    if isinstance(obj, Sale): return _sale_json(obj)
    if isinstance(obj, Shipping): return _shipping_json(obj)
    if isinstance(obj, ShipmentBatch): return _batch_json(obj)
    if isinstance(obj, Delivery): return _delivery_json(obj)
    if isinstance(obj, CourierRate): return _rate_json(obj)
    if isinstance(obj, MonthlyShippingRate): return _monthly_json(obj)
    if isinstance(obj, SaleItem): return {"id":obj.id,"sale_id":obj.sale_id,"product_id":obj.product_id,"qty":obj.qty,"unit_price":_json_decimal(obj.unit_price),"variant_note":obj.variant_note}
    if isinstance(obj, StockLog): return {"id":obj.id,"product_id":obj.product_id,"change_qty":obj.change_qty,"reason":obj.reason,"created_at":_dt(obj.created_at)}
    return None


@event.listens_for(Session, "after_flush")
def _capture_mobile_changes(session, flush_context):
    # Avoid recursively tracking the tracking rows themselves.
    seen = set()
    for collection, operation in ((session.new, "upsert"), (session.dirty, "upsert"), (session.deleted, "delete")):
        for obj in collection:
            entity = _TRACKED.get(type(obj))
            if not entity: continue
            ident = getattr(obj, "id", None)
            if ident is None: continue
            key=(entity, str(ident), operation)
            if key in seen: continue
            seen.add(key)
            payload = None if operation == "delete" else _change_payload(obj)
            session.add(MobileChange(entity_type=entity, entity_id=str(ident), operation=operation, payload=payload, created_at=datetime.utcnow()))
