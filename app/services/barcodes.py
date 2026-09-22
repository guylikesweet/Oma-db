"""
Barcode generation — Code128, encoding the order ID (which also serves as
the tracking number). Returns PNG bytes, embeddable in both the print-HTML
label (as a data URI) and the PDF (as a reportlab Image).
"""
import io

from barcode import Code128
from barcode.writer import ImageWriter


def generate_barcode_png(value):
    buf = io.BytesIO()
    writer = ImageWriter()
    writer.set_options({
        "module_height": 12.0,
        "font_size": 8,
        "text_distance": 3,
        "quiet_zone": 2,
        "write_text": True,
    })
    Code128(value, writer=writer).write(buf)
    buf.seek(0)
    return buf.read()
