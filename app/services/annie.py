"""Annie, the role-aware, zero-provider-cost Oma team-chat assistant.

Android clients generate responses with a local on-device model; the web client
retains deterministic database-backed answers. This service supplies bounded,
permission-filtered business context and durable chat notifications. Annie has
no write tools and cannot change sales, payments, stock, users, or shipments.
"""
import logging
import re
import secrets
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from zoneinfo import ZoneInfo

from sqlalchemy import desc

from app import db
from app.models import AnnieReplyTask, ChatMessage, Delivery, Product, PushDevice, Sale, ShipmentBatch, User

log = logging.getLogger(__name__)
_ANNIE_MENTION = re.compile(r"(?<![A-Za-z0-9_])@annie\b", re.IGNORECASE)
_PRIVATE_ACTIONS = {"user.update", "username.change", "password.change"}
DEMURRAGE_POLICY_GUIDANCE = (
    "After a batch arrives, customers have 5 days to settle shipping; "
    "demurrage starts on day 6 at ₦150 per piece per day."
)


def is_annie_mention(content):
    return bool(_ANNIE_MENTION.search(content or ""))


def is_trusted_annie_scheduler_claims(claims):
    """Allow only the dedicated main-branch reminder workflow to run the scheduler."""
    return bool(
        isinstance(claims, dict)
        and claims.get("repository") == "guylikesweet/Oma-db"
        and claims.get("ref") == "refs/heads/main"
        and claims.get("workflow_ref")
        == "guylikesweet/Oma-db/.github/workflows/annie-scheduler.yml@refs/heads/main"
        and claims.get("event_name") in {"schedule", "workflow_dispatch"}
    )


def _money(value):
    try:
        return f"₦{Decimal(str(value or 0)):,.2f}"
    except Exception:
        return "₦0.00"


def _active_staff_ids():
    return [
        row[0] for row in User.query.filter(
            User.is_active.is_(True), User.is_system.is_(False)
        ).with_entities(User.id).all()
    ]


def post_annie_message(
    content, *, event_key=None, recipient_user_ids=None,
    exclude_user_id=None, push_type="chat_message", push_data=None,
):
    """Create one durable Annie chat message and matching push outbox rows."""
    bot = User.query.filter_by(is_system=True).first()
    if bot is None:
        raise RuntimeError("Annie's system account has not been installed by the database migration.")

    event_key = (event_key or ("annie-" + secrets.token_hex(20)))[:100]
    existing = ChatMessage.query.filter_by(client_operation_id=event_key).first()
    if existing is not None:
        return existing, False

    message = ChatMessage(
        sender_user_id=bot.id,
        content=str(content or "").strip()[:4000],
        client_operation_id=event_key,
    )
    db.session.add(message)
    db.session.flush()

    if recipient_user_ids is None:
        recipients = [
            user_id for user_id in _active_staff_ids()
            if user_id != exclude_user_id
        ]
    else:
        recipients = list(dict.fromkeys(
            int(user_id) for user_id in recipient_user_ids
            if user_id is not None and int(user_id) != bot.id
        ))

    from app.services.push_notifications import queue_user_notification
    preview = " ".join(message.content.split())
    if len(preview) > 180:
        preview = preview[:177].rstrip() + "..."
    for user_id in recipients:
        if not PushDevice.query.filter_by(user_id=user_id, enabled=True).first():
            continue
        payload = {
            "type": push_type,
            "chat_message_id": str(message.id),
            "sender_user_id": str(bot.id),
            "sender_username": "Annie",
            "message_content": preview,
            "sound": "chat_message",
        }
        payload.update(push_data or {})
        queue_user_notification(
            user_id, event_type=push_type, title="Annie",
            body=preview, data=payload,
        )
    return message, True


