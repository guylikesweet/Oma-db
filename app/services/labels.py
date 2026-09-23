"""
Shipping label generation — one label per Delivery (one per physical
parcel), even when it consolidates multiple sales for the same customer.

Field set is deliberately fixed to exactly what's needed on the label:
sender (logo/phone/address from Settings), recipient (name/phone/address
from the sale), Order ID + date of shipment (from the sale/delivery),
and weight/dimensions/remarks captured fresh per label. Any missing value
shows "N/A" rather than a blank.

The PDF layout is responsive to the configured label size and is designed
to use the available paper area while avoiding horizontal/vertical
overflow on narrow labels.
"""
import io
import os

from app.services.settings import get_settings
from app.services.barcodes import generate_barcode_png

NA = "N/A"

# Preferred logo source: a file committed to the repo at this exact path.
# Falls back to the Settings-page DB-stored logo if this file isn't present.
STATIC_LOGO_PATH = os.path.join(
    os.path.dirname(os.path.dirname(__file__)),
    "static",
    "logo.png",
)


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
    return (
        delivery.package_weight_kg is not None
        and bool(delivery.package_dimensions)
    )


def get_label_context(delivery):
    """Data needed to render a label, shared by the print-HTML page and the PDF."""
    settings = get_settings()
    logo_bytes, _ = get_logo_bytes()

    # Consolidation is always same-customer (by name or phone), so every sale
    # in a delivery shares one recipient. The FIRST sale is the label's
    # primary order/tracking reference; additional consolidated sales are
    # listed separately so nothing is lost, but only one barcode is printed.
    primary_sale = delivery.sales[0] if delivery.sales else None

    other_order_ids = (
        [s.order_id for s in delivery.sales[1:]]
        if len(delivery.sales) > 1
        else []
    )

    line_items = []

    for sale in delivery.sales:
        for item in sale.items:
            line_items.append({
                "product_name": (
                    item.product.name
                    if item.product
                    else f"Product #{item.product_id}"
                ),
                "variant_note": item.variant_note or NA,
                "qty": item.qty,
            })

    order_id = (
        (primary_sale.order_id if primary_sale else None)
        or NA
    )

    barcode_png = (
        generate_barcode_png(order_id)
        if order_id != NA
        else None
    )

    return {
        "settings": settings,
        "delivery": delivery,
        "has_logo": logo_bytes is not None,
        "company_phone": settings.business_phone or NA,
        "company_address": settings.business_address or NA,
        "order_id": order_id,
        "other_order_ids": other_order_ids,
        "date_of_shipment": (
            delivery.shipped_at.strftime("%Y-%m-%d")
            if delivery.shipped_at
            else NA
        ),
        "recipient_name": (
            (primary_sale.customer_name if primary_sale else None)
            or NA
        ),
        "recipient_phone": (
            (primary_sale.customer_phone if primary_sale else None)
            or NA
        ),
        "delivery_address": (
            delivery.delivery_address
            or (
                primary_sale.customer_address
                if primary_sale
                else None
            )
            or NA
        ),
        "weight": (
            f"{delivery.package_weight_kg} kg"
            if delivery.package_weight_kg is not None
            else NA
        ),
        "dimensions": delivery.package_dimensions or NA,
        "remarks": delivery.remarks or NA,
        "line_items": line_items,
        "barcode_png": barcode_png,
    }


