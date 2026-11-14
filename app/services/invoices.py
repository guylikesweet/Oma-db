"""
Invoice / receipt generation for one Sale.

The receipt is a tall phone-sized picture (1080 px wide, 9:16 or a little
taller when there is a lot of text), drawn by app/services/receipt_image.py.
PNG is the preferred photo, JPG is a smaller alternative, and PDF is a small
80 mm page carrying the same picture, so all three always match exactly.

Rules for what a customer may be sent:
  * Only PAID orders get a receipt. Pending / refunded / cancelled orders are
    refused (a refund gets its own separate note, never this document).
  * No "N/A" placeholders and no "Generated ..." timestamp: a missing business
    address or Instagram handle is simply left out.
  * Internal order notes are never printed.

Deliberately separate from app/services/labels.py (the courier shipping label).
"""
import hashlib
import hmac
import io
import json
from functools import lru_cache
from datetime import date, datetime, timedelta, timezone

from flask import current_app, request

from app.services.settings import get_settings
from app.services.labels import get_logo_bytes

NA = "N/A"  # still used by other modules' vocabulary; never printed on receipts

DEFAULT_BUSINESS_NAME = "OmaBuy Nigeria Limited"
DEFAULT_TRACK_DISPLAY = "omabuy.ng/track"

# Nigeria is on West Africa Time all year (UTC+1, no daylight saving), so a
# fixed offset is exact and needs no timezone database on the server.
WAT = timezone(timedelta(hours=1), "WAT")

# Preorder schedule. A preorder window opens on the first Monday of every
# month and closes PREORDER_WINDOW_DAYS later. Goods are expected to arrive
# between ARRIVAL_MIN_DAYS and ARRIVAL_MAX_DAYS after the window CLOSES (not
# after the individual sale). Edit these three numbers to change the schedule.
PREORDER_WINDOW_DAYS = 14
ARRIVAL_MIN_DAYS = 50
ARRIVAL_MAX_DAYS = 75

# The app's order statuses -> the wording a customer sees.
_ORDER_STATUS_LABELS = {
    "New": "Processing",
    "Packed": "Processing",
    "Shipped": "Shipped",
    "Delivered": "Delivered",
}


class ReceiptNotAllowed(ValueError):
    """Raised when a receipt is requested for a sale that must not get one."""


def _to_wat(dt):
    """Converts a datetime to Nigerian time. Naive values are treated as UTC,
    which is how the database stores them (datetime.utcnow)."""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(WAT)


def _first_monday(year, month):
    first = date(year, month, 1)
    return first + timedelta(days=(7 - first.weekday()) % 7)


def _preorder_window_end(on_date):
    """The closing date of the preorder window a sale belongs to. A sale made
    on or before a month's closing date belongs to that month's window; one
    made after it belongs to the next month's window."""
    end = _first_monday(on_date.year, on_date.month) + timedelta(days=PREORDER_WINDOW_DAYS)
    if on_date <= end:
        return end
    year, month = (on_date.year + 1, 1) if on_date.month == 12 else (on_date.year, on_date.month + 1)
    return _first_monday(year, month) + timedelta(days=PREORDER_WINDOW_DAYS)


def estimated_arrival_range(sale):
    """(earliest, latest) estimated arrival dates for a preorder sale."""
    if sale.sale_date:
        basis = sale.sale_date
    elif sale.created_at:
        basis = _to_wat(sale.created_at).date()
    else:
        basis = datetime.now(WAT).date()
    window_end = _preorder_window_end(basis)
    return (
        window_end + timedelta(days=ARRIVAL_MIN_DAYS),
        window_end + timedelta(days=ARRIVAL_MAX_DAYS),
    )


def _fmt_date(d):
    return f"{d.day} {d.strftime('%b %Y')}"


def _canonical(sale):
    """The facts the signature vouches for. Change any of these on a printed
    invoice (price, quantity, product, customer, total) and it stops
    matching the server's record."""
    items = sorted(
        (
            (it.product.name if it.product else str(it.product_id)),
            int(it.qty or 0),
            f"{(it.unit_price or 0):.2f}",
        )
        for it in sale.items
    )
    parts = [
        sale.order_id or f"#{sale.id}",
        sale.sale_date.isoformat() if sale.sale_date else "",
        (sale.customer_name or "").strip(),
        # Products-only figure. total_amount changes when shipping is added at batch
        # arrival, which would wrongly invalidate invoices issued before that.
        f"{(sale.subtotal_amount or 0):.2f}",
    ] + [f"{n}|{q}|{p}" for n, q, p in items]
    return "\n".join(parts)