def build_audit_update(action, target_type=None, target_id=None, details=None):
    """Return a safe, human-readable chat update for a business audit event."""
    details = details or {}
    if action in _PRIVATE_ACTIONS or action.startswith("login") or action.startswith("password"):
        return None
    titles = {
        "sale.create": "New sale recorded",
        "sale.status": "Sale status updated",
        "sale.payment_status": "Sale payment status updated",
        "sale.payment.verified": "Customer payment verified",
        "sale.delete": "Sale removed",
        "product.create": "New product added",
        "product.update": "Product updated",
        "product.delete": "Product removed",
        "stock.adjust": "Stock adjusted",
        "batch.create": "Shipment batch created",
        "batch.add_sale": "Order added to shipment batch",
        "batch.remove_sale": "Order removed from shipment batch",
        "batch.delete": "Shipment batch removed",
        "batch.arrive": "Shipment batch arrived",
        "batch.undo_arrival": "Shipment arrival reversed",
        "shipping.settle": "Shipping payment confirmed",
        "shipping.create": "Shipment record created",
        "shipping.update": "Shipment record updated",
        "delivery.create": "Delivery created",
        "delivery.status": "Delivery status updated",
        "delivery.label_update": "Delivery package updated",
        "journey.update": "Order journey updated",
        "settings.update": "Business settings updated",
        "user.create": "New team member added",
        "user.delete": "Team member removed",
        "rate.courier.create": "Courier rate added",
        "rate.courier.update": "Courier rate updated",
        "rate.courier.delete": "Courier rate removed",
        "rate.air.create": "Air shipping rate added",
        "rate.air.update": "Air shipping rate updated",
        "rate.air.delete": "Air shipping rate removed",
        "rate.sea.create": "Sea shipping rate added",
        "rate.sea.update": "Sea shipping rate updated",
        "rate.sea.delete": "Sea shipping rate removed",
    }
    title = titles.get(action)
    if not title:
        return None

    body = title + "."
    try:
        entity_id = int(target_id) if target_id is not None else None
    except (TypeError, ValueError):
        entity_id = None

    if action == "batch.create":
        body = (
            f"Shipment batch {details.get('name') or ('#' + str(target_id))} "
            f"was created for {str(details.get('transport_mode') or 'sea').upper()} shipment."
        )
    elif action in {"batch.add_sale", "batch.remove_sale"}:
        batch = db.session.get(ShipmentBatch, int(details.get("batch_id") or 0))
        batch_name = batch.name if batch else f"batch #{details.get('batch_id') or 'unknown'}"
        body = f"Order #{target_id} was {'added to' if action.endswith('add_sale') else 'removed from'} {batch_name}."
    elif action == "batch.arrive":
        batch = db.session.get(ShipmentBatch, entity_id) if entity_id else None
        sales = [
            sale for sale in (batch.sales if batch else [])
            if not sale.is_stock_sale and sale.order_status != "Cancelled"
        ]
        pieces = sum(int(item.qty or 0) for sale in sales for item in sale.items)
        outstanding = sum((
            max(
                Decimal("0"),
                Decimal(str(sale.subtotal_amount or 0))
                - sum((Decimal(str(payment.amount or 0)) for payment in sale.payments), Decimal("0")),
            )
            for sale in sales
        ), Decimal("0"))
        name = (batch.name if batch else details.get("name")) or f"Batch #{target_id}"
        mode = str(details.get("transport_mode") or (batch.transport_mode if batch else "sea")).upper()
        body = (
            f"{name} has arrived ({mode}). {len(sales)} orders, {pieces} pieces. "
            f"Outstanding product balance: {_money(outstanding)}. "
            f"Daily demurrage at the current piece count: {_money(pieces * 150)}. "
            "Customers have 5 days after arrival to settle shipping; demurrage starts on day 6."
        )
    elif action == "sale.payment.verified":
        order = details.get("order_id") or f"sale #{target_id}"
        body = f"{_money(details.get('amount'))} received for {order}. Remaining product balance: {_money(details.get('outstanding'))}."
    elif action == "stock.adjust":
        product = db.session.get(Product, entity_id) if entity_id else None
        name = product.name if product else f"product #{target_id}"
        change = int(details.get("change_qty") or 0)
        stock = f" Current stock: {product.stock}." if product else ""
        body = f"{name}: stock {'increased' if change >= 0 else 'reduced'} by {abs(change)} pieces.{stock}"
    elif action == "delivery.status":
        body = (
            f"Delivery #{target_id} changed from {details.get('from') or 'previous status'} "
            f"to {details.get('to') or 'a new status'}."
        )
    elif action == "user.create":
        body = f"{details.get('username') or 'A new team member'} joined as {str(details.get('role') or 'staff').title()}."
    elif action == "user.delete":
        body = f"{details.get('username') or 'A team member'} was removed from Oma."
    elif action == "sale.create":
        sale = db.session.get(Sale, entity_id) if entity_id else None
        if sale:
            body = f"Order {sale.order_id or ('#' + str(sale.id))} was recorded for {sale.customer_name or 'a customer'}."
        else:
            body = f"Sale #{target_id} was recorded."
    elif action == "shipping.settle":
        body = f"Shipping payment of {_money(details.get('shipping_amount'))} was confirmed for sale #{target_id}."
    elif action == "journey.update":
        body = f"Order journey updated to {details.get('stage') or 'a new stage'}."
    elif action == "settings.update":
        body = "Business settings were updated by an administrator."

    return {"title": title, "body": body}


