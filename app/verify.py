"""
Public invoice verification (no login) — reached by scanning the QR code on
an invoice/receipt. It looks the sale up by order ID, recomputes the HMAC
signature from the server's record and compares it with the one on the
customer's document. Only what a customer needs to check an invoice is shown
(first name, items, amount) — never phone or address.
"""
import base64
import re

from flask import Blueprint, render_template_string

from app.models import Sale
from app.services.invoices import signature_matches
from app.services.labels import get_logo_bytes
from app.services.settings import get_settings

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
 .brand{text-align:center;margin-bottom:10px}
 .brand img{max-height:64px;max-width:200px}
 .brand div{font-weight:600;margin-top:4px}
 .wa{position:fixed;right:18px;bottom:18px;z-index:20;display:flex;flex-direction:column;align-items:flex-end;text-decoration:none}
 .wa-btn{width:58px;height:58px;border-radius:50%;background:#25d366;display:flex;align-items:center;justify-content:center;box-shadow:0 3px 10px #0004;animation:pulse 2.2s infinite}
 .wa-btn svg{width:32px;height:32px;fill:#fff}
 .wa-bubble{position:relative;background:#fff;color:#222;font-size:13px;line-height:1.35;padding:9px 12px;border-radius:12px;box-shadow:0 2px 10px #0003;max-width:210px;margin-bottom:10px;animation:pop .5s ease-out both,bob 3s ease-in-out 1s infinite}
 .wa-bubble:after{content:"";position:absolute;right:22px;bottom:-7px;width:14px;height:14px;background:#fff;transform:rotate(45deg);box-shadow:3px 3px 5px #0001}
 .wa-bubble b{color:#128c7e}
 .wa-close{position:absolute;top:-8px;left:-8px;width:20px;height:20px;border-radius:50%;background:#666;color:#fff;font-size:13px;line-height:20px;text-align:center;border:0;padding:0;cursor:pointer}
 @keyframes pulse{0%{box-shadow:0 0 0 0 #25d36699,0 3px 10px #0004}70%{box-shadow:0 0 0 14px #25d36600,0 3px 10px #0004}100%{box-shadow:0 0 0 0 #25d36600,0 3px 10px #0004}}
 @keyframes pop{from{opacity:0;transform:translateY(8px) scale(.9)}to{opacity:1;transform:none}}
 @keyframes bob{0%,100%{transform:translateY(0)}50%{transform:translateY(-4px)}}
 body{padding-bottom:110px}
</style></head><body><div class="card">
{% if state == 'valid' and (logo_uri or business_name) %}
 <div class="brand">{% if logo_uri %}<img src="{{ logo_uri }}" alt="{{ business_name or 'Company logo' }}">{% endif %}
 {% if business_name %}<div>{{ business_name }}</div>{% endif %}</div>
{% endif %}
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
 <tr><th colspan="2">Total paid (products only)</th><th class="n">{{ '{:,.2f}'.format(sale.subtotal_amount or 0) }}</th></tr></table>
 <p class="muted">Compare these details with the invoice you were given.</p>
{% elif state == 'changed' %}
 <h1 class="bad">&#10008; Invoice does not match</h1>
 <p>The verification code is not valid for this order's current record. The invoice may have been altered, or the order was edited after it was issued. Please contact the seller.</p>
{% else %}
 <h1 class="bad">&#10008; Invoice not found</h1>
 <p>No order with this reference exists. Do not trust this invoice.</p>
{% endif %}
</div>
{% if wa_number %}
<a class="wa" id="wa" href="https://wa.me/{{ wa_number }}?text={{ wa_text | urlencode }}" target="_blank" rel="noopener" aria-label="Chat with us on WhatsApp">
 <div class="wa-bubble" id="wa-bubble"><button type="button" class="wa-close" aria-label="Dismiss" onclick="event.preventDefault();event.stopPropagation();document.getElementById('wa-bubble').style.display='none'">&times;</button>
 Need a follow up on your order? <b>Chat with us</b></div>
 <div class="wa-btn"><svg viewBox="0 0 32 32"><path d="M16.04 3C9.4 3 4 8.4 4 15.04c0 2.12.55 4.19 1.6 6.01L4 29l8.13-1.57a12 12 0 0 0 3.9.65h.01C22.68 28.08 28 22.68 28 16.04 28 9.4 22.68 3 16.04 3zm0 22.04h-.01a10 10 0 0 1-5.1-1.4l-.37-.22-4.83.93.96-4.7-.24-.38a9.96 9.96 0 0 1-1.53-5.23c0-5.5 4.48-9.98 9.99-9.98a9.9 9.9 0 0 1 7.06 2.93 9.9 9.9 0 0 1 2.92 7.06c0 5.51-4.49 9.99-9.85 9.99zm5.47-7.48c-.3-.15-1.77-.87-2.04-.97-.27-.1-.47-.15-.67.15-.2.3-.77.97-.94 1.17-.17.2-.35.22-.65.07-.3-.15-1.27-.47-2.42-1.49-.9-.8-1.5-1.79-1.67-2.09-.17-.3-.02-.46.13-.61.14-.13.3-.35.45-.52.15-.17.2-.3.3-.5.1-.2.05-.37-.02-.52-.07-.15-.67-1.62-.92-2.22-.24-.58-.49-.5-.67-.51h-.57c-.2 0-.52.07-.8.37-.27.3-1.04 1.02-1.04 2.48 0 1.46 1.07 2.88 1.22 3.08.15.2 2.1 3.2 5.08 4.49.71.31 1.26.49 1.7.63.71.23 1.36.2 1.87.12.57-.09 1.77-.72 2.02-1.42.25-.7.25-1.29.17-1.42-.07-.12-.27-.2-.57-.35z"/></svg></div>
</a>
{% endif %}
</body></html>"""


def _logo_uri():
    data, mimetype = get_logo_bytes()
    if not data:
        return None
    return f"data:{mimetype or 'image/png'};base64," + base64.b64encode(data).decode()


def _wa_number(phone):
    """Digits-only international number for wa.me. A leading 0 is treated as a
    Nigerian local number (0803... -> 234803...); numbers already in
    international form (+234... / 234...) are kept as they are."""
    digits = re.sub(r"\D", "", phone or "")
    if not digits:
        return None
    if digits.startswith("00"):
        digits = digits[2:]
    elif digits.startswith("0"):
        digits = "234" + digits[1:]
    return digits if len(digits) >= 10 else None


def _brand_context(sale=None):
    settings = get_settings()
    order = f" (order {sale.order_id})" if sale is not None and sale.order_id else ""
    return {
        "logo_uri": _logo_uri(),
        "business_name": settings.business_name or "",
        "wa_number": _wa_number(settings.business_phone),
        "wa_text": f"Hello, I'd like a follow up on my order{order}.",
    }


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
        return render_template_string(PAGE, state="missing", **_brand_context()), 404
    if not signature_matches(sale, sig.replace("-", "")):
        return render_template_string(PAGE, state="changed", **_brand_context()), 200
    return render_template_string(PAGE, state="valid", sale=sale, name=_mask(sale.customer_name), **_brand_context(sale))