def invoice_signature(sale):
    """Unforgeable without the server's SECRET_KEY (HMAC-SHA256)."""
    key = current_app.config["SECRET_KEY"].encode()
    digest = hmac.new(key, _canonical(sale).encode(), hashlib.sha256).hexdigest()
    return digest[:20].upper()


def signature_matches(sale, presented):
    return hmac.compare_digest(invoice_signature(sale), (presented or "").upper())


def verify_url(sale):
    base = current_app.config.get("OMA_PUBLIC_BASE_URL", "").rstrip("/")
    if not base:
        base = request.url_root.rstrip("/")
        host = request.host.split(":")[0]
        if host not in ("localhost", "127.0.0.1") and base.startswith("http://"):
            base = "https://" + base[len("http://"):]
    code = sale.public_tracking_code or sale.order_id or str(sale.id)
    return f"{base}/track/{code}?sig={invoice_signature(sale)}"


def _money(value):
    if value is None:
        return "0.00"
    return f"{value:,.2f}"


def _clean(value):
    value = (str(value).strip() if value is not None else "")
    return value or None


def _instagram_handle(settings):
    """The business Instagram handle from Settings, shown as '@name'. Returns
    None when it has not been filled in, so nothing is ever invented."""
    raw = _clean(getattr(settings, "instagram_handle", None))
    if not raw:
        return None
    raw = raw.replace("https://", "").replace("http://", "")
    for prefix in ("www.instagram.com/", "instagram.com/", "instagr.am/"):
        if raw.lower().startswith(prefix):
            raw = raw[len(prefix):]
    raw = raw.split("?")[0].strip("/ @")
    return "@" + raw if raw else None


def receipt_block_reason(sale):
    """Why this sale must NOT be sent a receipt, or None if it may."""
    if (sale.order_status or "") == "Cancelled":
        return "A cancelled order does not get a receipt."
    if (sale.payment_status or "") != "Paid":
        return ("Receipts are only issued for paid orders. Mark the order as "
                "Paid first. A refund gets a separate refund note, not a receipt.")
    return None


def _receipt_date(sale):
    if sale.sale_date:
        d = sale.sale_date
    elif sale.created_at:
        d = _to_wat(sale.created_at).date()
    else:
        d = datetime.now(WAT).date()
    return d.strftime("%d %b %Y")


def _address_text(sale):
    parts, seen = [], set()
    for raw in (sale.customer_address, getattr(sale, "customer_city", None), sale.customer_state):
        part = _clean(raw)
        if part and part.lower() not in seen:
            seen.add(part.lower())
            parts.append(part)
    return ", ".join(parts)


def _notice_paragraphs(sale):
    """The shipping notice, as paragraphs of (text, bold) runs. Same wording
    the old A4 invoice used; nothing is added or removed."""
    if sale.is_stock_sale:
        return []
    actual = sale.actual_shipping_cost
    estimated = sale.estimated_shipping_cost
    sale_month = sale.sale_date.strftime("%B %Y") if sale.sale_date else "the month of your order"
    paras = []
    if actual is not None:
        paras.append([
            ("Shipping for this order has been calculated at ", False),
            (f"NGN {_money(actual)}", True),
            (". It is based on the size and weight of your goods and the shipping rate "
             "for the month they arrived. It is payable separately and is not included "
             "in the total above.", False),
        ])
        paras.append([("Please prepare your shipping payment.", False)])
        return paras
    if estimated is not None:
        paras.append([
            ("Estimated shipping: ", False),
            (f"NGN {_money(estimated)}", True),
            (". This is only an estimate, calculated from the size and weight of your "
             f"goods and this month's shipping rate ({sale_month}). It is not charged "
             "now and is not included in the total above.", False),
        ])
    paras.append([(
        "The actual shipping cost will be calculated using the shipping rate of the "
        "month your goods arrive, so the final amount may differ from this estimate.",
        False,
    )])
    arrival_from, arrival_to = estimated_arrival_range(sale)
    paras.append([
        ("Your goods are expected to arrive between ", False),
        (_fmt_date(arrival_from), True),
        (" and ", False),
        (_fmt_date(arrival_to), True),
        (". Please prepare your shipping payment for when they arrive.", False),
    ])
    return paras