def build_business_context(user, question):
    """Build a bounded, permission-aware, read-only snapshot for Annie."""
    # Oma operates in Nigeria. Sales are stored as naive UTC timestamps, so
    # calculate calendar periods at Africa/Lagos midnight and convert their
    # boundaries back to naive UTC before querying the database.
    utc_now = datetime.now(timezone.utc)
    lagos_now = utc_now.astimezone(ZoneInfo("Africa/Lagos"))
    now = utc_now.replace(tzinfo=None)
    local_day_start = lagos_now.replace(hour=0, minute=0, second=0, microsecond=0)
    day_start = local_day_start.astimezone(timezone.utc).replace(tzinfo=None)
    week_start = now - timedelta(days=7)

    def local_boundary(value):
        return value.astimezone(timezone.utc).replace(tzinfo=None)

    def summarize_sales(rows):
        product_value = sum((Decimal(str(s.subtotal_amount or 0)) for s in rows), Decimal("0"))
        paid = sum((
            sum((Decimal(str(p.amount or 0)) for p in s.payments), Decimal("0"))
            for s in rows
        ), Decimal("0"))
        return {
            "orders": len(rows),
            "product_value_ngn": float(product_value),
            "verified_product_payments_ngn": float(paid),
            "product_balance_ngn": float(max(Decimal("0"), product_value - paid)),
        }

    yesterday_start = day_start - timedelta(days=1)
    local_week_start = local_day_start - timedelta(days=local_day_start.weekday())
    this_week_start = local_boundary(local_week_start)
    last_week_start = local_boundary(local_week_start - timedelta(days=7))
    local_month_start = local_day_start.replace(day=1)
    local_next_month_start = (local_month_start.replace(day=28) + timedelta(days=4)).replace(day=1)
    local_last_month_start = (local_month_start - timedelta(days=1)).replace(day=1)
    month_start = local_boundary(local_month_start)
    next_month_start = local_boundary(local_next_month_start)
    last_month_start = local_boundary(local_last_month_start)
    next_week_start = local_boundary(local_week_start + timedelta(days=7))
    today_sales = Sale.query.filter(
        Sale.created_at >= day_start, Sale.order_status != "Cancelled"
    ).all()
    yesterday_sales = Sale.query.filter(
        Sale.created_at >= yesterday_start, Sale.created_at < day_start,
        Sale.order_status != "Cancelled"
    ).all()
    week_sales = Sale.query.filter(
        Sale.created_at >= week_start, Sale.order_status != "Cancelled"
    ).all()
    this_week_sales = Sale.query.filter(
        Sale.created_at >= this_week_start, Sale.created_at < next_week_start,
        Sale.order_status != "Cancelled"
    ).all()
    last_week_sales = Sale.query.filter(
        Sale.created_at >= last_week_start, Sale.created_at < this_week_start,
        Sale.order_status != "Cancelled"
    ).all()
    last_month_sales = Sale.query.filter(
        Sale.created_at >= last_month_start, Sale.created_at < month_start,
        Sale.order_status != "Cancelled"
    ).all()
    month_sales = Sale.query.filter(
        Sale.created_at >= month_start, Sale.created_at < next_month_start,
        Sale.order_status != "Cancelled"
    ).all()
    active_sales = Sale.query.filter(
        Sale.order_status != "Cancelled"
    ).order_by(desc(Sale.created_at)).limit(500).all()

    all_open_balance = sum((
        max(
            Decimal("0"),
            Decimal(str(s.subtotal_amount or 0))
            - sum((Decimal(str(p.amount or 0)) for p in s.payments), Decimal("0")),
        )
        for s in active_sales
    ), Decimal("0"))
    top_outstanding_orders = []
    for sale in active_sales:
        paid = sum((Decimal(str(p.amount or 0)) for p in sale.payments), Decimal("0"))
        balance = max(Decimal("0"), Decimal(str(sale.subtotal_amount or 0)) - paid)
        if balance > 0:
            top_outstanding_orders.append({
                "order": sale.order_id or f"#{sale.id}",
                "customer": sale.customer_name or "Customer",
                "product_balance_ngn": float(balance),
                "batch": sale.batch.name if sale.batch else None,
                "pieces": sum(int(item.qty or 0) for item in sale.items),
            })
    top_outstanding_orders.sort(key=lambda row: row["product_balance_ngn"], reverse=True)

    batches = ShipmentBatch.query.order_by(desc(ShipmentBatch.created_at)).limit(20).all()
    batch_rows = []
    for batch in batches:
        sales = [s for s in batch.sales if not s.is_stock_sale and s.order_status != "Cancelled"]
        pieces = sum(int(item.qty or 0) for sale in sales for item in sale.items)
        batch_rows.append({
            "name": batch.name, "status": batch.status,
            "transport_mode": batch.transport_mode,
            "created_at": batch.created_at.isoformat() if batch.created_at else None,
            "age_days": max(0, (now - batch.created_at).days) if batch.created_at else None,
            "orders": len(sales), "pieces": pieces,
        })

    low_stock = Product.query.filter(Product.stock <= 5).order_by(
        Product.stock.asc(), Product.name.asc()
    ).limit(15).all()
    deliveries = Delivery.query.order_by(desc(Delivery.created_at)).limit(15).all()

    question_lower = (question or "").casefold()
    customer_lookup_requested = bool(re.search(
        r"\b(owe|owes|owing|outstanding|balance|customer|customers|order|orders|payment|payments|pay|paid)\b",
        question_lower,
    ))
    stop_words = {
        "which", "who", "what", "when", "where", "how", "many", "much",
        "customer", "customers", "order", "orders", "payment", "payments",
        "owe", "owes", "owing", "outstanding", "balance", "pay", "paid",
        "still", "are", "is", "the", "our", "for", "of", "in", "on", "at", "show", "list", "find",
        "tell", "me", "about", "have", "has", "this", "that", "with", "current", "available", "pieces", "piece",
    }
    lookup_terms = [
        term for term in re.findall(r"[a-z0-9-]{3,}", question_lower)
        if term not in stop_words
    ]
    product_lookup_requested = bool(re.search(
        r"\b(product|products|stock|inventory|quantity|quantities)\b",
        question_lower,
    ))
    product_terms = [
        term for term in lookup_terms
        if term not in {"product", "products", "stock", "inventory", "quantity", "quantities"}
    ]
    matching_products = []
    if product_lookup_requested and product_terms:
        for product in Product.query.order_by(Product.name.asc()).limit(500).all():
            if any(term in (product.name or "").casefold() for term in product_terms):
                matching_products.append({
                    "name": product.name,
                    "stock_pieces": int(product.stock or 0),
                })
            if len(matching_products) >= 15:
                break
    matching_sales = []
    if customer_lookup_requested and lookup_terms:
        for sale in active_sales:
            searchable = " ".join([
                sale.customer_name or "", sale.order_id or "", str(sale.id),
                sale.batch.name if sale.batch else "",
            ]).casefold()
            if any(term in searchable for term in lookup_terms):
                paid = sum((Decimal(str(p.amount or 0)) for p in sale.payments), Decimal("0"))
                matching_sales.append({
                    "order": sale.order_id or f"#{sale.id}",
                    "customer": sale.customer_name or "Customer",
                    "status": sale.order_status,
                    "payment_status": sale.payment_status,
                    "product_paid_ngn": float(paid),
                    "product_balance_ngn": float(max(Decimal("0"), Decimal(str(sale.subtotal_amount or 0)) - paid)),
                    "batch": sale.batch.name if sale.batch else None,
                    "pieces": sum(int(item.qty or 0) for item in sale.items),
                })
            if len(matching_sales) >= 12:
                break

    context = {
        "business": "Oma Group", "currency": "NGN",
        "app_process_guide": [
            "Pay Small Small applies to preorder sales: a customer may pay in full or by instalments.",
            "The first instalment must meet the server-calculated minimum; staff are not shown the underlying product cost.",
            "After the first payment, the plan allows up to two further settlements. Every payment must be verified by a handler before it is recorded.",
            "Each verified payment has its own server-generated receipt. The order receipt lists payment history and remaining product balance.",
            "Product payments and shipping charges are separate balances.",
            "Customer reminder actions become available 35 days after a shipment batch is created.",
            DEMURRAGE_POLICY_GUIDANCE,
            "Customers are consolidated by normalized phone number within one shipment batch only; the same phone in another batch remains a separate customer group.",
            "A sale becomes ready for delivery after its shipping payment is settled, or when it is a stocked sale.",
            "Annie is read-only. Staff must use the normal Oma workflows to create, verify, edit or settle records."
        ],
        "as_of_local": lagos_now.isoformat(),
        "staff_role": "admin" if user.is_admin else "staff",
        "sales_today": summarize_sales(today_sales),
        "sales_yesterday": summarize_sales(yesterday_sales),
        "sales_last_7_days": summarize_sales(week_sales),
        "sales_this_week": summarize_sales(this_week_sales),
        "sales_last_week": summarize_sales(last_week_sales),
        "sales_month_to_date": summarize_sales(month_sales),
        "sales_last_month": summarize_sales(last_month_sales),
        "inventory_preview": [{
            "name": p.name, "stock_pieces": int(p.stock or 0)
        } for p in Product.query.order_by(Product.name.asc()).limit(50).all()],
        "outstanding_product_balance_recent_500_open_orders_ngn": float(all_open_balance),
        "largest_outstanding_orders_recent_500": (
            top_outstanding_orders[:15] if customer_lookup_requested else []
        ),
        "shipment_batches": batch_rows,
        "shipment_batch_status_counts": {
            str(status or "unknown"): int(count)
            for status, count in db.session.query(
                ShipmentBatch.status, db.func.count(ShipmentBatch.id)
            ).group_by(ShipmentBatch.status).all()
        },
        "product_count": Product.query.count(),
        "total_stock_pieces": int(
            db.session.query(db.func.coalesce(db.func.sum(Product.stock), 0)).scalar() or 0
        ),
        "matching_products": matching_products,
        "low_stock_products": [{"name": p.name, "stock_pieces": int(p.stock or 0)} for p in low_stock],
        "recent_deliveries": [{
            "id": d.id, "status": d.status, "method": d.method,
            "sales_count": len(d.sales),
        } for d in deliveries],
        "matching_customer_orders": matching_sales,
        "data_scope_note": "Outstanding balance covers at most the 500 most recent active orders; do not present it as a complete company-wide total.",
    }
    if user.is_admin:
        context["admin_only_financial_summary"] = {
            "profit_last_7_days_ngn": float(sum(
                (Decimal(str(s.profit or 0)) for s in week_sales), Decimal("0")
            )),
        }
    return context


