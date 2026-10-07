"""
Customer notifications — currently one: the "your goods have arrived" WhatsApp
message sent after a shipment batch arrives.

The wording is fixed here (it is the approved template). The things that
change over time — the bank account customers pay shipping into and the
business name — come from Settings, so an account change never needs a code edit.
"""
import re
from decimal import Decimal
from urllib.parse import quote

from app.models import ShipmentBatch
from app.services.settings import get_settings

# Customers' numbers are stored the way they were typed (e.g. 08012345678).
# WhatsApp needs the number with country code and no leading 0 or "+".
DEFAULT_COUNTRY_CODE = "234"


class NotificationError(ValueError):
    pass


ARRIVAL_TEMPLATE = """Hello {{1}},

Your goods have arrived at the port and are awaiting shipment settlement to prepare for delivery.

Order Details:
Product Name: {{2}}
Sale ID: {{3}}
Amount Paid: {{4}}
Total Shipping Cost Due: {{5}}

Payment Details:
Bank Name: {{6}}
Account Number: {{7}}
Account Name: {{8}}

Please use your phone number {{9}} as the narration for the transaction.

Kindly reply to this message with your payment receipt after payment for verification.

Your delivery will be scheduled immediately after confirmation.

Thank you,
{{10}}"""


def whatsapp_number(raw):
    """08012345678 / +234 801 234 5678 / 2348012345678 / 8012345678 -> 2348012345678."""
    digits = "".join(ch for ch in (raw or "") if ch.isdigit())
    if digits.startswith("00"):
        digits = digits[2:]
    if digits.startswith(DEFAULT_COUNTRY_CODE):
        pass
    elif digits.startswith("0"):
        digits = DEFAULT_COUNTRY_CODE + digits[1:]
    elif len(digits) == 10:
        digits = DEFAULT_COUNTRY_CODE + digits
    if not (10 <= len(digits) <= 15):
        raise NotificationError("This sale's phone number doesn't look like a valid WhatsApp number.")
    return digits


def format_ngn(amount):
    amount = Decimal(amount or 0)
    if amount == amount.to_integral_value():
        return f"NGN {int(amount):,}"
    return f"NGN {amount:,.2f}"


def _product_summary(sale):
    parts = []
    for item in sale.items:
        name = item.product.name if item.product else f"Product #{item.product_id}"
        if item.variant_note:
            name += f" ({item.variant_note})"
        if item.qty and item.qty > 1:
            name += f" x{item.qty}"
        parts.append(name)
    return ", ".join(parts)


