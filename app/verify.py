"""
Public invoice verification (no login) — reached by scanning the QR code on
an invoice/receipt. It looks the sale up by order ID, recomputes the HMAC
signature from the server's record and compares it with the one on the
customer's document. Only what a customer needs to check an invoice is shown
(first name, items, amount) — never phone or address.
"""
from flask import Blueprint, render_template_string

from app.models import Sale
from app.services.invoices import signature_matches

verify_bp = Blueprint("verify", __name__)

PAGE = """<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Invoice verification</title>
<style>
 body{font-family:system-ui,sans-serif;background:#f4f4f4;margin:0;padding:16px}
 .card{max-width:520px;margin:24px auto;background:#fff;border-radius:10px;padding:20px;box-shadow:0 1px 6px #0002}
 .ok{color:#137333}.bad{color:#b3261e}
 h1{font-size:20px;margin:0 0 8px}
 table{width:100%;border-collapse:collapse;margin-top:12px;font-size:14px}
 td,th{padding:6px 4px;border-bottom:1px solid #eee;text-align:left}
 td.n,th.n{text-align:right}
 .muted{color:#777;font-size:12px;margin-top:14px}
</style></head><body><div class="card">
{% if state == 'valid' %}
 <h1 class="ok">&#10004; Authentic invoice</h1>
 <p>This invoice matches our records.</p>
 <p><b>Order:</b> {{ sale.order_id }}<br>
 <b>Date:</b> {{ sale.sale_date }}<br>
 <b>Customer:</b> {{ name }}<br>
 <b>Payment status:</b> {{ sale.payment_status }}</p>
 <table><tr><th>Item</th><th class="n">Qty</th><th class="n">Price</th></tr>
 {% for it in sale.items %}
  <tr><td>{{ it.product.name if it.product else 'Item' }}{% if it.variant_note %} ({{ it.variant_note }}){% endif %}</td>
  <td class="n">{{ it.qty }}</td><td class="n">{{ '{:,.2f}'.format(it.unit_price or 0) }}</td></tr>
 {% endfor %}
 <tr><th colspan="2">Total paid (products only)</th><th class="n">{{ '{:,.2f}'.format(sale.total_amount or 0) }}</th></tr></table>
 <p class="muted">Compare these details with the invoice you were given.</p>
{% elif state == 'changed' %}
 <h1 class="bad">&#10008; Invoice does not match</h1>
 <p>The verification code is not valid for this order's current record. The invoice may have been altered, or the order was edited after it was issued. Please contact the seller.</p>
{% else %}
 <h1 class="bad">&#10008; Invoice not found</h1>
 <p>No order with this reference exists. Do not trust this invoice.</p>
{% endif %}
</div></body></html>"""


def _mask(name):
    parts = (name or "").split()
    if not parts:
        return "-"
    return " ".join([parts[0]] + [p[0] + "***" for p in parts[1:]])


@verify_bp.route("/verify/<order_id>/<sig>")
def verify(order_id, sig):
    sale = Sale.query.filter_by(order_id=order_id).first()
    if sale is None and order_id.isdigit():
        sale = Sale.query.get(int(order_id))
    if sale is None:
        return render_template_string(PAGE, state="missing"), 404
    if not signature_matches(sale, sig.replace("-", "")):
        return render_template_string(PAGE, state="changed"), 200
    return render_template_string(PAGE, state="valid", sale=sale, name=_mask(sale.customer_name))
