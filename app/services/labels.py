"""
Shipping label generation — one label per Delivery (one per physical
parcel), even when it consolidates multiple sales for the same customer.

Field set is deliberately fixed to exactly what's needed on the label:
sender (logo/phone/address from Settings), recipient (name/phone/address
from the sale), Order ID + date of shipment (from the sale/delivery),
and weight/dimensions/remarks captured fresh per label. Any missing value
shows "N/A" rather than a blank.
"""
import io
import os

from app.services.settings import get_settings
from app.services.barcodes import generate_barcode_png

NA = "N/A"

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


def label_ready(delivery):
    """Weight and dimensions must be captured before a label can be generated."""
    return delivery.package_weight_kg is not None and bool(delivery.package_dimensions)


def get_label_context(delivery):
    """Data needed to render a label, shared by the print-HTML page and the PDF."""
    settings = get_settings()
    logo_bytes, _ = get_logo_bytes()

    # Consolidation is always same-customer (by name or phone), so every sale
    # in a delivery shares one recipient. The FIRST sale is the label's
    # primary order/tracking reference; additional consolidated sales are
    # listed separately so nothing is lost, but only one barcode is printed.
    primary_sale = delivery.sales[0] if delivery.sales else None
    other_order_ids = [s.order_id for s in delivery.sales[1:]] if len(delivery.sales) > 1 else []

    line_items = []
    for sale in delivery.sales:
        for item in sale.items:
            line_items.append({
                "product_name": item.product.name if item.product else f"Product #{item.product_id}",
                "variant_note": item.variant_note or NA,
                "qty": item.qty,
            })

    order_id = (primary_sale.order_id if primary_sale else None) or NA
    barcode_png = generate_barcode_png(order_id) if order_id != NA else None

    return {
        "settings": settings,
        "delivery": delivery,
        "has_logo": logo_bytes is not None,
        "company_phone": settings.business_phone or NA,
        "company_address": settings.business_address or NA,
        "order_id": order_id,
        "other_order_ids": other_order_ids,
        "date_of_shipment": delivery.shipped_at.strftime("%Y-%m-%d") if delivery.shipped_at else NA,
        "recipient_name": (primary_sale.customer_name if primary_sale else None) or NA,
        "recipient_phone": (primary_sale.customer_phone if primary_sale else None) or NA,
        "delivery_address": delivery.delivery_address or (primary_sale.customer_address if primary_sale else None) or NA,
        "weight": f"{delivery.package_weight_kg} kg" if delivery.package_weight_kg is not None else NA,
        "dimensions": delivery.package_dimensions or NA,
        "remarks": delivery.remarks or NA,
        "line_items": line_items,
        "barcode_png": barcode_png,
    }


def generate_label_pdf(delivery):
    from reportlab.lib.units import mm
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image, HRFlowable
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib import colors
    from reportlab.lib.utils import ImageReader
    from reportlab.lib.enums import TA_CENTER

    ctx = get_label_context(delivery)
    settings = ctx["settings"]

    width = settings.label_width_mm * mm
    height = settings.label_height_mm * mm
    margin = 4 * mm
    content_width = width - 2 * margin

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=(width, height),
        leftMargin=margin, rightMargin=margin, topMargin=margin, bottomMargin=margin,
    )

    styles = getSampleStyleSheet()
    section_style = ParagraphStyle("section", parent=styles["Normal"], fontSize=8, textColor=colors.grey, spaceAfter=1)
    normal_style = ParagraphStyle("normal", parent=styles["Normal"], fontSize=9, leading=12)
    recipient_style = ParagraphStyle("recipient", parent=styles["Normal"], fontSize=13, leading=15)
    order_id_style = ParagraphStyle("orderid", parent=styles["Normal"], fontSize=11, leading=14)
    center_style = ParagraphStyle("center", parent=styles["Normal"], fontSize=9, alignment=TA_CENTER)

    story = []

    # Sender: small logo (kept small deliberately, not the visual focus) + phone/address
    logo_bytes, _ = get_logo_bytes()
    if logo_bytes:
        try:
            img_reader = ImageReader(io.BytesIO(logo_bytes))
            iw, ih = img_reader.getSize()
            max_logo_h = 10 * mm  # deliberately small — a corner mark, not a banner
            max_logo_w = content_width * 0.4
            scale = min(max_logo_w / iw, max_logo_h / ih)
            story.append(Image(io.BytesIO(logo_bytes), width=iw * scale, height=ih * scale))
        except Exception:
            pass
    story.append(Paragraph(f"Tel: {ctx['company_phone']}", normal_style))
    story.append(Paragraph(ctx["company_address"], normal_style))
    story.append(Spacer(1, 2 * mm))
    story.append(HRFlowable(width="100%", color=colors.grey, thickness=0.75))
    story.append(Spacer(1, 2 * mm))

    # Recipient
    story.append(Paragraph("TO", section_style))
    story.append(Paragraph(ctx["recipient_name"], recipient_style))
    story.append(Paragraph(ctx["recipient_phone"], normal_style))
    story.append(Paragraph(ctx["delivery_address"], normal_style))
    story.append(Spacer(1, 2 * mm))
    story.append(HRFlowable(width="100%", color=colors.grey, thickness=0.75))
    story.append(Spacer(1, 2 * mm))

    # Order details
    story.append(Paragraph(f"ORDER ID: {ctx['order_id']}", order_id_style))
    if ctx["other_order_ids"]:
        story.append(Paragraph("Also includes: " + ", ".join(ctx["other_order_ids"]), normal_style))
    story.append(Paragraph(f"Date of Shipment: {ctx['date_of_shipment']}", normal_style))
    story.append(Paragraph(f"Weight: {ctx['weight']}    Dimensions: {ctx['dimensions']}", normal_style))
    story.append(Paragraph(f"Remarks: {ctx['remarks']}", normal_style))
    story.append(Spacer(1, 3 * mm))

    # Barcode — bottom of the label, the last thing on it
    if ctx["barcode_png"]:
        bc_reader = ImageReader(io.BytesIO(ctx["barcode_png"]))
        biw, bih = bc_reader.getSize()
        bc_w = content_width * 0.9
        bc_h = bih * (bc_w / biw)
        story.append(Image(io.BytesIO(ctx["barcode_png"]), width=bc_w, height=bc_h))

    doc.build(story)
    buf.seek(0)
    return buf
