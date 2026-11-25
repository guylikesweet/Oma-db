"""Pay Small Small business rules and per-batch customer reminders."""
from collections import defaultdict
from datetime import datetime, timedelta
from decimal import Decimal
from urllib.parse import quote
from app.models import ShipmentBatch
from app.services.notifications import whatsapp_number, NotificationError


class PaymentError(ValueError):
    pass


def _paid(sale):
    return sum((p.amount or Decimal("0")) for p in sale.payments)


def _balance(sale):
    return max(Decimal("0"), Decimal(str(sale.subtotal_amount or 0)) - _paid(sale))


def _pieces(sale):
    return sum(int(item.qty or 0) for item in sale.items)


def build_batch_payment_reminders(batch, now=None):
    now = now or datetime.utcnow()
    if not batch or batch.status != ShipmentBatch.STATUS_IN_TRANSIT:
        raise PaymentError("Payment reminders are available only while the shipment is in transit.")
    if not batch.created_at or now < batch.created_at + timedelta(days=45):
        raise PaymentError("Payment reminders become available 45 days after the batch was created.")
    groups = defaultdict(list)
    for sale in batch.sales:
        if sale.is_stock_sale or sale.order_status == "Cancelled":
            continue
        try:
            phone = whatsapp_number(sale.customer_phone)
        except NotificationError:
            continue
        groups[phone].append(sale)
    notices = []
    for phone, sales in groups.items():
        sales.sort(key=lambda s: s.id)
        name = next(((s.customer_name or "").strip() for s in sales if (s.customer_name or "").strip()), "Customer")
        raw_phone = next(((s.customer_phone or "").strip() for s in sales if (s.customer_phone or "").strip()), phone)
        estimate = sum((Decimal(str(s.estimated_shipping_cost or 0)) for s in sales), Decimal("0"))
        outstanding = sum((_balance(s) for s in sales), Decimal("0"))
        pieces = sum((_pieces(s) for s in sales), 0)
        orders = "\n".join(f"• {s.order_id or '#'+str(s.id)} — {', '.join((i.product.name if i.product else 'Product') + (' x'+str(i.qty) if i.qty > 1 else '') for i in s.items)}" for s in sales)
        message = (f"Hello {name},\n\nA quick update: your shipment is still in transit. "
                   f"Please prepare for its arrival.\n\nOrders:\n{orders}\n\n"
                   f"Outstanding product balance: NGN {outstanding:,.2f}\n"
                   f"Estimated shipping cost: NGN {estimate:,.2f} (separate from product payment).\n\n"
                   f"After arrival, you will have 7 days to pay shipping. From day 8, demurrage is NGN 150 per piece per day "
                   f"(currently {pieces} piece(s): NGN {pieces * 150:,} per day).\n"
                   f"Please use {raw_phone} as your payment narration.\n\nThank you.")
        notices.append({"phone": phone, "customer_name": name, "sale_ids": [s.id for s in sales],
                        "piece_count": pieces, "product_outstanding": float(outstanding),
                        "estimated_shipping": float(estimate), "daily_demurrage": pieces * 150,
                        "message": message, "whatsapp_url": f"https://wa.me/{phone}?text={quote(message)}"})
    return notices
