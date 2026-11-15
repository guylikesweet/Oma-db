# Local receipt generation — implementation audit

## Stage 1 — Existing flow and source-of-truth audit

- The Flutter receipt dialog previously downloaded PNG, JPG, or PDF from three authenticated binary endpoints under `/api/v1/sales/<id>/receipt.*`.
- Those endpoints called `generate_invoice_image()` / `generate_invoice_pdf()`, which loaded sale and business settings, built receipt context, drew a 1080 px Pillow image, and then encoded it. The PDF was an 80 mm page containing that image.
- Receipt eligibility is server-enforced: cancelled orders and anything whose payment status is not exactly `Paid` are refused.
- Receipt facts include business name/phone/address/Instagram/logo; order ID/date/status; customer details; product name/variant/quantity/unit and line amounts; products-only total; shipping notice and estimated arrival; QR verification URL; HMAC signature/code; tracking display and footer.
- The HMAC canonical data covers order ID, sale date, customer name, subtotal and sorted product/quantity/unit-price tuples. The QR URL is checked by the server. The signing key must never be sent to Flutter.
- Internal notes, profit, stock cost, and staff-only fields are not part of the printed receipt.
- Local sales use negative IDs and OFF-/OFFSTK- placeholders until sync. They do not have server-issued signatures and must never be presented as verified receipts.

## Stage 2 — Local renderer

- Added `mobile/lib/receipt_renderer.dart`.
- The Flutter client now builds the 80 mm PDF locally, including logo, customer/order information, item table, total, shipping notice, QR code, verification code/seal, watermark and footer.
- PNG and JPG are rasterized from that locally generated PDF. JPG encoding uses the existing Flutter image ecosystem via a direct `image` dependency.
- The renderer is shared by Android and Flutter Web; no platform-specific rendering path was introduced.

## Stage 3 — Server-issued verification payload

- Added authenticated `GET /api/v1/sales/<id>/receipt-data`.
- It enforces the same paid/non-cancelled rule as the old file endpoints.
- It returns the existing `get_invoice_context()` facts, server-generated HMAC verification URL/code and logo bytes encoded as base64.
- No secret key or signing operation is exposed to the client. No database migration is required.

## Stage 4 — Receipt action switched to local rendering

- `ApiClient.receiptData()` fetches the compact JSON payload.
- `invoice_actions.dart` now renders PDF/PNG/JPG on the client instead of requesting server-generated files.
- The original binary receipt endpoints remain registered for older installed app versions and external compatibility; the updated client no longer calls them.
- Share and print continue to use the same popup and existing share/print plugins.

## Stage 5 — Validation

- Added a Flutter unit test that checks local PDF generation returns a PDF document.
- GitHub Actions CI is triggered by pushes to main and is responsible for dependency resolution, Flutter analysis, Flutter tests and Flutter Web release compilation, alongside backend tests.
- A passing CI run is required before calling this fully validated. Android release APK installation and visual parity still require a real device check.

## Explicit remaining limitation

A negative-ID offline sale cannot receive an official receipt yet: it has no server HMAC or verification URL until it synchronizes. It must remain clearly provisional until then. The current local renderer path is for server-confirmed paid sales. Do not create a fake signature or a fake verified QR for offline sales.