def answer_question(user, question):
    """Answer Oma questions locally from a bounded, role-aware database snapshot."""
    question = (question or "").strip()
    if not question:
        return "I'm Annie, Oma's business assistant. I answer questions about Oma records and procedures."

    lowered = re.sub(r"\s+", " ", question.casefold()).strip(" ?!.")
    if re.fullmatch(r"(hi|hello|hey|good morning|good afternoon|good evening|how are you)", lowered):
        return "Hello! 😊 I'm Annie, your Oma business assistant."

    if any(term in lowered for term in ("what can you do", "help me", "your capabilities", "what do you know", "how can you help")):
        return (
            "I can check live Oma records for sales, verified payments, outstanding product balances, "
            "products and stock, shipment batches, deliveries and admin-only profit summaries. "
            "I can also explain Oma procedures such as Pay Small Small, receipts, shipping settlement "
            "and demurrage. I provide information only and cannot change records."
        )

    business_terms = (
        "oma", "sales", "sale", "order", "customer", "payment", "paid", "owe", "owing",
        "balance", "stock", "inventory", "product", "shipment", "batch", "shipping",
        "delivery", "deliver", "profit", "margin", "revenue", "business", "staff",
        "team", "app", "preorder", "pre-order", "pay small", "small small", "money",
        "cash", "income", "turnover", "collected", "instalment", "installment",
        "demurrage", "receipt", "reminder", "courier", "rate", "today", "yesterday",
        "week", "month", "quantity", "quantities",
    )
    if not any(term in lowered for term in business_terms):
        return (
            "I'm Annie, Oma's business assistant. I can only answer questions about Oma records and procedures. "
            "I cannot confirm this topic from the available Oma information."
        )

    context = build_business_context(user, question)

    def money(value):
        try:
            return f"₦{float(value or 0):,.2f}"
        except (TypeError, ValueError):
            return "₦0.00"

    def list_lines(rows, formatter, empty):
        if not rows:
            return empty
        return "\n".join("• " + formatter(row) for row in rows)

    # Permission checks happen before using any admin-only values.
    if "profit" in lowered or "margin" in lowered:
        financial = context.get("admin_only_financial_summary")
        if not financial:
            return "I can't share profit or margin information with your staff account. Please ask an administrator."
        return (
            "Recorded profit for the last 7 days: "
            f"{money(financial.get('profit_last_7_days_ngn'))}. "
            "This is calculated from Oma's database, not estimated."
        )

    process_words = (
        "how do i", "how to", "how can i", "process", "procedure", "steps",
        "what happens", "how does", "when can", "receipt", "pay small",
        "instalment", "installment", "demurrage", "reminder", "shipping payment",
    )
    if any(word in lowered for word in process_words):
        guide = context.get("app_process_guide", [])
        topic_map = {
            "pay small": ("pay small", "instalment", "installment", "payment"),
            "instalment": ("instalment", "installment", "payment"),
            "installment": ("instalment", "installment", "payment"),
            "receipt": ("receipt", "payment"),
            "demurrage": ("demurrage", "shipping", "arrival"),
            "reminder": ("reminder", "35 days", "batch"),
            "shipping": ("shipping", "demurrage", "arrival"),
            "delivery": ("delivery", "shipping"),
            "batch": ("batch", "shipping", "reminder"),
        }
        topics = next((terms for key, terms in topic_map.items() if key in lowered), ())
        relevant = [item for item in guide if not topics or any(t in item.casefold() for t in topics)]
        if not relevant:
            relevant = guide[:4]
        return "Here's the relevant Oma procedure:\n" + list_lines(relevant[:5], str, "I don't have a verified procedure for that yet.")

    if any(word in lowered for word in ("low stock", "running low", "almost out", "stock alert", "reorder")):
        rows = context.get("low_stock_products", [])
        return (
            "Products with 5 pieces or fewer in stock:\n"
            + list_lines(rows, lambda row: f"{row['name']}: {row['stock_pieces']} piece(s)",
                         "No products currently meet the low-stock threshold.")
        )

    if any(word in lowered for word in ("outstanding", "owe", "owes", "owing", "unpaid", "balance")):
        if "shipping" in lowered or "demurrage" in lowered:
            return (
                "Shipping charges and demurrage are separate from product-payment balances. "
                "Open the relevant shipment batch in Oma to see the current shipping settlement and demurrage."
            )
        rows = context.get("matching_customer_orders") or context.get("largest_outstanding_orders_recent_500") or []
        header = "Matching customer/order balances:" if context.get("matching_customer_orders") else "Outstanding balances in the 500 most recent active orders:"
        details = list_lines(
            rows[:10],
            lambda row: (
                f"{row.get('customer') or 'Customer'} ({row.get('order') or 'order'}): "
                f"{money(row.get('product_balance_ngn'))}"
                + (f" — {row['batch']}" if row.get("batch") else "")
            ),
            "I couldn't find matching unpaid orders in the available records.",
        )
        total = context.get("outstanding_product_balance_recent_500_open_orders_ngn")
        return f"{header}\n{details}\n\nRecent-order outstanding total: {money(total)}. This is not a full-company total."

    if any(word in lowered for word in ("batch", "shipment", "in transit", "arrived")):
        rows = context.get("shipment_batches", [])
        status_counts = context.get("shipment_batch_status_counts", {})
        wanted = "In Transit" if "transit" in lowered else (
            "Arrived - Awaiting Shipping Payment" if "arrived" in lowered else None
        )
        if wanted:
            matching = [row for row in rows if str(row.get("status", "")).casefold() == wanted.casefold()]
            count = status_counts.get(wanted, len(matching))
            label = "in transit" if wanted == "In Transit" else "arrived and awaiting shipping payment"
            return (
                f"Oma has {count} batch(es) marked {label}.\n"
                + list_lines(matching[:10], lambda row: f"{row['name']} — {row['transport_mode']}, {row['orders']} order(s), {row['pieces']} pieces",
                             "The count includes older batches outside the 20 shown here.")
            )
        return "Recent shipment batches:\n" + list_lines(
            rows[:12],
            lambda row: f"{row['name']} — {row['status']}, {row['transport_mode']}, {row['orders']} order(s), {row['pieces']} pieces",
            "There are no shipment batches in the database."
        )

    if "deliver" in lowered:
        rows = context.get("recent_deliveries", [])
        return "Recent deliveries:\n" + list_lines(
            rows[:10],
            lambda row: f"Delivery #{row['id']} — {row['status']} ({row['method']}), {row['sales_count']} order(s)",
            "No delivery records were found."
        )

    if any(word in lowered for word in ("product", "stock", "inventory", "quantity", "quantities")):
        if any(word in lowered for word in ("list", "show all", "all products", "catalogue", "catalog")):
            rows = context.get("inventory_preview", [])
            return "Product stock (first 50 alphabetically):\n" + list_lines(
                rows, lambda row: f"{row['name']}: {row['stock_pieces']} piece(s)",
                "There are no product records."
            )
        rows = context.get("matching_products", [])
        if rows:
            return "Matching products and current stock:\n" + list_lines(
                rows, lambda row: f"{row['name']}: {row['stock_pieces']} piece(s)", ""
            )
        return (
            f"Oma currently has {context.get('product_count', 0)} product record(s) "
            f"and {context.get('total_stock_pieces', 0)} pieces of stock in total. "
            "Include a product name if you want its exact quantity."
        )

    if any(word in lowered for word in ("sale", "sales", "revenue", "today", "yesterday", "this week", "last 7 days", "last week", "this month", "month to date", "collected", "income", "turnover", "money", "cash", "made")):
        if "yesterday" in lowered:
            period, label = context.get("sales_yesterday", {}), "yesterday"
        elif "last month" in lowered or "previous month" in lowered:
            period, label = context.get("sales_last_month", {}), "last calendar month"
        elif "this month" in lowered or "month to date" in lowered:
            period, label = context.get("sales_month_to_date", {}), "this month to date"
        elif "last week" in lowered or "previous week" in lowered:
            period, label = context.get("sales_last_week", {}), "last calendar week"
        elif "this week" in lowered:
            period, label = context.get("sales_this_week", {}), "this calendar week"
        elif "today" in lowered:
            period, label = context.get("sales_today", {}), "today"
        else:
            period, label = context.get("sales_last_7_days", {}), "the last 7 days"
        return (
            f"Sales summary for {label}: {period.get('orders', 0)} order(s), "
            f"recorded product value {money(period.get('product_value_ngn'))}, "
            f"verified product payments {money(period.get('verified_product_payments_ngn'))}, "
            f"and product balance {money(period.get('product_balance_ngn'))}. "
            "Shipping charges are tracked separately."
        )

    if any(word in lowered for word in ("customer", "order", "payment", "paid")):
        rows = context.get("matching_customer_orders", [])
        if rows:
            return "Matching Oma orders:\n" + list_lines(
                rows[:10],
                lambda row: f"{row['customer']} — {row['order']}, {row['status']}, paid {money(row['product_paid_ngn'])}, balance {money(row['product_balance_ngn'])}",
                ""
            )
        return (
            "I can check customer orders and verified payments. Include the customer's "
            "name, order number or shipment batch so I can narrow down the records."
        )

    return (
        "I can help with Oma's live sales, product stock, outstanding balances, shipment batches, "
        "deliveries and app procedures. Ask about a time period or include a customer, product or order name."
    )


