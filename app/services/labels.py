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
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Table, TableStyle, Image
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib import colors
    from reportlab.lib.utils import ImageReader

    ctx = get_label_context(delivery)
    settings = ctx["settings"]

    width = settings.label_width_mm * mm
    height = settings.label_height_mm * mm
    margin = 4 * mm
    content_width = width - 2 * margin
    col_left = content_width * 0.4
    col_right = content_width * 0.6

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=(width, height),
        leftMargin=margin, rightMargin=margin, topMargin=margin, bottomMargin=margin,
    )

    styles = getSampleStyleSheet()
    section_style = ParagraphStyle("section", parent=styles["Normal"], fontSize=7, textColor=colors.grey, spaceAfter=1)
    normal_style = ParagraphStyle("normal", parent=styles["Normal"], fontSize=8.5, leading=10.5)
    recipient_style = ParagraphStyle("recipient", parent=styles["Normal"], fontSize=11, leading=13)
    order_id_style = ParagraphStyle("orderid", parent=styles["Normal"], fontSize=10, leading=12)

    def cell(*flowables):
        return list(flowables)

    def logo_flowable():
        logo_bytes, _ = get_logo_bytes()
        if not logo_bytes:
            return Paragraph(NA, normal_style)
        try:
            img_reader = ImageReader(io.BytesIO(logo_bytes))
            iw, ih = img_reader.getSize()
            max_h, max_w = 8 * mm, col_left - 4 * mm  # deliberately small — a corner mark, not a banner
            scale = min(max_w / iw, max_h / ih)
            img = Image(io.BytesIO(logo_bytes), width=iw * scale, height=ih * scale)
            img.hAlign = "LEFT"
            return img
        except Exception:
            return Paragraph(NA, normal_style)

    def barcode_flowable():
        if not ctx["barcode_png"]:
            return Paragraph(NA, normal_style)
        bc_reader = ImageReader(io.BytesIO(ctx["barcode_png"]))
        biw, bih = bc_reader.getSize()
        max_h = 10 * mm  # confined to its own compact cell, not spanning the label
        max_w = col_right - 4 * mm
        scale = min(max_w / biw, max_h / bih)
        img = Image(io.BytesIO(ctx["barcode_png"]), width=biw * scale, height=bih * scale)
        img.hAlign = "CENTER"
        return img

    order_id_cell = [
        Paragraph("ORDER ID", section_style),
        Paragraph(ctx["order_id"], order_id_style),
    ]
    if ctx["other_order_ids"]:
        order_id_cell.append(Paragraph("Also: " + ", ".join(ctx["other_order_ids"]), normal_style))

    table_data = [
        [cell(logo_flowable()), cell(Paragraph("FROM", section_style), Paragraph(f"Tel: {ctx['company_phone']}", normal_style), Paragraph(ctx["company_address"], normal_style))],
        [cell(Paragraph("TO", section_style)), cell(Paragraph(ctx["recipient_name"], recipient_style), Paragraph(ctx["recipient_phone"], normal_style), Paragraph(ctx["delivery_address"], normal_style))],
        [cell(Paragraph("WEIGHT", section_style), Paragraph(ctx["weight"], normal_style)), cell(Paragraph("DIMENSIONS", section_style), Paragraph(ctx["dimensions"], normal_style))],
        [cell(Paragraph("DATE OF SHIPMENT", section_style), Paragraph(ctx["date_of_shipment"], normal_style)), cell(Paragraph("REMARKS", section_style), Paragraph(ctx["remarks"], normal_style))],
        [order_id_cell, cell(barcode_flowable())],
    ]

    grid = Table(table_data, colWidths=[col_left, col_right])
    grid.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.75, colors.HexColor("#666666")),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 3),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3),
        ("TOPPADDING", (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
    ]))

    doc.build([grid])
    buf.seek(0)
    return buf
