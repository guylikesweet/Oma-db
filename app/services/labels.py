"""
Shipping label generation — one label per Delivery (one per physical
parcel), even when it consolidates multiple sales for the same customer.

The label size is taken directly from Settings.

The PDF is drawn directly onto the configured page size so that:
- the entire configured paper area is used;
- narrow labels do not overflow;
- long addresses/remarks wrap safely;
- the repository logo is embedded correctly;
- the barcode stays inside its cell;
- no accidental second page is created.
"""

import io
import os

from app.services.settings import get_settings
from app.services.barcodes import generate_barcode_png

NA = "N/A"


# ================================================================
# LOGO
# ================================================================
#
# The logo is stored in the repository at:
#
#     app/static/logo.png
#
# This is the same source used by the delivery label HTML.
#

STATIC_LOGO_PATH = os.path.join(
    os.path.dirname(os.path.dirname(__file__)),
    "static",
    "logo.png",
)


def get_logo_bytes():
    """
    Load the delivery logo directly from the repository's
    static/logo.png file.

    This intentionally uses the same logo source as the
    delivery label HTML instead of relying on a database/
    Settings logo.
    """

    if not os.path.exists(STATIC_LOGO_PATH):
        return None, None

    try:
        with open(STATIC_LOGO_PATH, "rb") as f:
            logo_bytes = f.read()

        if not logo_bytes:
            return None, None

        return logo_bytes, "image/png"

    except (OSError, IOError):
        return None, None


# ================================================================
# LABEL READY
# ================================================================

def label_ready(delivery):
    """
    Weight and dimensions must be captured before a label
    can be generated.
    """

    return (
        delivery.package_weight_kg is not None
        and bool(delivery.package_dimensions)
    )


# ================================================================
# LABEL CONTEXT
# ================================================================

