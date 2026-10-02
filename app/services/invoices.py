"""
Invoice / receipt generation — one PDF per Sale, so a customer can be sent
something that verifies exactly what they ordered and what they paid for it.

Deliberately separate from app/services/labels.py (the shipping label):
a label is for the courier and is sized to the configured label paper; an
invoice is for the customer and is always a normal A4 document, laid out
with reportlab's platypus (tables/paragraphs) rather than hand-drawn
coordinates, since it's a simple top-to-bottom document with no fixed
physical page size to fit.
"""
import hashlib
import hmac
import io
import os
from datetime import datetime
from xml.sax.saxutils import escape

from flask import current_app, request

from app.services.settings import get_settings
from app.services.labels import get_logo_bytes

NA = "N/A"

# Shown on every invoice. Edit here to change the wording/timeframe.
SHIPPING_WINDOW_TEXT = "30-45 days"


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
    base = os.environ.get("PUBLIC_BASE_URL", "").rstrip("/")
    if not base:
        base = request.url_root.rstrip("/")
        host = request.host.split(":")[0]
        if host not in ("localhost", "127.0.0.1") and base.startswith("http://"):
            base = "https://" + base[len("http://"):]
    return f"{base}/verify/{sale.order_id or sale.id}/{invoice_signature(sale)}"


def _money(value):
    if value is None:
        return "0.00"
    return f"{value:,.2f}"


def _safe(value):
    """Escapes user-entered text before it goes into a reportlab Paragraph —
    Paragraph parses its input as a small XML/HTML subset, so an unescaped
    '&' or '<' in a customer name/address/note would raise at render time
    instead of just printing literally."""
    if value is None:
        return NA
    return escape(str(value)) or NA


def get_invoice_context(sale):
    """Data needed to render an invoice/receipt for one sale."""
    settings = get_settings()

    line_items = []
    for item in sale.items:
        unit_price = item.unit_price or 0
        qty = item.qty or 0
        line_items.append({
            "product_name": item.product.name if item.product else f"Product #{item.product_id}",
            "variant_note": item.variant_note or "",
            "qty": qty,
            "unit_price": unit_price,
            "line_total": unit_price * qty,
        })

    # Shipping is NOT part of what the customer paid. Show the order-time
    # estimate (if any) as information only, or the actual figure once the
    # batch has arrived and it has been calculated.
    actual_shipping = sale.actual_shipping_cost
    estimated_shipping = sale.estimated_shipping_cost

    return {
        "settings": settings,
        "sale": sale,
        "has_logo": get_logo_bytes()[0] is not None,
        "business_name": settings.business_name or NA,
        "business_phone": settings.business_phone or NA,
        "business_address": settings.business_address or NA,
        "order_id": sale.order_id or f"#{sale.id}",
        "sale_date": sale.sale_date.strftime("%Y-%m-%d") if sale.sale_date else NA,
        "generated_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC"),
        "customer_name": sale.customer_name or NA,
        "customer_phone": sale.customer_phone or NA,
        "customer_address": sale.customer_address or NA,
        "customer_state": sale.customer_state or NA,
        "payment_status": sale.payment_status or NA,
        "order_status": sale.order_status or NA,
        "line_items": line_items,
        "subtotal": sale.subtotal_amount or 0,
        "estimated_shipping": estimated_shipping,
        "actual_shipping": actual_shipping,
        # Products only. sale.total_amount gains the actual shipping once a batch
        # arrives, but shipping is billed separately and must never be in this figure.
        "total": sale.subtotal_amount or 0,
        "is_stock_sale": sale.is_stock_sale,
        "sale_month": sale.sale_date.strftime("%B %Y") if sale.sale_date else "the month of your order",
        "signature": invoice_signature(sale),
        "verify_url": verify_url(sale),
        "notes": sale.notes or "",
    }


_SMALL_LOGO_CACHE = {}


def _small_logo_bytes():
    """
    The invoice logo is printed about 40mm wide, but static/logo.png is
    2172px wide (~500KB). Embedding it as-is made every invoice ~640KB, which
    is slow to download on a phone. Shrink it once (still sharp when printed)
    and reuse it.
    """
    if "logo" in _SMALL_LOGO_CACHE:
        return _SMALL_LOGO_CACHE["logo"]

    original, _ = get_logo_bytes()
    result = original

    if original:
        try:
            from PIL import Image as PILImage

            img = PILImage.open(io.BytesIO(original))
            img.thumbnail((700, 350))
            buf = io.BytesIO()
            img.save(buf, format="PNG", optimize=True)
            result = buf.getvalue()
        except Exception:
            result = original  # fall back to the full-size logo

    _SMALL_LOGO_CACHE["logo"] = result
    return result