def generate_label_pdf(delivery):
    from reportlab.lib.units import mm
    from reportlab.platypus import (
        SimpleDocTemplate,
        Paragraph,
        Table,
        TableStyle,
        Image,
    )
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib import colors
    from reportlab.lib.utils import ImageReader

    ctx = get_label_context(delivery)
    settings = ctx["settings"]

    # ============================================================
    # RESPONSIVE PAGE SIZE
    # ============================================================

    # Paper/label dimensions come directly from Settings.
    width = settings.label_width_mm * mm
    height = settings.label_height_mm * mm

    # Keep a consistent physical border around the label.
    #
    # On extremely small labels, reduce the margin slightly so the
    # border does not consume most of the usable area.
    margin = min(
        5 * mm,
        max(2.5 * mm, width * 0.045),
        max(2.5 * mm, height * 0.045),
    )

    content_width = max(
        width - (2 * margin),
        20 * mm,
    )

    content_height = max(
        height - (2 * margin),
        20 * mm,
    )

    width_mm = width / mm

    # ============================================================
    # RESPONSIVE COLUMN WIDTHS
    # ============================================================

    # Normal labels use 40/60.
    #
    # Narrow labels give the right side slightly more room because
    # addresses, remarks and barcode content benefit from width.
    if width_mm < 60:
        left_ratio = 0.34
    elif width_mm < 80:
        left_ratio = 0.37
    else:
        left_ratio = 0.40

    col_left = content_width * left_ratio
    col_right = content_width - col_left

    # ============================================================
    # RESPONSIVE FONT SIZES
    # ============================================================

    if width_mm < 50:
        section_font = 5.8
        normal_font = 6.7
        recipient_font = 8.5
        order_font = 7.8

    elif width_mm < 65:
        section_font = 6.2
        normal_font = 7.4
        recipient_font = 9.2
        order_font = 8.5

    elif width_mm < 80:
        section_font = 6.6
        normal_font = 8.0
        recipient_font = 10
        order_font = 9.2

    else:
        section_font = 7
        normal_font = 8.5
        recipient_font = 11
        order_font = 10

    # ============================================================
    # PDF DOCUMENT
    # ============================================================

    buf = io.BytesIO()

    doc = SimpleDocTemplate(
        buf,
        pagesize=(width, height),
        leftMargin=margin,
        rightMargin=margin,
        topMargin=margin,
        bottomMargin=margin,
        allowSplitting=0,
    )

    styles = getSampleStyleSheet()

    section_style = ParagraphStyle(
        "section",
        parent=styles["Normal"],
        fontSize=section_font,
        leading=section_font + 1.2,
        textColor=colors.grey,
        spaceAfter=0.5,
        wordWrap="CJK",
    )

    normal_style = ParagraphStyle(
        "normal",
        parent=styles["Normal"],
        fontSize=normal_font,
        leading=normal_font + 2,
        spaceAfter=0,
        wordWrap="CJK",
    )

    recipient_style = ParagraphStyle(
        "recipient",
        parent=styles["Normal"],
        fontSize=recipient_font,
        leading=recipient_font + 2,
        spaceAfter=0,
        wordWrap="CJK",
    )

    order_id_style = ParagraphStyle(
        "orderid",
        parent=styles["Normal"],
        fontSize=order_font,
        leading=order_font + 1.5,
        spaceAfter=0,
        wordWrap="CJK",
    )

    def cell(*flowables):
        return list(flowables)

    # ============================================================
    # LOGO
    # ============================================================

    def logo_flowable():
        logo_bytes, _ = get_logo_bytes()

        if not logo_bytes:
            return Paragraph(NA, normal_style)

        try:
            img_reader = ImageReader(
                io.BytesIO(logo_bytes)
            )

            iw, ih = img_reader.getSize()

            # Scale with the label, but keep a sensible maximum.
            max_h = min(
                content_height * 0.10,
                16 * mm,
            )

            max_w = max(
                col_left - 4 * mm,
                8 * mm,
            )

            scale = min(
                max_w / iw,
                max_h / ih,
            )

            img = Image(
                io.BytesIO(logo_bytes),
                width=iw * scale,
                height=ih * scale,
            )

            img.hAlign = "LEFT"

            return img

        except Exception:
            return Paragraph(NA, normal_style)

    # ============================================================
    # BARCODE
    # ============================================================

    def barcode_flowable():
        if not ctx["barcode_png"]:
            return Paragraph(NA, normal_style)

        try:
            bc_reader = ImageReader(
                io.BytesIO(ctx["barcode_png"])
            )

            biw, bih = bc_reader.getSize()

            # Keep barcode safely within its cell.
            max_h = min(
                content_height * 0.12,
                22 * mm,
            )

            max_w = max(
                col_right - 6 * mm,
                10 * mm,
            )

            scale = min(
                max_w / biw,
                max_h / bih,
            )

            img = Image(
                io.BytesIO(ctx["barcode_png"]),
                width=biw * scale,
                height=bih * scale,
            )

            img.hAlign = "CENTER"

            return img

        except Exception:
            return Paragraph(NA, normal_style)

    # ============================================================
    # ORDER ID
    # ============================================================

    order_id_cell = [
        Paragraph(
            "ORDER ID",
            section_style,
        ),
        Paragraph(
            ctx["order_id"],
            order_id_style,
        ),
    ]

    if ctx["other_order_ids"]:
        order_id_cell.append(
            Paragraph(
                "Also: " + ", ".join(ctx["other_order_ids"]),
                normal_style,
            )
        )

    # ============================================================
    # LABEL CONTENT
    # ============================================================

    table_data = [
        [
            cell(
                logo_flowable()
            ),
            cell(
                Paragraph(
                    "FROM",
                    section_style,
                ),
                Paragraph(
                    f"Tel: {ctx['company_phone']}",
                    normal_style,
                ),
                Paragraph(
                    ctx["company_address"],
                    normal_style,
                ),
            ),
        ],
        [
            cell(
                Paragraph(
                    "TO",
                    section_style,
                )
            ),
            cell(
                Paragraph(
                    ctx["recipient_name"],
                    recipient_style,
                ),
                Paragraph(
                    ctx["recipient_phone"],
                    normal_style,
                ),
                Paragraph(
                    ctx["delivery_address"],
                    normal_style,
                ),
            ),
        ],
        [
            cell(
                Paragraph(
                    "WEIGHT",
                    section_style,
                ),
                Paragraph(
                    ctx["weight"],
                    normal_style,
                ),
            ),
            cell(
                Paragraph(
                    "DIMENSIONS",
                    section_style,
                ),
                Paragraph(
                    ctx["dimensions"],
                    normal_style,
                ),
            ),
        ],
        [
            cell(
                Paragraph(
                    "DATE OF SHIPMENT",
                    section_style,
                ),
                Paragraph(
                    ctx["date_of_shipment"],
                    normal_style,
                ),
            ),
            cell(
                Paragraph(
                    "REMARKS",
                    section_style,
                ),
                Paragraph(
                    ctx["remarks"],
                    normal_style,
                ),
            ),
        ],
        [
            order_id_cell,
            cell(
                barcode_flowable()
            ),
        ],
    ]

    # ============================================================
    # RESPONSIVE TABLE
    # ============================================================
    #
    # We intentionally do NOT force fixed row heights immediately.
    #
    # ReportLab first calculates the minimum height required by the
    # actual content. This is important for narrow labels where a
    # long address or remark may require additional vertical space.
    #
    # After the minimum height is known, any remaining vertical space
    # is distributed across the rows so larger labels use their full
    # printable area.
    # ============================================================

    grid = Table(
        table_data,
        colWidths=[
            col_left,
            col_right,
        ],
        hAlign="LEFT",
        splitByRow=0,
    )

    grid.setStyle(
        TableStyle([
            (
                "GRID",
                (0, 0),
                (-1, -1),
                0.75,
                colors.HexColor("#666666"),
            ),

            (
                "VALIGN",
                (0, 0),
                (-1, -1),
                "MIDDLE",
            ),

            (
                "LEFTPADDING",
                (0, 0),
                (-1, -1),
                3,
            ),

            (
                "RIGHTPADDING",
                (0, 0),
                (-1, -1),
                3,
            ),

            (
                "TOPPADDING",
                (0, 0),
                (-1, -1),
                2,
            ),

            (
                "BOTTOMPADDING",
                (0, 0),
                (-1, -1),
                2,
            ),

            (
                "WORDWRAP",
                (0, 0),
                (-1, -1),
                "CJK",
            ),
        ])
    )

    # ============================================================
    # CALCULATE NATURAL CONTENT HEIGHT
    # ============================================================

    _, natural_height = grid.wrap(
        content_width,
        content_height,
    )

    # ============================================================
    # FILL UNUSED VERTICAL SPACE
    # ============================================================
    #
    # If the content naturally occupies less than the printable
    # height, distribute the remaining space according to the
    # intended visual proportions.
    #
    # If the content already needs most/all of the available height,
    # no forced height is applied. This protects narrow labels from
    # clipping.
    # ============================================================

    if natural_height < content_height:
        extra_height = content_height - natural_height

        row_weights = [
            0.20,  # FROM / logo
            0.25,  # TO / recipient
            0.15,  # Weight / dimensions
            0.15,  # Date / remarks
            0.25,  # Order ID / barcode
        ]

        current_row_heights = getattr(
            grid,
            "_rowHeights",
            None,
        )

        if (
            current_row_heights
            and len(current_row_heights) == len(row_weights)
            and all(
                row_height is not None
                for row_height in current_row_heights
            )
        ):
            final_row_heights = [
                row_height + (extra_height * weight)
                for row_height, weight in zip(
                    current_row_heights,
                    row_weights,
                )
            ]

            # ReportLab has already calculated these row heights during
            # wrap(). Updating them here lets the table occupy the full
            # printable area without changing the natural minimum size.
            grid._argH = final_row_heights
            grid._rowHeights = final_row_heights

    # ============================================================
    # BUILD PDF
    # ============================================================

    doc.build([grid])

    buf.seek(0)

    return buf
```
