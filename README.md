# Inventory & Shipping Admin

Flask + Postgres app: enter raw product dimensions and sale details, and CBM,
volumetric weight, shipping estimates, and profit are all calculated automatically.

## Stack
- Python 3.11, Flask 3, Flask-Admin, Flask-Login, Flask-SQLAlchemy, Flask-Migrate, Flask-Limiter
- Database: Postgres (Neon — free tier, does not expire or delete data on inactivity)
- Hosting: Render Web Service + Gunicorn
- Auth: bearer-token authentication for Flutter Web/Android; the former Flask/Jinja staff website is retired.

## Local setup

```bash
python3 -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt

cp .env.example .env
# then edit .env:
#   DATABASE_URL=<your Neon connection string>
#   SECRET_KEY=<any random string>
#   ADMIN_USERNAME=<your choice>
#   ADMIN_PASSWORD=<your choice>

export FLASK_APP=run.py         # Windows: set FLASK_APP=run.py
flask db upgrade                # applies the current Alembic migration chain
flask seed-admin                # creates the admin login if missing
flask seed-admin --reset        # explicitly reset the configured admin password

flask run
```

Visit `http://127.0.0.1:5000/` for the public OmaSales marketing site. The compiled Flutter Web staff application is available under `http://127.0.0.1:5000/webapp/`. The former `/classic` Flask/Jinja interface has been retired; old `/classic` bookmarks redirect to the Flutter application.

## OmaSales update 1.2 — marketing, SEO and conversion

The public marketing layer now includes:
- lightweight Flask-rendered marketing pages with no blocking third-party scripts;
- a single primary above-the-fold product CTA;
- programmatic business use-case pages, including pharmacy;
- an SEO guide funnel at `/blog` with article pages;
- a transparent `/pricing` page that does not invent commercial prices;
- a public `/status` page backed by a live database health probe;
- canonical URLs, robots.txt, sitemap.xml, Open Graph/Twitter metadata and Schema.org structured data.

Real testimonials, live customer activity, final pricing, a sub-45-second product demo, a custom production domain, and historical uptime monitoring still require real business inputs or external service configuration; the marketing code deliberately does not fabricate any of these.

## What's built

| Stage | Current implementation |
|---|---|
| 1 | PostgreSQL schema, migrations, generated product CBM/volumetric fields, atomic sales/inventory transactions. |
| 2 | Authentication, logout/password change, Flask-Admin, role-based access, protected CRUD, stock audit trail. |
| 3 | Admin/staff boundaries, immutable audit log, audited sensitive operations, mobile idempotency and offline actor attribution. |
| 4 | Android/iOS-capable local biometric gate with password fallback, Firebase Cloud Messaging device registration, notification outbox, batch-arrival push events and shipment-specific Android notification sounds. |
| 5 | Green/white brand system, light/dark/sunrise themes, responsive desktop/mobile layouts, operational dashboard KPIs, reports/CSV, offline/sync states, PDF branding/watermarks, Flutter Web and Android parity, Team Chat, push notifications, landed-cost pricing and shipment workflows. |

### Sensitive-action verification

- Classic Flask settings changes require the user's current password on every save.
- Flutter/webapp sensitive changes request biometric verification on supported native devices.
- If native biometric hardware is unavailable, fails, or is cancelled, the mobile/webapp offers password verification against the authenticated server account.
- Administrative authorization remains enforced server-side; biometric verification is an additional user-presence check, not a replacement for account authorization.

### Notifications

Firebase Cloud Messaging is used for push delivery. Notification intent is written to the transactional outbox with the business event, so a temporary Firebase outage does not discard the notification. Android batch-arrival notifications use a short sea-shipment horn or airport-style arrival sound; ordinary app notifications use a short scanner-style confirmation sound.

## Key calculated fields (never entered manually)

- `products.cbm` = L × W × H / 1,000,000 (DB-generated)
- `products.volumetric_kg` = L × W × H / 5,000 (DB-generated)
- `sale_items.line_shipping_estimate` = line_cbm × courier_rates.rate_per_cbm (by customer state)
- `sales.profit` = subtotal − Σ(unit_cost × qty) − estimated_shipping_cost
- `shipping.chargeable_weight_kg` = MAX(Σ actual_weight×qty, Σ volumetric_kg×qty)

## Deploying to Render

1. Push this repo to GitHub.
2. On Render: New → Web Service → connect the repo. Render will read `render.yaml`
   automatically (Build Command, Start Command, and health check are already set).
3. In the Render dashboard, set these environment variables manually (they're
   intentionally left out of `render.yaml` so no secret is ever committed):
   - `SECRET_KEY` — any random string
   - `DATABASE_URL` — your Neon connection string
   - `ADMIN_USERNAME`, `ADMIN_PASSWORD`
4. Deploy. The build command runs `flask db upgrade oma20261006_push_channels` automatically on every deploy
   (safe — already-applied migrations are skipped).
5. On a new database only, open the Render Shell and run `flask seed-admin` once to create the configured admin.
   Use `flask seed-admin --reset` only when you explicitly want to reset that admin password.
6. Visit your Render URL. The Flutter Web staff application is served from `/`; `/webapp/` remains available as its explicit SPA path. The former `/classic` interface is retired. `/healthz` returns `{"status": "ok"}` for uptime monitoring.

## Notes

- `.env` is git-ignored — never commit real credentials. `.env.example` is the template.
- All money values are stored as `NUMERIC`, not floats — no rounding drift.
- Sale/SaleItem/Shipping cannot be hand-created or hand-edited from the Flask-Admin
  CRUD screens — only through `/sales/new` and `/shipping/new/<sale_id>`, so totals,
  stock, and the audit trail (`stock_log`) can never drift out of sync.

## Cloud Android build (phone/Chromebook friendly)

The legacy Flask/Jinja staff website is no longer registered or served. Staff use Flutter Web/Android through the shared `/api/v1/*` backend.\n\nThe repository includes `.github/workflows/build-oma-apk.yml`. It builds the Flutter Android APK/AAB in GitHub Actions, so Android Studio/Flutter do not need to be installed locally. The workflow is manual (`workflow_dispatch`) and performs backend/migration/API compatibility checks before analyzing and building.

## Update 1.2 scope

Oma is a private business operations system for the owner and staff of one business. It is not a multi-business SaaS platform. Update 1.2 therefore focuses on staff authentication, products, inventory, sales, offline/sync operation, batches, deliveries, shipping, reports, notifications and team communication. Customer accounts, public checkout, public product browsing, SaaS subscriptions, multi-business workspaces and marketing/SEO surfaces are deferred to the future public webstore phase. The underlying product, inventory, sales and API architecture is kept reusable for that later phase.