def process_pending_annie_replies(limit=1):
    """Process durable tagged questions without blocking the original chat send."""
    now = datetime.utcnow()
    # Recover tasks abandoned by a worker restart. A normal AI request has a
    # 12-second provider timeout, so five minutes is ample recovery headroom.
    AnnieReplyTask.query.filter(
        AnnieReplyTask.status == "processing",
        AnnieReplyTask.created_at < now - timedelta(minutes=5),
    ).update({"status": "pending"}, synchronize_session=False)

    processed = 0
    for _ in range(max(1, min(int(limit or 1), 3))):
        task = (
            AnnieReplyTask.query
            .filter(AnnieReplyTask.status == "pending")
            .order_by(AnnieReplyTask.created_at.asc(), AnnieReplyTask.id.asc())
            .with_for_update(skip_locked=True)
            .first()
        )
        if task is None:
            break

        task.status = "processing"
        task.attempts = (task.attempts or 0) + 1
        task_id = task.id
        db.session.commit()

        try:
            task = db.session.get(AnnieReplyTask, task_id)
            message = task.message if task else None
            asker = task.asker if task else None
            if (
                message is None or asker is None or message.deleted_at is not None
                or not asker.is_active or not is_annie_mention(message.content)
            ):
                if task:
                    task.status = "failed"
                    task.last_error = "The original message was removed or the asking account is no longer active."
                    task.processed_at = datetime.utcnow()
                    db.session.commit()
                continue

            question = _ANNIE_MENTION.sub("", message.content or "").strip()
            answer = (
                "Hi! I'm Annie. What would you like to know about Oma?"
                if not question else answer_question(asker, question)
            )
            reply, created = post_annie_message(
                answer,
                event_key=f"annie-reply-{message.id}",
                recipient_user_ids=_active_staff_ids(),
                push_type="chat_message",
                push_data={"reply_to_id": str(message.id)},
            )
            task.status = "completed"
            task.processed_at = datetime.utcnow()
            task.last_error = None
            db.session.commit()
            if created:
                from app.services.audit import _schedule_outbox_flush
                _schedule_outbox_flush()
            processed += 1
        except Exception as exc:
            db.session.rollback()
            task = db.session.get(AnnieReplyTask, task_id)
            if task is not None:
                task.status = "failed" if (task.attempts or 0) >= 3 else "pending"
                task.last_error = str(exc)[:1000]
                if task.status == "failed":
                    task.processed_at = datetime.utcnow()
                db.session.commit()
            log.exception("Annie reply task %s failed", task_id)
    return processed


