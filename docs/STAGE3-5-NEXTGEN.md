# Oma Stage 3–5 product roadmap

Stages 3–5 are now the product-hardening and next-generation experience phase.

## Stage 3 — Trust, permissions and auditability

- Admin/Owner vs Staff authorization boundaries.
- Sensitive actions require server-side authorization, not UI-only hiding.
- Immutable audit log for login/logout/security events, price and product changes, shipping-rate changes, bank/business-setting changes, sale status/payment changes, shipping settlement, batch arrival, delivery changes, user/role changes and destructive operations.
- Every audit event records actor, action, target, timestamp, outcome and useful before/after metadata.
- Admin audit viewer with filtering and search.
- Mobile/offline operations retain their original authenticated actor identity.
- High-risk operations use idempotency and transactional state-change + audit recording.

## Stage 4 — Secure approvals, biometrics and notifications

- OS biometric unlock for supported Android/iOS devices.
- Biometrics are never sent to the server and never treated as raw server credentials.
- High-risk approvals use a server-verifiable challenge bound to actor, action, target, nonce, expiry and idempotency key.
- Batch-arrival and shipping-settlement approvals require the stronger approval flow.
- Firebase Cloud Messaging for Android/mobile push notifications.
- Per-device push tokens, revocation and deduplication.
- Transactional notification outbox so a committed business event cannot silently lose its notification.
- Web uses standards-based browser capabilities where supported; no fake biometric security.
- Offline actions remain attributable to the authenticated user.

## Stage 5 — Next-generation product experience

### Brand system

The Omabuy logo's three colors are first-class design tokens:

- Orange #FC4300 — primary action, important CTAs, active progress and high-attention states.
- Green #039664 — success, confirmed/synced states, secondary actions, navigation selection and positive financial/inventory signals.
- White — clean surfaces, cards, content breathing room and logo contrast.

The colors should be used deliberately rather than making the entire interface orange.

### Appearance

Both the Flask website and Flutter app support:

- System appearance.
- Sunset-to-sunrise appearance.
- Always light.
- Always dark.
- Persistent per-device preference.
- Safe fallback when browser/device location is unavailable.

### Layout and service quality

Every page will be progressively brought to the same design standard:

- clear information hierarchy
- responsive desktop/tablet/mobile layouts
- compact mobile density without making text or controls uncomfortably small
- consistent cards, spacing, typography, icons and actions
- clear loading, empty, offline and error states
- accessible contrast and touch targets
- destructive-action confirmation
- predictable navigation and back behavior
- skeleton/loading placeholders where useful
- server-authoritative calculations
- useful search/filter/sort patterns
- clear success/error feedback
- offline-first behavior where supported
- graceful recovery instead of dead-end screens
- consistent brand treatment across Flask web, Flutter web and Android

## Dashboard and operational intelligence

The final dashboard will surface:

- profit per sale
- shipping money still owed for arrived goods
- low stock
- monthly sales
- batches in transit
- journey-stage counts
- pending sync and operational exceptions

Profit and shipping-owed figures must use canonical server calculations. Estimated shipping remains distinct from actual/settled shipping.

## Implementation rule

Large UI changes are delivered in small verified increments. The Flutter order-journey card is specifically being rebuilt piece-by-piece after the previous white-block layout problem; a timeline or advanced controls will not be added until the compact current-status card is proven safe.
