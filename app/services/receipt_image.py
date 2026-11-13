"""
Tall phone receipt, drawn as an image (1080 px wide, 9:16 by default).

Why an image: a receipt is almost always shared on WhatsApp. An A4 PDF is wide,
mostly white space, and has tiny text, so customers have to zoom. This draws
the receipt to a 1080 x 1920 canvas so it fills a phone screen as-is. The PDF
version is just this same picture placed on a small page, so the two always
match exactly.

Anti-forgery ("originality") layers, all seeded from the receipt's HMAC
signature so no two receipts look alike and a forger cannot reproduce them for
an edited amount:

  * a guilloche line pattern + rosettes behind everything (banknote style)
  * the OmaBuy logo watermark drawn OVER the content (it used to be hidden
    behind the opaque shipping notice) at low opacity so it never blocks text
  * a tiled diagonal text watermark carrying the order id and signature
  * micro-text rules that blur away when a receipt is re-photographed/edited
  * a circular "ORIGINAL - VERIFIED" seal carrying part of the signature

Honest limit: a picture can always be edited by a determined person. The thing
that cannot be faked is the QR code / verification code, which is checked
against the server's own record (HMAC signature). The visual layers make casual
edits obvious and make a convincing fake much more work.

This module is pure Pillow: no Flask, no database. app/services/invoices.py
builds the data dictionary and calls render_receipt().
"""
import hashlib
import io
import math
import os
from functools import lru_cache

from PIL import Image, ImageChops, ImageDraw, ImageFont

W = 1080
H_TARGET = 1920
MARGIN = 64
CARD_RADIUS = 56
FOOTER_H = 96

GREEN = (27, 67, 38)
GREEN_MID = (74, 140, 84)
ORANGE = (249, 127, 14)
INK = (30, 30, 30)
GREY = (110, 110, 110)
HAIR = (222, 222, 222)
TABLE_HEAD = (0xD9, 0xEA, 0xD3)
TABLE_LINE = (176, 204, 176)
NOTICE_BG = (0xFF, 0xF3, 0xCD)
NOTICE_LINE = (232, 196, 104)
NOTICE_INK = (92, 64, 14)
TOTAL_BG = (246, 246, 244)
PILL_GREEN = (74, 150, 92)


# ----------------------------------------------------------------- fonts ----
@lru_cache(maxsize=64)
def _font(size, bold=False):
    try:
        import reportlab
        base = os.path.join(os.path.dirname(reportlab.__file__), "fonts")
        path = os.path.join(base, "VeraBd.ttf" if bold else "Vera.ttf")
        return ImageFont.truetype(path, size)
    except Exception:
        try:
            return ImageFont.load_default(size)
        except TypeError:  # very old Pillow
            return ImageFont.load_default()


def _tw(font, text):
    return font.getlength(text)


def _fit_font(text, max_w, start, bold=False, floor=22):
    size = start
    while size > floor and _tw(_font(size, bold), text) > max_w:
        size -= 2
    return _font(size, bold)


def _wrap(font, text, max_w):
    """Greedy word wrap; a single over-long word is broken by characters."""
    lines, cur = [], ""
    for word in str(text).split():
        trial = word if not cur else cur + " " + word
        if _tw(font, trial) <= max_w:
            cur = trial
            continue
        if cur:
            lines.append(cur)
        cur = ""
        while _tw(font, word) > max_w and len(word) > 1:
            cut = len(word) - 1
            while cut > 1 and _tw(font, word[:cut]) > max_w:
                cut -= 1
            lines.append(word[:cut])
            word = word[cut:]
        cur = word
    if cur:
        lines.append(cur)
    return lines or [""]


