        p = Product(name=name, sku=(str(data.get("sku") or "").strip() or None),
                    cost=Decimal(str(data.get("cost") or data.get("landed_cost") or "0")),
                    supplier_cost=Decimal(str(data.get("supplier_cost") or data.get("cost") or "0")),
                    inbound_shipping_cost=Decimal(str(data.get("inbound_shipping_cost") or "0")),
                    markup_percent=Decimal(str(data.get("markup_percent") or "0")),
                    selling_price=Decimal(str(data.get("selling_price") or "0")),
                    length_cm=data.get("length_cm"), width_cm=data.get("width_cm"),
                    height_cm=data.get("height_cm"), actual_weight_kg=data.get("actual_weight_kg"),
                    stock=int(data.get("stock") or 0))
        if p.stock < 0: raise ValueError("Stock cannot be negative.")
        db.session.add(p); db.session.flush()
        record_audit("product.create", target_type="product", target_id=p.id,
                     details={"name": p.name, "source": "api"}, user=g.api_user)
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
        numeric_fields = {
            "cost", "supplier_cost", "inbound_shipping_cost",
            "markup_percent", "selling_price",
            "length_cm", "width_cm", "height_cm", "actual_weight_kg",
        }
        for f in ("name", "sku", *numeric_fields):
            if f not in data:
                continue
            value = data[f]
            if f == "sku":
                value = str(value or "").strip() or None
            elif f in numeric_fields:
                # Flutter forms can legitimately send an empty string for an
                # optional numeric field (for example selling price while a
                # product photo is being changed). Never send "" to PostgreSQL
                # NUMERIC columns.
                if value is None or (isinstance(value, str) and not value.strip()):
                    value = Decimal("0")
                else:
                    value = Decimal(str(value))
            setattr(p, f, value)
        record_audit("product.update", target_type="product", target_id=p.id,
                     details={"source": "api"}, user=g.api_user)
        return _mobile_finish(op, "update_product", 200, _product_json(p))
    except (ValueError, TypeError, InvalidOperation) as e:
        db.session.rollback(); return jsonify({"error": str(e)}), 400


@api_bp.route("/v1/products/<int:product_id>", methods=("DELETE",))
@require_api_token
def mobile_delete_product(product_id):