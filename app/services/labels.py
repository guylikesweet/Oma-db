"""
Shipping label generation — one label per Delivery (one per physical
parcel), even when it consolidates multiple sales for the same customer.
"""
import io
import os

from app.services.settings import get_settings

# Preferred logo source: a file committed to the repo at this exact path.
# Since it's part of the git repo (not a runtime upload), it survives every
# Render redeploy automatically — no database storage needed for it.
# Falls back to the Settings-page DB-stored logo if this file isn't present.
STATIC_LOGO_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "static", "logo.png")


def get_logo_bytes():
    """Returns (bytes, mimetype) for the logo, or (None, None) if none is set anywhere."""
    if os.path.exists(STATIC_LOGO_PATH):
        with open(STATIC_LOGO_PATH, "rb") as f:
            return f.read(), "image/png"

    settings = get_settings()
    if settings.logo_data:
        return settings.logo_data, settings.logo_mimetype or "image/png"

    return None, None


def get_label_context(delivery):
    """Data needed to render a label, shared by the print-HTML page and the PDF."""
    settings = get_settings()
    logo_bytes, logo_mimetype = get_logo_bytes()
    has_static_logo = os.path.exists(STATIC_LOGO_PATH)

    # Consolidation is always same-customer (by name or phone), so every sale
    # in a delivery shares one recipient — safe to read from the first sale.
    primary_sale = delivery.sales[0] if delivery.sales else None

    line_items = []
    for sale in delivery.sales:
        for item in sale.items:
            line_items.append({
                "sale_id": sale.id,
                "product_name": item.product.name if item.product else f"Product #{item.product_id}",
                "variant_note": item.variant_note,
                "qty": item.qty,
            })

    return {
        "settings": settings,
        "delivery": delivery,
        "has_logo": logo_bytes is not None,
        "has_static_logo": has_static_logo,
        "recipient_name": primary_sale.customer_name if primary_sale else "",
        "recipient_phone": primary_sale.customer_phone if primary_sale else "",
        "recipient_state": primary_sale.customer_state if primary_sale else "",
        "delivery_address": delivery.delivery_address or (primary_sale.customer_address if primary_sale else ""),
        "line_items": line_items,
        "sale_ids": [s.id for s in delivery.sales],
    }


def generate_label_pdf(delivery):
    from reportlab.lib.units import mm
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib import colors
    from reportlab.lib.utils import ImageReader

    ctx = get_label_context(delivery)
    settings = ctx["settings"]

    width = settings.label_width_mm * mm
    height = settings.label_height_mm * mm
    margin = 4 * mm

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=(width, height),
        leftMargin=margin, rightMargin=margin, topMargin=margin, bottomMargin=margin,
    )

    styles = getSampleStyleSheet()
    business_style = ParagraphStyle("business", parent=styles["Heading3"], fontSize=11, spaceAfter=1)
    small_style = ParagraphStyle("small", parent=styles["Normal"], fontSize=8, leading=10)
    label_style = ParagraphStyle("label", parent=styles["Normal"], fontSize=9, spaceAfter=1, textColor=colors.grey)
    recipient_style = ParagraphStyle("recipient", parent=styles["Normal"], fontSize=12, leading=14)

    story = []

    logo_bytes, _ = get_logo_bytes()
    if logo_bytes:
        try:
            img_reader = ImageReader(io.BytesIO(logo_bytes))
            iw, ih = img_reader.getSize()
            max_w = width - 2 * margin
            max_logo_h = 18 * mm
            scale = min(max_w / iw, max_logo_h / ih)
            story.append(Image(io.BytesIO(logo_bytes), width=iw * scale, height=ih * scale))
            story.append(Spacer(1, 3 * mm))
        except Exception:
            pass  # bad/unreadable image data shouldn't block label generation

    if settings.business_name:
        story.append(Paragraph(settings.business_name, business_style))
    if settings.business_phone:
        story.append(Paragraph(settings.business_phone, small_style))
    if settings.business_address:
        story.append(Paragraph(settings.business_address, small_style))
    story.append(Spacer(1, 4 * mm))

    story.append(Paragraph("SHIP TO", label_style))
    story.append(Paragraph(ctx["recipient_name"] or "-", recipient_style))
    if ctx["recipient_phone"]:
        story.append(Paragraph(ctx["recipient_phone"], small_style))
    if ctx["delivery_address"]:
        story.append(Paragraph(ctx["delivery_address"], small_style))
    if ctx["recipient_state"]:
        story.append(Paragraph(ctx["recipient_state"], small_style))
    story.append(Spacer(1, 4 * mm))

    story.append(Paragraph(f"Parcel #{delivery.id} &mdash; {delivery.method or ''}", label_style))
    order_ref = ", ".join(f"#{sid}" for sid in ctx["sale_ids"])
    story.append(Paragraph(f"Order(s): {order_ref}", small_style))
    story.append(Spacer(1, 3 * mm))

    table_data = [["Item", "Variant", "Qty"]]
    for li in ctx["line_items"]:
        table_data.append([li["product_name"], li["variant_note"] or "-", str(li["qty"])])

    items_table = Table(table_data, colWidths=[(width - 2 * margin) * 0.5, (width - 2 * margin) * 0.3, (width - 2 * margin) * 0.2])
    items_table.setStyle(TableStyle([
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
        ("BACKGROUND", (0, 0), (-1, 0), colors.whitesmoke),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ]))
    story.append(items_table)

    doc.build(story)
    buf.seek(0)
    return buf
