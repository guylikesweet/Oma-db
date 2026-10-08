# Inventory & Shipping Admin

Flask + Postgres app: enter raw product dimensions and sale details, and CBM,
volumetric weight, shipping estimates, and profit are all calculated automatically.

## Stack
- Python 3.11, Flask 3, Flask-Admin, Flask-Login, Flask-SQLAlchemy, Flask-Migrate, Flask-Limiter
- Database: Postgres (Neon — free tier, does not expire or delete data on inactivity)
- Hosting: Render Web Service + Gunicorn
- Auth: Flask session login for the legacy `/classic` interface plus bearer-token authentication for Flutter Web/Android.

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

Visit `http://127.0.0.1:5000/` for the public OmaSales site. Open `http://127.0.0.1:5000/webapp/` for the Flutter Web application. The legacy Flask/Jinja interface is available under `/classic`.

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
6. Visit your Render URL. The public OmaSales marketing site is served from `/`; the Flutter Web application is available at `/webapp/`. `/healthz` returns `{"status": "ok"}` for uptime monitoring.

## Notes

- `.env` is git-ignored — never commit real credentials. `.env.example` is the template.
- All money values are stored as `NUMERIC`, not floats — no rounding drift.
- Sale/SaleItem/Shipping cannot be hand-created or hand-edited from the Flask-Admin
  CRUD screens — only through `/sales/new` and `/shipping/new/<sale_id>`, so totals,
  stock, and the audit trail (`stock_log`) can never drift out of sync.

## Cloud Android build (phone/Chromebook friendly)

The repository includes `.github/workflows/build-oma-apk.yml`. It builds the Flutter Android APK/AAB in GitHub Actions, so Android Studio/Flutter do not need to be installed locally. The workflow is manual (`workflow_dispatch`) and performs backend/migration/API compatibility checks before analyzing and building.