def process_due_payment_reminders(now=None):
    """Post one idempotent Annie team update per batch once its 35-day reminder is due."""
    now = now or datetime.utcnow()
    cutoff = now - timedelta(days=35)
    batches = ShipmentBatch.query.filter(
        ShipmentBatch.status == ShipmentBatch.STATUS_IN_TRANSIT,
        ShipmentBatch.created_at <= cutoff,
    ).order_by(ShipmentBatch.created_at.asc()).all()

    from app.services.payments import build_batch_payment_reminders, PaymentError
    posted = 0
    for batch in batches:
        event_key = f"annie-reminder-batch-{batch.id}-35d"
        if ChatMessage.query.filter_by(client_operation_id=event_key).first():
            continue
        try:
            notices = build_batch_payment_reminders(batch, now=now)
        except PaymentError:
            continue
        if not notices:
            continue
        outstanding = sum(Decimal(str(item["product_outstanding"])) for item in notices)
        shipping = sum(Decimal(str(item["estimated_shipping"])) for item in notices)
        pieces = sum(int(item["piece_count"]) for item in notices)
        body = (
            f"35-day customer reminders are due for {batch.name}. "
            f"{len(notices)} consolidated customer reminder(s), {pieces} pieces. "
            f"Outstanding product balance: {_money(outstanding)}. "
            f"Estimated shipping: {_money(shipping)} (separate from product payments). "
            f"{DEMURRAGE_POLICY_GUIDANCE} Open the batch's customer reminder actions to prepare "
            "each WhatsApp message."
        )
        _, created = post_annie_message(
            body, event_key=event_key, recipient_user_ids=_active_staff_ids(),
            push_type="chat_message",
            push_data={"event": "35_day_payment_reminder", "batch_id": str(batch.id)},
        )
        if created:
            posted += 1

    if posted:
        db.session.commit()
        from app.services.audit import _schedule_outbox_flush
        _schedule_outbox_flush()
    return posted