def get_label_context(delivery):
    """
    Data needed to render a label.

    The first sale is used as the primary order/tracking
    reference. Additional consolidated orders are listed
    separately.
    """

    settings = get_settings()

    logo_bytes, _ = get_logo_bytes()

    primary_sale = (
        delivery.sales[0]
        if delivery.sales
        else None
    )

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
                "variant_note": (
                    item.variant_note
                    or NA
                ),
                "qty": item.qty,
            })

    order_id = (
        (
            primary_sale.order_id
            if primary_sale
            else None
        )
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

        "company_phone": (
            settings.business_phone
            or NA
        ),

        "company_address": (
            settings.business_address
            or NA
        ),

        "order_id": order_id,

        "other_order_ids": other_order_ids,

        "date_of_shipment": (
            delivery.shipped_at.strftime("%Y-%m-%d")
            if delivery.shipped_at
            else NA
        ),

        "recipient_name": (
            (
                primary_sale.customer_name
                if primary_sale
                else None
            )
            or NA
        ),

        "recipient_phone": (
            (
                primary_sale.customer_phone
                if primary_sale
                else None
            )
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

        "dimensions": (
            delivery.package_dimensions
            or NA
        ),

        "remarks": (
            delivery.remarks
            or NA
        ),

        "line_items": line_items,

        "barcode_png": barcode_png,
    }


# ================================================================
# PDF GENERATION
# ================================================================

def generate_label_pdf(delivery):
    """
    Generate a single-page PDF label.

    The page dimensions come directly from Settings.
    """

    from reportlab.pdfgen import canvas
    from reportlab.lib.units import mm
    from reportlab.lib import colors
    from reportlab.lib.utils import ImageReader

    ctx = get_label_context(delivery)
    settings = ctx["settings"]

    # ============================================================
    # PAGE SIZE
    # ============================================================

    width = float(
        settings.label_width_mm
    ) * mm

    height = float(
        settings.label_height_mm
    ) * mm

    # ============================================================
    # OUTER MARGIN
    # ============================================================

    margin = min(
        5 * mm,
        width * 0.045,
        height * 0.045,
    )

    margin = max(
        2.5 * mm,
        margin,
    )

    content_left = margin
    content_bottom = margin

    content_width = (
        width - (2 * margin)
    )

    content_height = (
        height - (2 * margin)
    )

    width_mm = width / mm

    # ============================================================
    # RESPONSIVE COLUMN WIDTHS
    # ============================================================

    if width_mm < 60:

        left_ratio = 0.34

    elif width_mm < 80:

        left_ratio = 0.37

    else:

        left_ratio = 0.40

    col_left = (
        content_width * left_ratio
    )

    col_right = (
        content_width - col_left
    )

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
    # CREATE PDF
    # ============================================================

    buf = io.BytesIO()

    pdf = canvas.Canvas(
        buf,
        pagesize=(width, height),
    )

    # ============================================================
    # TEXT HELPERS
    # ============================================================

    def safe_text(value):

        if value is None:
            return NA

        value = str(value).strip()

        return value or NA

    def wrap_text(
        text,
        font_name,
        font_size,
        max_width,
    ):
        """
        Wrap text based on the actual PDF width.

        Handles both normal sentences and very long strings
        such as addresses, phone numbers and IDs.
        """

        text = safe_text(text)

        if not text:
            return [NA]

        words = text.split()

        if not words:
            return [NA]

        lines = []

        current = ""

        for word in words:

            candidate = (
                word
                if not current
                else current + " " + word
            )

            if pdf.stringWidth(
                candidate,
                font_name,
                font_size,
            ) <= max_width:

                current = candidate

                continue

            if current:

                lines.append(current)

            # Handle a single word that is too wide.
            if pdf.stringWidth(
                word,
                font_name,
                font_size,
            ) <= max_width:

                current = word

                continue

            chunk = ""

            for char in word:

                candidate_chunk = (
                    chunk + char
                )

                if pdf.stringWidth(
                    candidate_chunk,
                    font_name,
                    font_size,
                ) <= max_width:

                    chunk = candidate_chunk

                else:

                    if chunk:
                        lines.append(chunk)

                    chunk = char

            current = chunk

        if current:
            lines.append(current)

        return lines or [NA]

    def draw_text(
        text,
        x,
        y,
        max_width,
        font_size,
        leading=None,
        bold=False,
        max_lines=None,
    ):
        """
        Draw wrapped text and return the resulting y position.
        """

        if leading is None:
            leading = font_size * 1.25

        font_name = (
            "Helvetica-Bold"
            if bold
            else "Helvetica"
        )

        lines = wrap_text(
            text,
            font_name,
            font_size,
            max_width,
        )

        if max_lines is not None:

            lines = lines[:max_lines]

        pdf.setFont(
            font_name,
            font_size,
        )

        for line in lines:

            pdf.drawString(
                x,
                y,
                line,
            )

            y -= leading

        return y

    def draw_section_label(
        text,
        x,
        y,
        max_width,
    ):
        pdf.setFillColor(
            colors.HexColor("#888888")
        )

        y = draw_text(
            text.upper(),
            x,
            y,
            max_width,
            section_font,
            leading=section_font + 1.2,
            bold=False,
            max_lines=2,
        )

        pdf.setFillColor(
            colors.black
        )

        return y

    # ============================================================
    # ROW HEIGHTS
    # ============================================================
    #
    # These weights make the label use the complete configured
    # paper height.
    #

    row_weights = [
        0.20,  # FROM / LOGO
        0.25,  # TO / RECIPIENT
        0.15,  # WEIGHT / DIMENSIONS
        0.15,  # DATE / REMARKS
        0.25,  # ORDER / BARCODE
    ]

    row_heights = [
        content_height * weight
        for weight in row_weights
    ]

    # ============================================================
    # OUTER BORDER
    # ============================================================

    pdf.setStrokeColor(
        colors.HexColor("#333333")
    )

    pdf.setLineWidth(1)

    pdf.roundRect(
        margin,
        margin,
        content_width,
        content_height,
        3 * mm,
        stroke=1,
        fill=0,
    )

    # ============================================================
    # ROW 1
    # LOGO | FROM
    # ============================================================

    row_top = (
        content_bottom
        + content_height
    )

    row_height = row_heights[0]

    row_bottom = (
        row_top - row_height
    )

    right_x = (
        content_left
        + col_left
    )

    # Horizontal separator.
    pdf.setStrokeColor(
        colors.HexColor("#999999")
    )

    pdf.setLineWidth(0.75)

    pdf.line(
        content_left,
        row_bottom,
        content_left + content_width,
        row_bottom,
    )

    # Vertical separator.
    pdf.line(
        right_x,
        row_bottom,
        right_x,
        row_top,
    )

    pad_x = min(
        2.5 * mm,
        col_left * 0.08,
    )

    pad_y = min(
        2.2 * mm,
        row_height * 0.08,
    )

    # ------------------------------------------------------------
    # LOGO
    # ------------------------------------------------------------

    logo_bytes, _ = get_logo_bytes()

    if logo_bytes:

        try:

            logo_reader = ImageReader(
                io.BytesIO(logo_bytes)
            )

            logo_w, logo_h = (
                logo_reader.getSize()
            )

            max_logo_w = max(
                col_left - (2 * pad_x),
                5 * mm,
            )

            max_logo_h = min(
                row_height - (2 * pad_y),
                16 * mm,
            )

            scale = min(
                max_logo_w / logo_w,
                max_logo_h / logo_h,
            )

            if scale > 0:

                final_w = (
                    logo_w * scale
                )

                final_h = (
                    logo_h * scale
                )

                logo_x = (
                    content_left
                    + pad_x
                )

                logo_y = (
                    row_bottom
                    + (
                        row_height
                        - final_h
                    ) / 2
                )

                pdf.drawImage(
                    logo_reader,
                    logo_x,
                    logo_y,
                    width=final_w,
                    height=final_h,
                    preserveAspectRatio=True,
                    mask="auto",
                )

        except Exception:

            pdf.setFont(
                "Helvetica",
                normal_font,
            )

            pdf.drawString(
                content_left + pad_x,
                row_bottom
                + row_height / 2,
                NA,
            )

    else:

        pdf.setFont(
            "Helvetica",
            normal_font,
        )

        pdf.drawString(
            content_left + pad_x,
            row_bottom
            + row_height / 2,
            NA,
        )

    # ------------------------------------------------------------
    # FROM
    # ------------------------------------------------------------

    text_x = (
        right_x + pad_x
    )

    text_width = (
        col_right
        - (2 * pad_x)
    )

    text_y = (
        row_top
        - pad_y
        - section_font
    )

    text_y = draw_section_label(
        "From",
        text_x,
        text_y,
        text_width,
    )

    text_y -= 1.5

    text_y = draw_text(
        f"Tel: {safe_text(ctx['company_phone'])}",
        text_x,
        text_y,
        text_width,
        normal_font,
        max_lines=2,
    )

    text_y -= 1

    draw_text(
        ctx["company_address"],
        text_x,
        text_y,
        text_width,
        normal_font,
        max_lines=5,
    )

    # ============================================================
    # ROW 2
    # TO | RECIPIENT
    # ============================================================

    row_top = row_bottom

    row_height = row_heights[1]

    row_bottom = (
        row_top - row_height
    )

    right_x = (
        content_left
        + col_left
    )

    pdf.setStrokeColor(
        colors.HexColor("#999999")
    )

    pdf.line(
        content_left,
        row_bottom,
        content_left + content_width,
        row_bottom,
    )

    pdf.line(
        right_x,
        row_bottom,
        right_x,
        row_top,
    )

    pad_x = min(
        2.5 * mm,
        col_left * 0.08,
    )

    pad_y = min(
        2.2 * mm,
        row_height * 0.08,
    )

    # ------------------------------------------------------------
    # TO
    # ------------------------------------------------------------

    text_x = (
        content_left + pad_x
    )

    text_y = (
        row_top
        - pad_y
        - section_font
    )

    draw_section_label(
        "To",
        text_x,
        text_y,
        col_left - (2 * pad_x),
    )

    # ------------------------------------------------------------
    # RECIPIENT
    # ------------------------------------------------------------

    text_x = (
        right_x + pad_x
    )

    text_width = (
        col_right
        - (2 * pad_x)
    )

    text_y = (
        row_top
        - pad_y
        - recipient_font
    )

    text_y = draw_text(
        ctx["recipient_name"],
        text_x,
        text_y,
        text_width,
        recipient_font,
        leading=recipient_font + 2,
        bold=True,
        max_lines=2,
    )

    text_y -= 1

    text_y = draw_text(
        ctx["recipient_phone"],
        text_x,
        text_y,
        text_width,
        normal_font,
        max_lines=2,
    )

    text_y -= 1

    draw_text(
        ctx["delivery_address"],
        text_x,
        text_y,
        text_width,
        normal_font,
        max_lines=6,
    )

    # ============================================================
    # ROW 3
    # WEIGHT | DIMENSIONS
    # ============================================================

    row_top = row_bottom

    row_height = row_heights[2]

    row_bottom = (
        row_top - row_height
    )

    middle_x = (
        content_left
        + content_width / 2
    )

    pdf.setStrokeColor(
        colors.HexColor("#999999")
    )

    pdf.line(
        content_left,
        row_bottom,
        content_left + content_width,
        row_bottom,
    )

    pdf.line(
        middle_x,
        row_bottom,
        middle_x,
        row_top,
    )

    pad_x = 2.5 * mm
    pad_y = 2.2 * mm

    half_width = (
        content_width / 2
    )

    # ------------------------------------------------------------
    # WEIGHT
    # ------------------------------------------------------------

    text_x = (
        content_left + pad_x
    )

    text_y = (
        row_top
        - pad_y
        - section_font
    )

    text_y = draw_section_label(
        "Weight",
        text_x,
        text_y,
        half_width - (2 * pad_x),
    )

    draw_text(
        ctx["weight"],
        text_x,
        text_y - 1,
        half_width - (2 * pad_x),
        normal_font,
        max_lines=2,
    )

    # ------------------------------------------------------------
    # DIMENSIONS
    # ------------------------------------------------------------

    text_x = (
        middle_x + pad_x
    )

    text_y = (
        row_top
        - pad_y
        - section_font
    )

    text_y = draw_section_label(
        "Dimensions",
        text_x,
        text_y,
        half_width - (2 * pad_x),
    )

    draw_text(
        ctx["dimensions"],
        text_x,
        text_y - 1,
        half_width - (2 * pad_x),
        normal_font,
        max_lines=2,
    )

    # ============================================================
    # ROW 4
    # DATE | REMARKS
    # ============================================================

    row_top = row_bottom

    row_height = row_heights[3]

    row_bottom = (
        row_top - row_height
    )

    middle_x = (
        content_left
        + content_width / 2
    )

    pdf.setStrokeColor(
        colors.HexColor("#999999")
    )

    pdf.line(
        content_left,
        row_bottom,
        content_left + content_width,
        row_bottom,
    )

    pdf.line(
        middle_x,
        row_bottom,
        middle_x,
        row_top,
    )

    # ------------------------------------------------------------
    # DATE
    # ------------------------------------------------------------

    text_x = (
        content_left + pad_x
    )

    text_y = (
        row_top
        - pad_y
        - section_font
    )

    text_y = draw_section_label(
        "Date of Shipment",
        text_x,
        text_y,
        half_width - (2 * pad_x),
    )

    draw_text(
        ctx["date_of_shipment"],
        text_x,
        text_y - 1,
        half_width - (2 * pad_x),
        normal_font,
        max_lines=2,
    )

    # ------------------------------------------------------------
    # REMARKS
    # ------------------------------------------------------------

    text_x = (
        middle_x + pad_x
    )

    text_y = (
        row_top
        - pad_y
        - section_font
    )

    text_y = draw_section_label(
        "Remarks",
        text_x,
        text_y,
        half_width - (2 * pad_x),
    )

    draw_text(
        ctx["remarks"],
        text_x,
        text_y - 1,
        half_width - (2 * pad_x),
        normal_font,
        max_lines=5,
    )

    # ============================================================
    # ROW 5
    # ORDER ID | BARCODE
    # ============================================================

    row_top = row_bottom

    row_height = row_heights[4]

    row_bottom = (
        row_top - row_height
    )

    middle_x = (
        content_left
        + col_left
    )

    pdf.setStrokeColor(
        colors.HexColor("#999999")
    )

    pdf.line(
        middle_x,
        row_bottom,
        middle_x,
        row_top,
    )

    pad_x = min(
        2.5 * mm,
        col_left * 0.08,
    )

    pad_y = min(
        2.2 * mm,
        row_height * 0.08,
    )

    # ------------------------------------------------------------
    # ORDER ID
    # ------------------------------------------------------------

    text_x = (
        content_left + pad_x
    )

    text_width = (
        col_left
        - (2 * pad_x)
    )

    text_y = (
        row_top
        - pad_y
        - section_font
    )

    text_y = draw_section_label(
        "Order ID",
        text_x,
        text_y,
        text_width,
    )

    text_y -= 1

    text_y = draw_text(
        ctx["order_id"],
        text_x,
        text_y,
        text_width,
        order_font,
        leading=order_font + 1.5,
        bold=True,
        max_lines=3,
    )

    if ctx["other_order_ids"]:

        text_y -= 2

        draw_text(
            "Also: "
            + ", ".join(
                ctx["other_order_ids"]
            ),
            text_x,
            text_y,
            text_width,
            normal_font,
            max_lines=4,
        )

    # ------------------------------------------------------------
    # BARCODE
    # ------------------------------------------------------------

    if ctx["barcode_png"]:

        try:

            barcode_reader = ImageReader(
                io.BytesIO(
                    ctx["barcode_png"]
                )
            )

            barcode_w, barcode_h = (
                barcode_reader.getSize()
            )

            barcode_cell_x = middle_x

            barcode_cell_width = (
                col_right
            )

            max_barcode_w = max(
                barcode_cell_width
                - (2 * pad_x),
                10 * mm,
            )

            max_barcode_h = min(
                row_height
                - (2 * pad_y),
                22 * mm,
            )

            scale = min(
                max_barcode_w / barcode_w,
                max_barcode_h / barcode_h,
            )

            if scale > 0:

                final_w = (
                    barcode_w * scale
                )

                final_h = (
                    barcode_h * scale
                )

                barcode_x = (
                    barcode_cell_x
                    + (
                        barcode_cell_width
                        - final_w
                    ) / 2
                )

                barcode_y = (
                    row_bottom
                    + (
                        row_height
                        - final_h
                    ) / 2
                )

                pdf.drawImage(
                    barcode_reader,
                    barcode_x,
                    barcode_y,
                    width=final_w,
                    height=final_h,
                    preserveAspectRatio=True,
                    mask="auto",
                )

        except Exception:
            # A barcode failure should never prevent the
            # label itself from being generated.
            pass

    # ============================================================
    # FINISH PDF
    # ============================================================

    pdf.showPage()
    pdf.save()

    buf.seek(0)

    return buf
