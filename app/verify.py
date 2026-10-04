"""
Public invoice verification (no login) — reached by scanning the QR code on
an invoice/receipt. It looks the sale up by order ID, recomputes the HMAC
signature from the server's record and compares it with the one on the
customer's document. Only what a customer needs to check an invoice is shown
(first name, items, amount) — never phone or address.
"""
import base64
import re

from flask import Blueprint, render_template_string, request, redirect

from app.models import Sale
from app.services.invoices import signature_matches
from app.services.labels import get_logo_bytes
from app.services.settings import get_settings
from app.services.journey import journey_for

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



TRACKING_PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>Order tracking</title>
<style>
:root{--track-bg:#f5f7f9;--track-card:#fff;--track-ink:#17212b;--track-muted:#667085;--track-line:#e5e7eb;--track-orange:#fc4300;--track-green:#039664}
body{background:var(--track-bg)!important;color:var(--track-ink);font-family:Inter,system-ui,-apple-system,"Segoe UI",sans-serif}.card{max-width:700px;margin:28px auto;background:var(--track-card);border:1px solid var(--track-line);border-radius:18px;padding:26px;box-shadow:0 8px 30px rgba(16,24,40,.08)}.brand{text-align:center;margin-bottom:20px}.brand img{max-height:58px;max-width:200px;object-fit:contain}.brand div{font-weight:800;font-size:16px;margin-top:7px}h1{font-size:27px;line-height:1.15;margin:4px 0 5px}.muted{color:var(--track-muted);font-size:13px}.verify{padding:12px 14px;border-radius:10px;background:#eaf8f2;color:#027a52;margin:15px 0}.mode{display:inline-block;margin:12px 0;padding:6px 10px;border-radius:999px;background:#fff1eb;color:#c93b08;font-weight:800;font-size:12px}.tracking-current{margin:16px 0 20px;padding:15px;border:1px solid #dfe9e5;border-radius:12px;background:#f7fcfa}.tracking-current b{font-size:15px}.tracking-progress{height:8px;background:#e9edf0;border-radius:99px;overflow:hidden;margin-top:12px}.tracking-progress span{display:block;height:100%;background:var(--track-green);width:{{ ((journey.steps|selectattr('state','in',['done','current','final'])|list|length/(journey.steps|length or 1))*100)|round(0) }}%}.steps{list-style:none;padding:0;margin:20px 0}.step{display:flex;gap:13px;padding:14px 0;border-bottom:1px solid var(--track-line);position:relative}.step:last-child{border-bottom:0}.dot{width:13px;height:13px;border-radius:50%;background:#cfd5dc;margin-top:4px;flex:none;box-shadow:0 0 0 1px #cfd5dc}.done .dot{background:var(--track-green);box-shadow:0 0 0 1px var(--track-green)}.current .dot,.final .dot{background:var(--track-orange);box-shadow:0 0 0 1px var(--track-orange)}.current strong,.final strong{color:var(--track-orange)}.date{font-size:11px;color:#98a2b3;margin-top:4px}.items{border-top:0;margin-top:18px;padding-top:18px}.item{display:flex;justify-content:space-between;gap:15px;padding:11px 0;border-bottom:1px solid var(--track-line);font-size:13px}.footer{margin-top:18px;font-size:12px;color:var(--track-muted);text-align:center;line-height:1.5}@media(max-width:600px){body{padding:10px}.card{margin:8px auto;padding:18px;border-radius:14px}h1{font-size:23px}.item{font-size:12px}}
</style></head><body><div class="card"><div class="brand">{% if logo_uri %}<img src="{{ logo_uri }}">{% endif %}<div><b>{{ business_name }}</b></div></div>
<h1>Order tracking</h1><div class="muted">Order ID: <b>{{ sale.order_id or '-' }}</b></div>
{% if verification == "valid" %}<div class="verify"><b>Invoice verified.</b> This invoice matches our records.</div>{% elif verification == "invalid" %}<div style="padding:10px 12px;border-radius:8px;background:#fdecea;color:#b3261e;margin:12px 0"><b>Invoice verification failed.</b> The order is still shown, but the supplied invoice code did not match our records.</div>{% endif %}
{% if journey.mode %}<div class="mode">{{ "✈ On air" if journey.mode == "air" else "🚢 On sea" }}</div>{% endif %}
<div class="tracking-current"><b>{{ journey.current_label }}</b><br><span class="muted">{{ journey.current_description }}</span><div class="tracking-progress"><span></span></div></div>
<ol class="steps">{% for step in journey.steps %}<li class="step {{ step.state }}"><span class="dot"></span><div><strong>{{ step.label }}</strong>{% if step.at %}<div class="date">{{ step.at[:10] }}</div>{% endif %}<div class="muted">{{ step.description }}</div></div></li>{% endfor %}</ol>
<div class="items"><b>Order items</b>{% for item in sale.items %}<div class="item"><span>{{ item.product.name if item.product else "Item" }}{% if item.variant_note %} · {{ item.variant_note }}{% endif %}</span><span>× {{ item.qty }}</span></div>{% endfor %}</div>
<div class="footer">This public page does not display your phone number or delivery address.</div></div></body></html>"""

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


@verify_bp.route("/track/<tracking_code>")
def track(tracking_code):
    sale = Sale.query.filter_by(public_tracking_code=tracking_code).first()
    if sale is None:
        return render_template_string(TRACKING_PAGE, sale=Sale(order_id=None), journey={"current_label":"Order not found","current_description":"This tracking link is invalid or no longer exists.","steps":[],"mode":None}, verification=None, **_brand_context()), 404
    sig = request.args.get("sig", "")
    verification = "valid" if sig and signature_matches(sale, sig.replace("-", "")) else ("invalid" if sig else None)
    return render_template_string(TRACKING_PAGE, sale=sale, journey=journey_for(sale), verification=verification, **_brand_context(sale))


@verify_bp.route("/verify/<order_id>/<sig>")
def verify(order_id, sig):
    sale = Sale.query.filter_by(order_id=order_id).first()
    if sale is None and order_id.isdigit():
        sale = Sale.query.get(int(order_id))
    if sale is None:
        return render_template_string(PAGE, state="missing", **_brand_context()), 404
    if not signature_matches(sale, sig.replace("-", "")):
        return render_template_string(PAGE, state="changed", **_brand_context()), 200
    return redirect(f"/track/{sale.public_tracking_code}?sig={sig}")