def maybe_process_due_payment_reminders():
    """Throttled request-driven reminder check for Oma's single free web instance."""
    import threading
    import time

    if not hasattr(maybe_process_due_payment_reminders, "_lock"):
        maybe_process_due_payment_reminders._lock = threading.Lock()
        maybe_process_due_payment_reminders._last = 0.0
    lock = maybe_process_due_payment_reminders._lock
    if not lock.acquire(blocking=False):
        return 0
    try:
        now = time.monotonic()
        if now - maybe_process_due_payment_reminders._last < 60:
            return 0
        maybe_process_due_payment_reminders._last = now
        return process_due_payment_reminders()
    finally:
        lock.release()


def process_annie_question(message_id, asker_user_id):
    """Answer a tagged chat message immediately using the local Oma database engine.

    This path intentionally does not depend on the optional AnnieReplyTask queue
    table: a missing queue migration must never silence direct @Annie questions.
    """
    message = db.session.get(ChatMessage, int(message_id))
    asker = db.session.get(User, int(asker_user_id))
    if (
        message is None or asker is None or not asker.is_active
        or message.deleted_at is not None
        or message.sender_user_id != asker.id
        or not is_annie_mention(message.content)
    ):
        return None

    question = _ANNIE_MENTION.sub("", message.content or "").strip()
    answer = (
        "Hi! I'm Annie. What would you like to know about Oma?"
        if not question else answer_question(asker, question)
    )
    # Save the actual answer independently of Firebase/notification tables.
    # A push-queue problem must never erase Annie's chat reply.
    reply, created = post_annie_message(
        answer,
        event_key=f"annie-reply-{message.id}",
        recipient_user_ids=[],
        push_type="chat_message",
        push_data={"reply_to_id": str(message.id)},
    )
    if created:
        db.session.commit()

        # Best-effort push delivery happens only after the reply is durable.
        # The chat timeline also polls, so a notification outage cannot silence Annie.
        try:
            from app.services.push_notifications import queue_user_notification
            preview = " ".join(getattr(reply, "content", answer).split())
            if len(preview) > 180:
                preview = preview[:177].rstrip() + "..."
            staff_ids = _active_staff_ids()
            bot = User.query.filter_by(is_system=True).first() if staff_ids else None
            for user_id in staff_ids:
                if not PushDevice.query.filter_by(user_id=user_id, enabled=True).first():
                    continue
                queue_user_notification(
                    user_id,
                    event_type="chat_message",
                    title="Annie",
                    body=preview,
                    data={
                        "type": "chat_message",
                        "chat_message_id": str(reply.id),
                        "sender_user_id": str(bot.id if bot else ""),
                        "sender_username": "Annie",
                        "message_content": preview,
                        "sound": "chat_message",
                        "reply_to_id": str(message.id),
                    },
                )
            db.session.commit()
            from app.services.audit import _schedule_outbox_flush
            _schedule_outbox_flush()
        except Exception:
            db.session.rollback()
            log.exception("Annie reply %s was saved, but push delivery could not be queued", reply.id)

    log.info("Annie answered tagged chat message %s", message.id)
    return reply