def build_batch_arrival_notices(batch):
    """Build compact WhatsApp notices, merging every unsettled sale per phone."""
    if not batch or batch.status != ShipmentBatch.STATUS_ARRIVED:
        raise NotificationError("This shipment batch hasn't been marked as arrived yet.")

    settings = get_settings()
    missing = [
        label for label, value in (
            ("business name", settings.business_name),
            ("bank name", settings.bank_name),
            ("account number", settings.bank_account_number),
            ("account name", settings.bank_account_name),
        ) if not (value or "").strip()
    ]
    if missing:
        raise NotificationError("Add the " + ", ".join(missing) + " in Settings first.")

    groups = {}
    for sale in batch.sales:
        if sale.is_stock_sale or sale.shipping_payment_settled or sale.order_status == "Cancelled":
            continue
        if sale.actual_shipping_cost is None:
            continue
        try:
            phone = whatsapp_number(sale.customer_phone)
        except NotificationError:
            continue
        groups.setdefault(phone, []).append(sale)

    notices = []
    for phone, sales in groups.items():
        sales.sort(key=lambda s: s.id)
        customer_name = next(
            ((s.customer_name or "").strip() for s in sales if (s.customer_name or "").strip()),
            "Customer",
        )
        raw_phone = next(
            ((s.customer_phone or "").strip() for s in sales if (s.customer_phone or "").strip()),
            phone,
        )
        lines = []
        total_paid = Decimal("0")
        total_shipping = Decimal("0")
        for sale in sales:
            paid = sale.subtotal_amount if sale.payment_status == "Paid" else Decimal("0")
            shipping = sale.actual_shipping_cost or Decimal("0")
            total_paid += paid
            total_shipping += shipping
            lines.append(
                f"• {sale.order_id or f'#{sale.id}'} — {_product_summary(sale)} — "
                f"Paid {format_ngn(paid)} — Shipping {format_ngn(shipping)}"
            )

        message = (
            f"Hello {customer_name},\n\n"
            f"Your goods have arrived. Please settle the shipping balance so we can prepare your delivery.\n\n"
            f"Orders:\n" + "\n".join(lines) + "\n\n"
            f"Total paid: {format_ngn(total_paid)}\n"
            f"Total shipping due: {format_ngn(total_shipping)}\n\n"
            f"Payment: {settings.bank_name.strip()} — "
            f"{settings.bank_account_number.strip()} ({settings.bank_account_name.strip()})\n"
            f"Use your phone number {raw_phone} as narration.\n\n"
            f"Reply here with your payment receipt for verification. "
            f"Delivery will be scheduled after confirmation.\n\n"
            f"Thank you,\n{settings.business_name.strip()}"
        )
        notices.append({
            "phone": phone,
            "customer_name": customer_name,
            "sale_ids": [s.id for s in sales],
            "order_ids": [s.order_id or f"#{s.id}" for s in sales],
            "sale_count": len(sales),
            "total_paid": float(total_paid),
            "total_shipping": float(total_shipping),
            "message": message,
            "whatsapp_url": f"https://wa.me/{phone}?text={quote(message)}",
        })

    return notices

def build_arrival_notice(sale):
    """Returns {"phone", "message", "whatsapp_url"} or raises NotificationError with a plain-English reason."""
    if sale.is_stock_sale:
        raise NotificationError("Stocked sales have no shipping to pay, so there is nothing to notify.")
    if not sale.batch or sale.batch.status != ShipmentBatch.STATUS_ARRIVED:
        raise NotificationError("This sale's batch hasn't been marked as arrived yet.")
    if sale.shipping_payment_settled:
        raise NotificationError("Shipping for this sale is already settled.")
    if sale.actual_shipping_cost is None:
        raise NotificationError("This sale has no shipping cost yet.")

    settings = get_settings()
    missing = [
        label for label, value in (
            ("business name", settings.business_name),
            ("bank name", settings.bank_name),
            ("account number", settings.bank_account_number),
            ("account name", settings.bank_account_name),
        ) if not (value or "").strip()
    ]
    if missing:
        raise NotificationError("Add the " + ", ".join(missing) + " in Settings first.")

    phone = whatsapp_number(sale.customer_phone)
    amount_paid = sale.subtotal_amount if sale.payment_status == "Paid" else Decimal("0")

    values = {
        "{{1}}": (sale.customer_name or "Customer").strip(),
        "{{2}}": _product_summary(sale),
        "{{3}}": sale.order_id or f"#{sale.id}",
        "{{4}}": format_ngn(amount_paid),
        "{{5}}": format_ngn(sale.actual_shipping_cost),
        "{{6}}": settings.bank_name.strip(),
        "{{7}}": settings.bank_account_number.strip(),
        "{{8}}": settings.bank_account_name.strip(),
        "{{9}}": (sale.customer_phone or "").strip(),
        "{{10}}": settings.business_name.strip(),
    }
    # One pass over the template, so text inside a value (a product name, say)
    # can never be mistaken for another placeholder.
    message = re.sub(r"\{\{\d+\}\}", lambda m: values.get(m.group(0), m.group(0)), ARRIVAL_TEMPLATE)

    return {
        "phone": phone,
        "message": message,
        "whatsapp_url": f"https://wa.me/{phone}?text={quote(message)}",
    }
