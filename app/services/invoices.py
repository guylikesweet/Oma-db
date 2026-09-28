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
import io
from datetime import datetime
from xml.sax.saxutils import escape

from app.services.settings import get_settings
from app.services.labels import get_logo_bytes

NA = "N/A"


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

    # Whichever shipping figure is actually known for this sale — the
    # locked-in actual cost once a batch has arrived, otherwise the
    # order-time estimate. Never both, so the invoice always shows one
    # unambiguous shipping line.
    shipping_cost = sale.actual_shipping_cost
    shipping_label = "Shipping"
    if shipping_cost is None:
        shipping_cost = sale.estimated_shipping_cost
        shipping_label = "Shipping (estimated)"

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
        "shipping_label": shipping_label,
        "shipping_cost": shipping_cost,
        "total": sale.total_amount or 0,
        "notes": sale.notes or "",
    }


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
    logo_bytes, _ = get_logo_bytes()
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

    # ---- Totals ----
    totals_rows = [["Subtotal", _money(ctx["subtotal"])]]
    if ctx["shipping_cost"] is not None:
        totals_rows.append([ctx["shipping_label"], _money(ctx["shipping_cost"])])
    totals_rows.append(["Total", _money(ctx["total"])])

    totals_table = Table(totals_rows, colWidths=[140 * mm, 27 * mm], hAlign="RIGHT")
    totals_table.setStyle(TableStyle([
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("ALIGN", (1, 0), (1, -1), "RIGHT"),
        ("LINEABOVE", (0, -1), (-1, -1), 0.75, colors.black),
        ("FONTNAME", (0, -1), (-1, -1), "Helvetica-Bold"),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]))
    story.append(totals_table)

    if ctx["notes"]:
        story.append(Spacer(1, 8 * mm))
        story.append(Paragraph("NOTES", label_style))
        story.append(Paragraph(_safe(ctx["notes"]), normal_style))

    story.append(Spacer(1, 12 * mm))
    story.append(Paragraph(
        f"Generated {ctx['generated_at']} — thank you for your order.",
        small_muted,
    ))

    doc.build(story)
    buf.seek(0)
    return buf