def get_invoice_context(sale):
    """Everything the receipt picture needs, as plain values (no N/A)."""
    settings = get_settings()
    business_name = _clean(settings.business_name) or DEFAULT_BUSINESS_NAME

    line_items = []
    for item in sale.items:
        unit_price = item.unit_price or 0
        qty = item.qty or 0
        line_items.append({
            "name": item.product.name if item.product else f"Product #{item.product_id}",
            "variant": _clean(item.variant_note),
            "qty": qty,
            "unit_text": _money(unit_price),
            "line_text": _money(unit_price * qty),
        })

    signature = invoice_signature(sale)
    return {
        "business_name": business_name,
        "business_phone": _clean(settings.business_phone),
        "business_address": _clean(settings.business_address),
        "instagram": _instagram_handle(settings),
        "order_id": sale.order_id or f"#{sale.id}",
        "date_text": _receipt_date(sale),
        "order_status_label": _ORDER_STATUS_LABELS.get(sale.order_status or "", "Processing"),
        "customer_name": _clean(sale.customer_name) or "Customer",
        "customer_phone": _clean(sale.customer_phone),
        "address_text": _address_text(sale),
        "line_items": line_items,
        # Products only. sale.total_amount gains the actual shipping once a batch
        # arrives, but shipping is billed separately and never part of this figure.
        "total_text": _money(sale.subtotal_amount or 0),
        "total_note": None if sale.is_stock_sale else "(products only)",
        "notice_paragraphs": _notice_paragraphs(sale),
        "verify_url": verify_url(sale),
        "signature": signature,
        "code_text": "-".join(signature[i:i + 5] for i in range(0, len(signature), 5)),
        "track_display": current_app.config.get("OMA_TRACK_DISPLAY") or DEFAULT_TRACK_DISPLAY,
        "footer_text": f"Thank you for your order - {business_name}",
    }


@lru_cache(maxsize=2)
def _render_cached(context_json, logo_bytes):
    """Keep the last two rendered receipts in this worker.

    PNG, JPG and PDF are different encodings of the same artwork. Caching the
    Pillow image avoids repeating the expensive text layout, watermark, seal
    and QR drawing when a user changes format or prints the same receipt.
    The complete rendered context and logo bytes form the cache key, so edits
    to sale details, business settings or logo automatically invalidate it.
    """
    from app.services import receipt_image

    return receipt_image.render_receipt(json.loads(context_json), logo_bytes)


def _render(sale):
    """Draws the receipt and returns the Pillow image (RGBA, rounded corners)."""
    reason = receipt_block_reason(sale)
    if reason:
        raise ReceiptNotAllowed(reason)

    logo_bytes, _ = get_logo_bytes()
    if not logo_bytes:
        # Fall back to a logo uploaded in Settings, if there is one.
        logo_bytes = getattr(get_settings(), "logo_data", None)

    context_json = json.dumps(
        get_invoice_context(sale),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )
    return _render_cached(context_json, bytes(logo_bytes or b""))


def generate_invoice_image(sale, fmt="png"):
    """Returns (BytesIO, mimetype, extension) for a PNG or JPG receipt."""
    from app.services import receipt_image

    fmt = (fmt or "png").lower().lstrip(".")
    img = _render(sale)
    if fmt in ("jpg", "jpeg"):
        return io.BytesIO(receipt_image.to_jpeg_bytes(img)), "image/jpeg", "jpg"
    return io.BytesIO(receipt_image.to_png_bytes(img)), "image/png", "png"


def generate_invoice_pdf(sale):
    """Returns a BytesIO PDF: one 80 mm wide page carrying the same picture
    (never A4). The QR code is a tappable link to the order page."""
    from reportlab.lib.units import mm
    from reportlab.lib.utils import ImageReader
    from reportlab.pdfgen import canvas
    from app.services import receipt_image

    img = _render(sale)
    jpeg = receipt_image.to_jpeg_bytes(img, background=(255, 255, 255), quality=92)

    page_w = 80 * mm
    page_h = page_w * img.height / img.width
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=(page_w, page_h))
    c.setTitle(f"Receipt {sale.order_id or sale.id}")
    c.drawImage(ImageReader(io.BytesIO(jpeg)), 0, 0, width=page_w, height=page_h)

    box = img.info.get("qr_box")
    if box:
        scale = page_w / img.width
        x0, y0, x1, y1 = box
        c.linkURL(
            verify_url(sale),
            (x0 * scale, page_h - y1 * scale, x1 * scale, page_h - y0 * scale),
            relative=0,
        )
    c.showPage()
    c.save()
    buf.seek(0)
    return buf
