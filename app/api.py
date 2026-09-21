"""
JSON API — for the offline-capable mobile app.

Token-authenticated (not session/cookie-based, since the phone app isn't a
browser). The phone caches /api/products for offline reference, queues new
sales locally while offline, then POSTs each one to /api/sales once it has
connectivity. Sale creation reuses the exact same app.services.sales.create_sale
used by the web form, so validation/stock rules/estimate calc never drift
between the two.
"""
from functools import wraps
from decimal import Decimal, InvalidOperation

from flask import Blueprint, request, jsonify, g

from app.models import User, Product, Sale, SaleItem
from app.services.sales import create_sale, SaleValidationError

api_bp = Blueprint("api", __name__, url_prefix="/api")


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


def _product_json(p):
    return {
        "id": p.id,
        "name": p.name,
        "sku": p.sku,
        "length_cm": float(p.length_cm) if p.length_cm is not None else None,
        "width_cm": float(p.width_cm) if p.width_cm is not None else None,
        "height_cm": float(p.height_cm) if p.height_cm is not None else None,
        "cbm": float(p.cbm) if p.cbm is not None else None,
        "volumetric_kg": float(p.volumetric_kg) if p.volumetric_kg is not None else None,
        "actual_weight_kg": float(p.actual_weight_kg) if p.actual_weight_kg is not None else None,
        "stock": p.stock,
    }


def _sale_json(s):
    return {
        "id": s.id,
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
        "shipping_payment_settled": s.shipping_payment_settled,
        "total_amount": float(s.total_amount) if s.total_amount is not None else None,
        "items": [
            {
                "product_id": item.product_id,
                "product_name": item.product.name if item.product else None,
                "qty": item.qty,
                "unit_price": float(item.unit_price) if item.unit_price is not None else None,
                "variant_note": item.variant_note,
            }
            for item in s.items
        ],
    }


@api_bp.route("/products", methods=("GET",))
@require_api_token
def list_products():
    products = Product.query.order_by(Product.name).all()
    return jsonify([_product_json(p) for p in products])


@api_bp.route("/sales", methods=("GET",))
@require_api_token
def list_sales():
    limit = request.args.get("limit", default=100, type=int)
    sales = Sale.query.order_by(Sale.id.desc()).limit(min(limit, 500)).all()
    return jsonify([_sale_json(s) for s in sales])


@api_bp.route("/sales", methods=("POST",))
@require_api_token
def create_sale_api():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "Request body must be JSON."}), 400

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
        sale = create_sale(
            customer_name=(data.get("customer_name") or "").strip(),
            customer_phone=(data.get("customer_phone") or "").strip(),
            customer_address=(data.get("customer_address") or "").strip(),
            customer_state=(data.get("customer_state") or "").strip(),
            payment_status=data.get("payment_status") or "Paid",
            notes=(data.get("notes") or "").strip(),
            line_items=line_items,
        )
        return jsonify(_sale_json(sale)), 201
    except SaleValidationError as e:
        return jsonify({"error": str(e)}), 400