def generate_invoice_pdf(sale):
    """Returns a BytesIO buffer containing a one-page (or more, if there are
    many line items) A4 PDF invoice/receipt for this sale."""
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.units import mm
    from reportlab.lib import colors
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.platypus import (
        SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, Image,
    )
    from reportlab.lib.utils import ImageReader

    ctx = get_invoice_context(sale)
    styles = getSampleStyleSheet()

    title_style = ParagraphStyle(
        "InvoiceTitle", parent=styles["Heading1"], fontSize=18, spaceAfter=2,
    )
    label_style = ParagraphStyle(
        "SectionLabel", parent=styles["Normal"], fontSize=8,
        textColor=colors.HexColor("#888888"), spaceAfter=1,
    )
    normal_style = ParagraphStyle("InvoiceNormal", parent=styles["Normal"], fontSize=10)
    small_muted = ParagraphStyle(
        "SmallMuted", parent=styles["Normal"], fontSize=8, textColor=colors.HexColor("#888888"),
    )

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=A4,
        topMargin=18 * mm, bottomMargin=18 * mm,
        leftMargin=18 * mm, rightMargin=18 * mm,
        title=f"Invoice {ctx['order_id']}",
    )

    story = []

    # ---- Header: logo + business info on the left, invoice meta on the right ----
    logo_bytes = _small_logo_bytes()
    logo_cell = ""
    if logo_bytes:
        try:
            reader = ImageReader(io.BytesIO(logo_bytes))
            iw, ih = reader.getSize()
            max_w, max_h = 40 * mm, 20 * mm
            scale = min(max_w / iw, max_h / ih)
            logo_cell = Image(io.BytesIO(logo_bytes), width=iw * scale, height=ih * scale)
        except Exception:
            logo_cell = ""

    business_block = [
        Paragraph(f"<b>{_safe(ctx['business_name'])}</b>", normal_style),
        Paragraph(_safe(ctx["business_phone"]), normal_style),
        Paragraph(_safe(ctx["business_address"]), normal_style),
    ]

    invoice_meta = [
        Paragraph("<b>INVOICE / RECEIPT</b>", label_style),
        Paragraph(f"Order ID: <b>{_safe(ctx['order_id'])}</b>", normal_style),
        Paragraph(f"Date: {_safe(ctx['sale_date'])}", normal_style),
        Paragraph(f"Payment status: {_safe(ctx['payment_status'])}", normal_style),
        Paragraph(f"Order status: {_safe(ctx['order_status'])}", normal_style),
    ]

    header_table = Table(
        [[logo_cell, business_block, invoice_meta]],
        colWidths=[42 * mm, 65 * mm, None],
    )
    header_table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("ALIGN", (2, 0), (2, 0), "RIGHT"),
    ]))
    story.append(header_table)
    story.append(Spacer(1, 10 * mm))

    # ---- Bill-to ----
    story.append(Paragraph("BILL TO", label_style))
    story.append(Paragraph(f"<b>{_safe(ctx['customer_name'])}</b>", normal_style))
    story.append(Paragraph(_safe(ctx["customer_phone"]), normal_style))
    story.append(Paragraph(_safe(ctx["customer_address"]), normal_style))
    story.append(Paragraph(_safe(ctx["customer_state"]), normal_style))
    story.append(Spacer(1, 8 * mm))

    # ---- Line items ----
    item_rows = [["Product", "Variant", "Qty", "Unit Price", "Line Total"]]
    for li in ctx["line_items"]:
        item_rows.append([
            Paragraph(_safe(li["product_name"]), normal_style),
            Paragraph(_safe(li["variant_note"]) if li["variant_note"] else "—", normal_style),
            str(li["qty"]),
            _money(li["unit_price"]),
            _money(li["line_total"]),
        ])

    items_table = Table(
        item_rows,
        colWidths=[65 * mm, 35 * mm, 15 * mm, 25 * mm, 27 * mm],
        repeatRows=1,
    )
    items_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#f0f0f0")),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("ALIGN", (2, 0), (-1, -1), "RIGHT"),
        ("ALIGN", (2, 0), (2, 0), "CENTER"),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#cccccc")),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(items_table)
    story.append(Spacer(1, 6 * mm))

    # ---- Total: goods only ----
    totals_table = Table(
        [["TOTAL PAID" if ctx["is_stock_sale"] else "TOTAL PAID (products only)", _money(ctx["total"])]],
        colWidths=[140 * mm, 27 * mm], hAlign="RIGHT",
    )
    totals_table.setStyle(TableStyle([
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("ALIGN", (1, 0), (1, -1), "RIGHT"),
        ("LINEABOVE", (0, 0), (-1, 0), 0.75, colors.black),
        ("FONTNAME", (0, 0), (-1, -1), "Helvetica-Bold"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(totals_table)
    story.append(Spacer(1, 6 * mm))

    # ---- Shipping notice ----
    ship_lines = ["<b>SHIPPING NOTICE</b>"]
    if ctx["is_stock_sale"]:
        ship_lines = []
    elif ctx["actual_shipping"] is not None:
        ship_lines.append(
            f"Shipping for this order has been calculated at "
            f"<b>NGN {_money(ctx['actual_shipping'])}</b> based on the month your "
            f"goods arrived. It is payable separately and is not included in the total above."
        )
    else:
        if ctx["estimated_shipping"] is not None:
            ship_lines.append(
                f"Estimated shipping: <b>NGN {_money(ctx['estimated_shipping'])}</b>. "
                f"This is only an estimate, calculated using this month's shipping rate "
                f"({ctx['sale_month']}). It is not charged now and is not included in the total above."
            )
        ship_lines.append(
            "The actual shipping cost will be calculated using the shipping rate of the "
            "month your goods arrive, so the final amount may differ from this estimate."
        )
    if ship_lines:
        if not ctx["is_stock_sale"]:
            ship_lines.append(
                f"Please prepare your shipping payment - expect to settle it within "
                f"<b>{SHIPPING_WINDOW_TEXT}</b>."
            )
        ship_box = Table(
            [[[Paragraph(l, normal_style) for l in ship_lines]]],
            colWidths=[167 * mm],
        )
        ship_box.setStyle(TableStyle([
            ("BOX", (0, 0), (-1, -1), 0.75, colors.HexColor("#999999")),
            ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#faf6e8")),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("RIGHTPADDING", (0, 0), (-1, -1), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 6),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ]))
        story.append(ship_box)

    if ctx["notes"]:
        story.append(Spacer(1, 8 * mm))
        story.append(Paragraph("NOTES", label_style))
        story.append(Paragraph(_safe(ctx["notes"]), normal_style))

    story.append(Spacer(1, 8 * mm))

    # ---- Authenticity: signed code + QR to the live record ----
    from reportlab.graphics.barcode.qr import QrCodeWidget
    from reportlab.graphics.shapes import Drawing

    widget = QrCodeWidget(ctx["verify_url"])
    x0, y0, x1, y1 = widget.getBounds()
    size = 28 * mm
    qr_drawing = Drawing(
        size, size,
        transform=[size / (x1 - x0), 0, 0, size / (y1 - y0), 0, 0],
    )
    qr_drawing.add(widget)

    sig = ctx["signature"]
    sig_grouped = "-".join(sig[i:i + 5] for i in range(0, len(sig), 5))
    verify_text = [
        Paragraph("<b>VERIFY THIS INVOICE</b>", normal_style),
        Paragraph(f"Verification code: <b>{sig_grouped}</b>", normal_style),
        Paragraph(
            "Scan the QR code, or open the link below, to confirm this invoice "
            "against our records. The page shows the real items and amount paid. "
            "If it does not match this document, or says the code is invalid, "
            "the invoice has been altered and should not be trusted.",
            small_muted,
        ),
        Paragraph(_safe(ctx["verify_url"]), small_muted),
    ]
    verify_table = Table([[qr_drawing, verify_text]], colWidths=[32 * mm, 135 * mm])
    verify_table.setStyle(TableStyle([
        ("BOX", (0, 0), (-1, -1), 0.75, colors.HexColor("#999999")),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
    ]))
    story.append(verify_table)

    story.append(Spacer(1, 6 * mm))
    story.append(Paragraph(
        f"Generated {ctx['generated_at']} - thank you for your order.",
        small_muted,
    ))

    doc.build(story)
    buf.seek(0)
    return buf
