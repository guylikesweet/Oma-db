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
 <p><b>Scan the QR code or open this invoice link to verify it and view your product-tracking journey.</b></p>
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



TRACKING_PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>{{ business_name }} · Order tracking</title><style>
:root{--bg:#f5f7f8;--surface:#fff;--ink:#17212b;--muted:#667085;--line:#e4e8ec;--orange:#fc4300;--green:#039664;--soft-orange:#fff2ec;--soft-green:#eaf8f2}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:Inter,system-ui,-apple-system,"Segoe UI",sans-serif}.track-shell{max-width:980px;margin:auto;padding:28px 18px 60px}.track-brand{display:flex;align-items:center;gap:12px;margin-bottom:22px}.track-brand img{max-width:150px;max-height:52px}.track-brand-name{font-weight:800}.track-hero{background:linear-gradient(135deg,#17212b,#253340);color:#fff;border-radius:22px;padding:28px;box-shadow:0 14px 40px #10182829}.eyebrow{font-size:11px;letter-spacing:.13em;text-transform:uppercase;font-weight:800;color:#ffb49a}.track-hero h1{font-size:32px;margin:7px 0}.track-ref{color:#d6dde3;font-size:13px}.track-grid{display:grid;grid-template-columns:minmax(0,1.5fr) minmax(280px,.8fr);gap:18px;margin-top:18px}.track-card{background:var(--surface);border:1px solid var(--line);border-radius:18px;padding:21px;box-shadow:0 5px 22px #1018280d}.track-card h2{font-size:17px;margin:0 0 15px}.current{background:linear-gradient(135deg,var(--soft-green),#fff);border-color:#cce9dd}.current-label{font-size:23px;font-weight:800;color:var(--green)}.current-desc{margin:6px 0;color:var(--muted);font-size:13px;line-height:1.5}.mode{display:inline-flex;margin-top:13px;padding:6px 10px;border-radius:999px;background:var(--soft-orange);color:#c93b08;font-size:11px;font-weight:800}.progress{height:8px;border-radius:99px;background:#e8ecef;overflow:hidden;margin-top:17px}.progress span{display:block;height:100%;background:linear-gradient(90deg,var(--orange),var(--green));width:{{ ((journey.steps|selectattr('state','in',['done','current','final'])|list|length/(journey.steps|length or 1))*100)|round(0) }}%}.verification{margin-top:18px;padding:11px 13px;border-radius:10px;font-size:12px;font-weight:700}.verification.ok{background:var(--soft-green);color:#027a52}.verification.bad{background:#fff0f0;color:#b3261e}.timeline{list-style:none;margin:0;padding:0}.event{display:grid;grid-template-columns:20px 1fr;gap:12px;position:relative;padding-bottom:19px}.event:last-child{padding-bottom:0}.event:not(:last-child):before{content:"";position:absolute;left:8px;top:18px;bottom:0;width:2px;background:#dce3df}.event-dot{width:17px;height:17px;border-radius:50%;background:#d4dadd;border:3px solid #fff;box-shadow:0 0 0 1px #c9d0d4}.event.done .event-dot{background:var(--green)}.event.current .event-dot,.event.final .event-dot{background:var(--orange)}.event-title{font-weight:800;font-size:13px}.event.current .event-title,.event.final .event-title{color:var(--orange)}.event-date{display:block;color:#98a2b3;font-size:11px;margin-top:3px}.event-desc{color:var(--muted);font-size:12px;margin-top:4px;line-height:1.45}.info-list{margin:0;padding:0;list-style:none}.info-list li{display:flex;justify-content:space-between;gap:12px;padding:11px 0;border-bottom:1px solid var(--line);font-size:13px}.info-list li:last-child{border-bottom:0}.info-list span{color:var(--muted)}.info-list strong{text-align:right}.items{overflow-x:auto}.item{display:flex;justify-content:space-between;gap:16px;padding:11px 0;border-bottom:1px solid var(--line);font-size:13px}.support{background:#17212b;color:#fff}.support p{color:#d6dde3;font-size:13px;line-height:1.5}.support a{display:inline-flex;padding:9px 13px;border-radius:9px;background:var(--green);color:#fff;text-decoration:none;font-weight:800;font-size:12px}.privacy{text-align:center;color:var(--muted);font-size:11px;margin-top:18px}@media(max-width:760px){.track-shell{padding:12px 10px 32px}.track-brand{gap:9px;margin-bottom:14px;min-height:34px}.track-brand img{max-width:112px;max-height:38px}.track-brand-name{font-size:14px;line-height:1.2}.track-hero{padding:17px 16px;border-radius:15px;box-shadow:0 8px 24px #1018281c}.eyebrow{font-size:9px;letter-spacing:.11em}.track-hero h1{font-size:22px;line-height:1.2;margin:5px 0 7px}.track-ref{font-size:11px;line-height:1.4;overflow-wrap:anywhere}.track-grid{grid-template-columns:1fr;gap:12px;margin-top:12px}.track-card{padding:14px;border-radius:14px;box-shadow:0 3px 14px #1018280a}.track-card h2{font-size:15px;margin-bottom:11px}.current-label{font-size:19px;line-height:1.25}.current-desc{font-size:12px;line-height:1.45}.mode{margin-top:9px;padding:5px 8px;font-size:10px}.progress{height:6px;margin-top:13px}.timeline .event{grid-template-columns:17px minmax(0,1fr);gap:9px;padding-bottom:15px}.event-dot{width:15px;height:15px}.event:not(:last-child):before{left:7px;top:16px}.event-title{font-size:12px;line-height:1.3}.event-date{font-size:10px}.event-desc{font-size:11px;line-height:1.4}.info-list li{padding:9px 0;font-size:12px;gap:9px}.info-list strong{max-width:62%;overflow-wrap:anywhere}.item{padding:9px 0;font-size:12px;gap:10px}.support p{font-size:12px}.support a{padding:8px 11px;font-size:11px}.privacy{font-size:10px;line-height:1.4;margin-top:14px}}@media(max-width:380px){.track-shell{padding-left:8px;padding-right:8px}.track-hero{padding:15px 13px}.track-hero h1{font-size:20px}.track-card{padding:12px}.current-label{font-size:18px}.track-brand img{max-width:95px;max-height:34px}.track-brand-name{font-size:13px}}
</style></head><body><div class="track-shell"><div class="track-brand">{% if logo_uri %}<img src="{{ logo_uri }}" alt="{{ business_name or 'Business' }}">{% endif %}<span class="track-brand-name">{{ business_name }}</span></div><div class="verification" style="background:#fff2ec;color:#9e3108">Scan the QR code or open/click the invoice link to verify the invoice and follow your product's journey from order to delivery.</div>{% if journey.current_label=='Order not found' %}<section class="track-hero"><div class="eyebrow">Order tracking</div><h1>We couldn't find this order</h1><div class="track-ref">The tracking link is invalid or no longer exists.</div></section>{% else %}<section class="track-hero"><div class="eyebrow">Order tracking</div><h1>{{ journey.current_headline }}</h1><div class="track-ref">Order reference: <b>{{ sale.order_id or '—' }}</b></div></section>{% if verification=="valid" %}<div class="verification ok">✓ Invoice verified · The supplied invoice code matches our records.</div>{% elif verification=="invalid" %}<div class="verification bad">Invoice verification failed · The supplied invoice code does not match our records.</div>{% endif %}<div class="track-grid"><main><section class="track-card current"><h2>Current shipment status</h2><div class="current-label">{{ journey.current_label }}</div><p class="current-desc">{{ journey.current_description }}</p>{% if journey.mode %}<span class="mode">{{ '✈ Air shipment' if journey.mode=='air' else '🚢 Sea shipment' }}</span>{% endif %}<div class="progress"><span></span></div></section><section class="track-card" style="margin-top:18px"><h2>Shipment journey</h2><ol class="timeline">{% for step in journey.steps %}<li class="event {{ step.state }}"><span class="event-dot"></span><div><div class="event-title">{{ step.label }}</div>{% if step.at %}<span class="event-date">{{ step.at[:10] }}</span>{% elif step.at_dt %}<span class="event-date">{{ step.at_dt.strftime('%d %b %Y') }}</span>{% endif %}<div class="event-desc">{{ step.description }}</div></div></li>{% endfor %}</ol></section><section class="track-card" style="margin-top:18px"><h2>Order contents</h2><div class="items">{% for item in sale.items %}<div class="item"><span><strong>{{ item.product.name if item.product else 'Item' }}</strong>{% if item.variant_note %}<br><span style="color:var(--muted)">{{ item.variant_note }}</span>{% endif %}</span><strong>× {{ item.qty }}</strong></div>{% else %}<div style="color:var(--muted)">No order items available.</div>{% endfor %}</div></section></main><aside><section class="track-card"><h2>Order summary</h2><ul class="info-list"><li><span>Order</span><strong>{{ sale.order_id }}</strong></li><li><span>Placed</span><strong>{{ sale.sale_date }}</strong></li>{% if sale.estimated_arrival_start %}<li><span>Estimated arrival</span><strong>{{ sale.estimated_arrival_start }}{% if sale.estimated_arrival_end %} — {{ sale.estimated_arrival_end }}{% endif %}</strong></li>{% endif %}<li><span>Payment</span><strong>{{ sale.payment_status }}</strong></li></ul></section><section class="track-card support" style="margin-top:18px"><h2>Need help?</h2><p>Have a question about this order? Include your order reference when contacting us.</p>{% if wa_number %}<a href="https://wa.me/{{ wa_number }}?text={{ wa_text|urlencode }}" target="_blank" rel="noopener">Contact us on WhatsApp</a>{% endif %}</section></aside></div>{% endif %}<div class="privacy">For your privacy, this public tracking page does not display your phone number or delivery address.</div></div></body></html>"""

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