def _center_text(d, y, text, font, fill, cx=W // 2):
    d.text((cx - _tw(font, text) / 2, y), text, font=font, fill=fill)


# --------------------------------------------------------- small glyphs ----
# The bundled font has no naira sign or tick, so they are drawn by hand.
def _naira(d, x, y, size, fill, bold=True):
    """Draws the naira sign at (x, y) (top-left of the text line). Returns
    the horizontal advance."""
    font = _font(size, bold)
    d.text((x, y), "N", font=font, fill=fill)
    l, t, r, b = font.getbbox("N")
    h = b - t
    adv = _tw(font, "N")
    thick = max(2, size // 13)
    for frac in (0.36, 0.64):
        yy = y + t + h * frac
        d.rectangle([x + l - size * 0.09, yy - thick / 2,
                     x + r + size * 0.09, yy + thick / 2], fill=fill)
    return adv + size * 0.12


def _money_w(size, text, bold=True):
    return size * 0.9 + _tw(_font(size, bold), text)


def _money(d, right_x, y, amount_text, size, fill, bold=True):
    """Right-aligns '₦1,234.00' so its right edge sits at right_x."""
    font = _font(size, bold)
    w = _tw(font, amount_text)
    start = right_x - w - size * 0.78
    adv = _naira(d, start, y, size, fill, bold)
    d.text((start + adv, y), amount_text, font=font, fill=fill)


def _tick(d, cx, cy, s, fill, width):
    d.line([(cx - s * 0.5, cy), (cx - s * 0.12, cy + s * 0.38),
            (cx + s * 0.55, cy - s * 0.42)], fill=fill, width=width, joint="curve")


def _person_icon(d, x, y, s, fill):
    d.ellipse([x + s * 0.3, y, x + s * 0.7, y + s * 0.4], outline=fill, width=3)
    d.arc([x + s * 0.08, y + s * 0.48, x + s * 0.92, y + s * 1.2], 180, 360,
          fill=fill, width=3)


# ------------------------------------------------------------ rich text ----
def _wrap_runs(paragraph, size, max_w):
    """paragraph = [(text, bold), ...] -> list of lines, each a list of
    (word, bold) tuples, wrapped to max_w."""
    words = []  # (word, bold, glued_to_previous)
    prev = ""
    for text, bold in paragraph:
        text = str(text)
        parts = text.split()
        for i, w in enumerate(parts):
            # Punctuation that directly follows a run (no space between the
            # two runs, e.g. "<b>NGN 1.00</b>.") sticks to the previous word.
            glued = (i == 0 and bool(words) and not text[:1].isspace()
                     and not prev[-1:].isspace())

            # Never let a long URL, reference, or other unbroken token exceed
            # the available line width. Split it into measured character runs.
            font = _font(size, bold)
            pieces = []
            remaining = w
            while _tw(font, remaining) > max_w and len(remaining) > 1:
                cut = len(remaining) - 1
                while cut > 1 and _tw(font, remaining[:cut]) > max_w:
                    cut -= 1
                pieces.append(remaining[:cut])
                remaining = remaining[cut:]
            pieces.append(remaining)
            for piece_index, piece in enumerate(pieces):
                words.append((piece, bold, glued if piece_index == 0 else True))
        prev = text
    lines, cur, cur_w = [], [], 0.0
    space = _tw(_font(size), " ")
    for w, bold, glued in words:
        ww = _tw(_font(size, bold), w)
        add = ww if (not cur or glued) else space + ww
        if cur and not glued and cur_w + add > max_w:
            lines.append(cur)
            cur, cur_w = [(w, bold, False)], ww
        else:
            cur.append((w, bold, glued))
            cur_w += add
    if cur:
        lines.append(cur)
    return lines


def _draw_runs_line(d, x, y, line, size, fill):
    space = _tw(_font(size), " ")
    for i, (w, bold, glued) in enumerate(line):
        f = _font(size, bold)
        if i and not glued:
            x += space
        d.text((x, y), w, font=f, fill=fill)
        x += _tw(f, w)


# ----------------------------------------------------------------- logo -----
def _prepare_logo(raw):
    """Opens the logo, drops an opaque white background if it has one, and
    trims empty margins so the logo fills its box (a logo with big transparent
    borders would otherwise print tiny)."""
    img = Image.open(io.BytesIO(raw)).convert("RGBA")
    if img.getchannel("A").getextrema()[0] >= 250:
        r, g, b = img.convert("RGB").split()
        low = ImageChops.darker(ImageChops.darker(r, g), b)
        img.putalpha(low.point(lambda v: 0 if v >= 245 else min(255, int((255 - v) * 3))))
    box = img.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
    if box:
        pad = 4
        img = img.crop((max(0, box[0] - pad), max(0, box[1] - pad),
                        min(img.width, box[2] + pad), min(img.height, box[3] + pad)))
    return img


# ------------------------------------------------------------------ QR -----
def _qr_matrix(url):
    from reportlab.graphics.barcode import qrencoder
    qr = qrencoder.QRCode(None, qrencoder.QRErrorCorrectLevel.M)
    qr.addData(url)
    qr.make()
    n = qr.getModuleCount()
    return [[bool(qr.isDark(r, c)) for c in range(n)] for r in range(n)]


def _qr_image(url, px):
    m = _qr_matrix(url)
    n = len(m)
    quiet = 2
    total = n + quiet * 2
    cell = max(1, px // total)
    size = cell * total
    img = Image.new("RGB", (size, size), "white")
    d = ImageDraw.Draw(img)
    for r in range(n):
        for c in range(n):
            if m[r][c]:
                x0 = (c + quiet) * cell
                y0 = (r + quiet) * cell
                d.rectangle([x0, y0, x0 + cell - 1, y0 + cell - 1], fill=(15, 15, 15))
    return img


# ------------------------------------------------------ security layers ----
def _seed_bytes(signature):
    return hashlib.sha256(("omabuy-receipt:" + str(signature)).encode()).digest()


def _guilloche_layer(w, h, seed):
    """Fine wave-line pattern + rosettes whose shape comes from the signature."""
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    s = seed
    amp = 10 + s[0] % 9
    wave = 150 + s[1] % 90
    phase = (s[2] / 255.0) * math.tau
    drift = 0.05 + (s[3] % 8) / 100.0
    spacing = 13
    line = (GREEN[0], GREEN[1], GREEN[2], 20)
    for k, y0 in enumerate(range(-30, h + 30, spacing)):
        pts = []
        for x in range(0, w + 6, 6):
            y = y0 + amp * math.sin(x / wave * math.tau + phase + k * drift)
            y += (amp * 0.45) * math.sin(x / (wave * 0.37) * math.tau + k * 0.31)
            pts.append((x, y))
        d.line(pts, fill=line, width=1)

    def rosette(cx, cy, r, a, b, col, steps=1400):
        pts = []
        for i in range(steps + 1):
            t = i / steps * math.tau * (b if b else 1)
            x = (r - a) * math.cos(t) + a * 0.9 * math.cos((r - a) / a * t)
            y = (r - a) * math.sin(t) - a * 0.9 * math.sin((r - a) / a * t)
            pts.append((cx + x, cy + y))
        d.line(pts, fill=col, width=1)

    ra = 7 + s[4] % 5
    rb = 3 + s[5] % 4
    col = (ORANGE[0], ORANGE[1], ORANGE[2], 34)
    gcol = (GREEN[0], GREEN[1], GREEN[2], 30)
    rosette(120, 150, 150, rb + 20, ra, gcol)
    rosette(w - 120, 150, 150, rb + 24, ra + 1, col)
    rosette(w // 2, int(h * 0.55), 330, rb + 40, ra + 2, gcol, steps=2600)
    return layer


def _micro_rule(d, y, text, seed):
    """A line of tiny text that looks like a rule from far away."""
    f = _font(11)
    unit = text + "  "
    n = int(W / max(1, _tw(f, unit))) + 3
    d.text((-int(seed[6] % 20), y), unit * n, font=f, fill=(*GREEN_MID,))


def _tiled_text_layer(w, h, text, alpha=15):
    diag = int(math.hypot(w, h)) + 40
    big = Image.new("RGBA", (diag, diag), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    f = _font(26, True)
    unit = text + "      "
    tw = max(1, int(_tw(f, unit)))
    row_h = 74
    for ri, y in enumerate(range(0, diag, row_h)):
        offset = -(ri * 137) % tw
        x = -offset
        while x < diag:
            d.text((x, y), unit, font=f, fill=(GREEN[0], GREEN[1], GREEN[2], alpha))
            x += tw
    big = big.rotate(24, resample=Image.BICUBIC)
    left = (diag - w) // 2
    top = (diag - h) // 2
    return big.crop((left, top, left + w, top + h))


def _logo_watermark_layer(w, h, logo, center_y, opacity=0.11, target_w=860, angle=-14):
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    if logo is None:
        return layer
    lg = logo.copy()
    scale = target_w / lg.width
    lg = lg.resize((target_w, max(1, int(lg.height * scale))), Image.LANCZOS)
    a = lg.getchannel("A").point(lambda v: int(v * opacity))
    lg.putalpha(a)
    lg = lg.rotate(angle, expand=True, resample=Image.BICUBIC)
    layer.alpha_composite(lg, (int((w - lg.width) / 2), int(center_y - lg.height / 2)))
    return layer


def _seal(diameter, sig):
    """Circular 'ORIGINAL - VERIFIED' stamp with a tick and signature fragment."""
    S = diameter * 2  # draw at 2x then shrink for smooth edges
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    col = (GREEN[0], GREEN[1], GREEN[2], 215)
    d.ellipse([6, 6, S - 6, S - 6], outline=col, width=9)
    d.ellipse([22, 22, S - 22, S - 22], outline=col, width=3)
    inner = int(S * 0.30)
    d.ellipse([S / 2 - inner, S / 2 - inner, S / 2 + inner, S / 2 + inner],
              outline=col, width=3)

    ring = "ORIGINAL RECEIPT  *  OMABUY VERIFIED  *  "
    f = _font(int(S * 0.095), True)
    radius = S * 0.395
    widths = [_tw(f, ch) for ch in ring]
    total = sum(widths)
    angle = 0.0
    cx = cy = S / 2
    for ch, cw in zip(ring, widths):
        mid = angle + cw / 2
        theta = mid / total * math.tau
        glyph = Image.new("RGBA", (int(cw) + 16, int(f.size * 1.6)), (0, 0, 0, 0))
        ImageDraw.Draw(glyph).text((8, 4), ch, font=f, fill=col)
        glyph = glyph.rotate(-math.degrees(theta), expand=True, resample=Image.BICUBIC)
        px = cx + radius * math.sin(theta) - glyph.width / 2
        py = cy - radius * math.cos(theta) - glyph.height / 2
        img.alpha_composite(glyph, (int(px), int(py)))
        angle += cw

    _tick(d, S / 2, S / 2 - S * 0.045, S * 0.26, col, int(S * 0.034))
    f2 = _font(int(S * 0.062), True)
    code = (sig or "")[:8]
    _center_text(d, S * 0.60, code, f2, col, cx=S / 2)
    seal = img.resize((diameter, diameter), Image.LANCZOS)
    return seal.rotate(-12, expand=True, resample=Image.BICUBIC)


# ---------------------------------------------------------- the layout -----
def _draw_content(img, ctx, logo, qr_img, gap):
    """Draws every section top to bottom. `gap` is extra breathing room added
    between sections (used to stretch short receipts to a full 9:16 screen).
    Returns the y position where content ends (before the footer bar)."""
    d = ImageDraw.Draw(img)
    inner_w = W - 2 * MARGIN
    y = 64

    # 1. header -------------------------------------------------------------
    if logo is not None:
        max_w, max_h = 640, 150
        s = min(max_w / logo.width, max_h / logo.height)
        lw, lh = int(logo.width * s), int(logo.height * s)
        lg = logo.resize((lw, lh), Image.LANCZOS)
        img.paste(lg, ((W - lw) // 2, y), lg)
        y += lh + 14
    # No logo file found: leave the space empty rather than printing plain
    # text that only pretends to be the logo.
    _center_text(d, y, ctx["business_name"], _fit_font(ctx["business_name"], inner_w, 36, True), GREEN)
    y += 48
    contact = []
    if ctx.get("business_phone"):
        contact.append("Phone: " + ctx["business_phone"])
    if ctx.get("instagram"):
        contact.append("Instagram: " + ctx["instagram"])
    if contact:
        line = "  |  ".join(contact)
        _center_text(d, y, line, _fit_font(line, inner_w, 28, False, 20), GREY)
        y += 40
    if ctx.get("business_address"):
        for ln in _wrap(_font(26), ctx["business_address"], inner_w)[:2]:
            _center_text(d, y, ln, _font(26), GREY)
            y += 36
    y += 10 + gap

    # 2. title bar ----------------------------------------------------------
    d.rectangle([MARGIN, y, W - MARGIN, y + 3], fill=ORANGE)
    y += 3
    title = "INVOICE / RECEIPT"
    _center_text(d, y + 18, title, _fit_font(title, inner_w, 72, True), GREEN)
    y += 18 + 88 + 8
    d.rectangle([MARGIN, y, W - MARGIN, y + 1], fill=HAIR)
    y += 22 + gap

    # 3. order info ---------------------------------------------------------
    col_l, col_r = MARGIN, W // 2 + 16
    col_w = W // 2 - MARGIN - 16
    for x, label, value in ((col_l, "Order ID:", ctx["order_id"]),
                            (col_r, "Date:", ctx["date_text"])):
        lf = _font(26)
        lw = _tw(lf, label) + 28
        d.rounded_rectangle([x, y, x + lw, y + 42], radius=10, fill=(232, 232, 232))
        d.text((x + 14, y + 7), label, font=lf, fill=GREY)
        vf = _fit_font(value, col_w, 44, False, 26)
        d.text((x, y + 50), value, font=vf, fill=INK)
    y += 50 + 56 + 4

    # status pills
    pill_h = 52
    pf = _font(26, True)
    ptxt = "Payment Status:"
    pw = int(_tw(pf, ptxt) + _tw(pf, "Paid") + 120)
    d.rounded_rectangle([col_l, y, col_l + pw, y + pill_h], radius=pill_h // 2, fill=PILL_GREEN)
    d.text((col_l + 20, y + 13), ptxt, font=pf, fill="white")
    bx = col_l + 20 + _tw(pf, ptxt) + 14
    d.ellipse([bx, y + 9, bx + 38, y + 47], fill=GREEN)
    _tick(d, bx + 19, y + 28, 20, "white", 4)
    d.text((bx + 50, y + 13), "Paid", font=pf, fill="white")

    sf = _font(26, True)
    stxt = "Order Status: " + ctx["order_status_label"]
    sw = int(_tw(sf, stxt) + 40)
    d.rounded_rectangle([col_r, y, col_r + sw, y + pill_h], radius=pill_h // 2,
                        outline=GREEN, width=3, fill="white")
    d.text((col_r + 20, y + 13), stxt, font=sf, fill=GREEN)
    y += pill_h + 22
    d.rectangle([MARGIN, y, W - MARGIN, y + 1], fill=HAIR)
    y += 22 + gap

    # 4. bill to ------------------------------------------------------------
    _person_icon(d, MARGIN - 4, y + 4, 42, GREEN)
    d.text((MARGIN + 58, y), "BILL TO", font=_font(40, True), fill=GREEN)
    y += 56
    name_f = _fit_font(ctx["customer_name"], inner_w - 20, 50, True, 30)
    d.text((MARGIN + 20, y), ctx["customer_name"], font=name_f, fill=INK)
    y += 60
    if ctx.get("customer_phone"):
        d.text((MARGIN + 20, y), "Phone: " + ctx["customer_phone"], font=_font(30), fill=INK)
        y += 42
    if ctx.get("address_text"):
        for ln in _wrap(_font(30), "Address: " + ctx["address_text"], inner_w - 20):
            d.text((MARGIN + 20, y), ln, font=_font(30), fill=INK)
            y += 38
    y += 16 + gap

    # 5. items table --------------------------------------------------------
    c_qty, c_unit, c_line = 96, 214, 226
    c_prod = inner_w - c_qty - c_unit - c_line
    x0 = MARGIN
    xs = [x0, x0 + c_prod, x0 + c_prod + c_qty, x0 + c_prod + c_qty + c_unit, x0 + inner_w]
    head_h = 62
    hf = _font(29, True)
    rows = []
    row_f = _font(29)
    var_f = _font(24)
    for it in ctx["line_items"]:
        name_lines = _wrap(row_f, it["name"], c_prod - 32)
        var_lines = _wrap(var_f, it["variant"], c_prod - 32) if it.get("variant") else []
        rh = max(74, 26 + 38 * len(name_lines) + 30 * len(var_lines))
        rows.append((it, name_lines, var_lines, rh))
    table_h = head_h + sum(r[3] for r in rows)
    d.rounded_rectangle([x0, y, x0 + inner_w, y + table_h], radius=20, fill="white",
                        outline=TABLE_LINE, width=3)
    # header fill (rounded top)
    d.rounded_rectangle([x0 + 1, y + 1, x0 + inner_w - 1, y + head_h], radius=19, fill=TABLE_HEAD)
    d.rectangle([x0 + 1, y + head_h - 20, x0 + inner_w - 1, y + head_h], fill=TABLE_HEAD)
    d.text((xs[0] + 20, y + 16), "Product", font=hf, fill=GREEN)
    d.text((xs[2] - 16 - _tw(hf, "Qty"), y + 16), "Qty", font=hf, fill=GREEN)
    d.text((xs[3] - 16 - _tw(hf, "Unit Price"), y + 16), "Unit Price", font=hf, fill=GREEN)
    d.text((xs[4] - 16 - _tw(hf, "Line Total"), y + 16), "Line Total", font=hf, fill=GREEN)
    ry = y + head_h
    for it, name_lines, var_lines, rh in rows:
        d.line([(x0 + 2, ry), (x0 + inner_w - 2, ry)], fill=TABLE_LINE, width=2)
        text_h = 38 * len(name_lines) + 30 * len(var_lines)
        ty = ry + (rh - text_h) // 2
        for ln in name_lines:
            d.text((xs[0] + 20, ty), ln, font=row_f, fill=INK)
            ty += 38
        for ln in var_lines:
            d.text((xs[0] + 20, ty), ln, font=var_f, fill=GREY)
            ty += 30
        mid = ry + (rh - 34) // 2
        q = str(it["qty"])
        d.text((xs[2] - 16 - _tw(row_f, q), mid), q, font=row_f, fill=INK)
        _money(d, xs[3] - 12, mid, it["unit_text"], 27, INK, bold=False)
        _money(d, xs[4] - 12, mid, it["line_text"], 27, INK, bold=False)
        ry += rh
    for cx in xs[1:4]:
        d.line([(cx, y + 2), (cx, y + table_h - 2)], fill=TABLE_LINE, width=2)
    y += table_h + 24 + gap

    # 6. total box ----------------------------------------------------------
    box_h = 128
    d.rounded_rectangle([MARGIN, y, W - MARGIN, y + box_h], radius=22, fill=TOTAL_BG,
                        outline=ORANGE, width=3)
    d.text((MARGIN + 30, y + 26), "TOTAL PAID", font=_font(40, True), fill=INK)
    if ctx.get("total_note"):
        d.text((MARGIN + 30, y + 76), ctx["total_note"], font=_font(27), fill=GREY)
    _money(d, W - MARGIN - 30, y + 28, ctx["total_text"],
           66 if len(ctx["total_text"]) <= 10 else 54, GREEN)
    y += box_h + 24 + gap

    # 7. shipping notice ----------------------------------------------------
    paras = ctx.get("notice_paragraphs") or []
    if paras:
        body = 25
        lh = 34
        # Text begins to the right of the info icon. Measure from that
        # actual x-position to the inner right edge, preserving equal padding
        # on both sides of the notice instead of assuming a centered text box.
        tx = MARGIN + 28 + 54 + 20
        # Keep a deliberate right-side inset inside the rounded notice.
        # The line image below also clips as a final safeguard, so a wrapping
        # regression or an unusually long token can never paint outside it.
        text_right = W - MARGIN - 44
        text_w = max(1, text_right - tx)
        wrapped = [_wrap_runs(p, body, text_w) for p in paras]
        n_lines = sum(len(w) for w in wrapped)
        nh = 26 + 50 + n_lines * lh + 8 * (len(paras) - 1) + 22
        d.rounded_rectangle([MARGIN, y, W - MARGIN, y + nh], radius=24, fill=NOTICE_BG,
                            outline=NOTICE_LINE, width=3)
        ix, iy = MARGIN + 28, y + 20
        d.ellipse([ix, iy, ix + 54, iy + 54], outline=(196, 112, 12), width=4)
        d.text((ix + 27 - _tw(_font(32, True), "i") / 2, iy + 7), "i",
               font=_font(32, True), fill=(196, 112, 12))
        d.text((tx, y + 20), "Shipping Notice", font=_font(36, True), fill=(176, 92, 8))
        ty = y + 26 + 46
        for w in wrapped:
            for line in w:
                # Render each line into a bounded transparent strip. Even if
                # future rich-text changes mis-measure a line, Pillow cannot
                # draw any of its pixels beyond the notice's inner right edge.
                line_layer = Image.new("RGBA", (int(text_w), lh + 8), (0, 0, 0, 0))
                line_draw = ImageDraw.Draw(line_layer)
                _draw_runs_line(line_draw, 0, 0, line, body, NOTICE_INK)
                img.paste(line_layer, (tx, ty), line_layer)
                ty += lh
            ty += 8
        y += nh + 26 + gap
    else:
        y += 6

    # 8. QR + verify --------------------------------------------------------
    hd = "TRACK YOUR ORDER & VERIFY THIS INVOICE"
    _center_text(d, y, hd, _fit_font(hd, inner_w, 28, True, 20), GREEN)
    y += 38
    qs = qr_img.width
    pad = 14
    qx = (W - qs) // 2 - pad
    d.rounded_rectangle([qx, y, qx + qs + 2 * pad, y + qs + 2 * pad], radius=20,
                        fill="white", outline=(200, 200, 200), width=3)
    img.paste(qr_img, (qx + pad, y + pad))
    qr_top, qr_bottom = y, y + qs + 2 * pad
    y = qr_bottom + 14
    line = "Scan QR or visit: " + ctx["track_display"]
    _center_text(d, y, line, _fit_font(line, inner_w, 30, True, 20), GREEN)
    y += 38
    if ctx.get("code_text"):
        _center_text(d, y, "Verification code: " + ctx["code_text"], _font(24), GREY)
        y += 36
    return y, (qr_top, qr_bottom)


def render_receipt(ctx, logo_bytes=None):
    """Returns an RGBA Pillow image of the receipt (rounded corners are
    transparent). `ctx` is built by app.services.invoices."""
    logo = None
    if logo_bytes:
        try:
            logo = _prepare_logo(logo_bytes)
        except Exception:
            logo = None

    sig = ctx.get("signature") or ""
    seed = _seed_bytes(sig)
    qr_img = _qr_image(ctx["verify_url"], 250)

    # Pass 1: measure on a tall scratch canvas.
    scratch = Image.new("RGB", (W, 4200), "white")
    end_y, _ = _draw_content(scratch, ctx, logo, qr_img, 0)
    natural = end_y + 28 + FOOTER_H
    n_gaps = 8
    if natural < H_TARGET:
        gap = min(34, (H_TARGET - natural) // n_gaps)
        height = H_TARGET
    else:
        gap = 0
        height = natural

    # Pass 2: real canvas. Guilloche goes underneath.
    base = Image.new("RGBA", (W, height), (255, 255, 255, 255))
    base.alpha_composite(_guilloche_layer(W, height, seed))
    rgb = base.convert("RGB")
    end_y, (qr_top, qr_bottom) = _draw_content(rgb, ctx, logo, qr_img, gap)
    d = ImageDraw.Draw(rgb)

    # micro-text rules
    micro = "OMABUY NIGERIA LIMITED - ORIGINAL RECEIPT - %s - %s" % (ctx["order_id"], sig)
    _micro_rule(d, 20, micro.upper(), seed)
    _micro_rule(d, height - FOOTER_H - 22, micro.upper(), seed)

    # footer bar (rounded bottom corners are applied by the card mask)
    d.rectangle([0, height - FOOTER_H, W, height], fill=GREEN)
    ft = ctx["footer_text"]
    _center_text(d, height - FOOTER_H + (FOOTER_H - 38) // 2 - 2, ft,
                 _fit_font(ft, W - 2 * MARGIN, 34, True, 22), "white")

    out = rgb.convert("RGBA")

    # Watermark layers go OVER the content so the opaque notice/total boxes
    # can no longer hide them.
    out.alpha_composite(_tiled_text_layer(W, height, "OMABUY ORIGINAL  " + sig[:10]))
    out.alpha_composite(_logo_watermark_layer(W, height, logo, int(height * 0.50)))

    # seal beside the QR code
    seal = _seal(236, sig)
    out.alpha_composite(seal, (W - MARGIN - seal.width + 14, int((qr_top + qr_bottom) / 2 - seal.height / 2)))

    # rounded card corners
    mask = Image.new("L", (W, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, height - 1], radius=CARD_RADIUS, fill=255)
    out.putalpha(mask)
    # Where the QR code sits (pixels), so the PDF can make it a tappable link.
    qs = qr_img.width
    qx0 = (W - qs) // 2 - 14
    out.info["qr_box"] = (qx0, qr_top, qx0 + qs + 28, qr_bottom)
    return out


def to_png_bytes(img):
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def to_jpeg_bytes(img, background=(236, 240, 236), quality=90):
    flat = Image.new("RGB", img.size, background)
    flat.paste(img, (0, 0), img.getchannel("A"))
    buf = io.BytesIO()
    flat.save(buf, format="JPEG", quality=quality, optimize=True, subsampling=0)
    return buf.getvalue()
