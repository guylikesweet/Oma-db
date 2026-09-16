# Inventory & Shipping Admin

Flask + Postgres app: enter raw product dimensions and sale details, and CBM,
volumetric weight, shipping estimates, and profit are all calculated automatically.

## Stack
- Python 3.11, Flask 3, Flask-Admin, Flask-Login, Flask-SQLAlchemy, Flask-Migrate
- Database: Postgres (Neon — free tier, does not expire or delete data on inactivity)
- Hosting: Render Web Service + Gunicorn
- Auth: single admin user, session-based login

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
flask db upgrade                # creates all 7 tables on your database
flask seed-admin                # creates/resets the admin login from .env

flask run
```

Visit `http://127.0.0.1:5000/` — it redirects to `/admin/`, which redirects to
`/login` if you're not signed in yet.

## What's built (Stages 1–5)

| Stage | Contents |
|---|---|
| 1 | DB schema (7 tables, Postgres `GENERATED ALWAYS AS` columns for `cbm`/`volumetric_kg`), migrations |
| 2 | Login/logout/change-password, Flask-Admin panel (locked behind auth), Products CRUD, audited stock adjustments |
| 3 | Sale creation (`/sales/new`): line-item totals, shipping estimate, profit, stock deduction — all atomic; sale cancellation restocks inventory |
| 4 | Shipping (`/shipping/new/<sale_id>`): chargeable weight = MAX(actual, volumetric), status flow auto-updates the parent sale; shipment search by tracking # or state; dashboard with 4 KPIs + 30-day sales chart |
| 5 | Sales report with date-range filter, CSV export (sales/shipping/inventory), Render deployment config |

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
4. Deploy. The build command runs `flask db upgrade` automatically on every deploy
   (safe — already-applied migrations are skipped).
5. Open the Render Shell tab once and run `flask seed-admin` to create your admin login.
6. Visit your Render URL. `/healthz` returns `{"status": "ok"}` for uptime monitoring.

## Notes

- `.env` is git-ignored — never commit real credentials. `.env.example` is the template.
- All money values are stored as `NUMERIC`, not floats — no rounding drift.
- Sale/SaleItem/Shipping cannot be hand-created or hand-edited from the Flask-Admin
  CRUD screens — only through `/sales/new` and `/shipping/new/<sale_id>`, so totals,
  stock, and the audit trail (`stock_log`) can never drift out of sync.
