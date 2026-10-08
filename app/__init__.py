from flask import Flask, redirect, url_for, render_template, session, request, flash, g
import click
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_login import LoginManager, login_required
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from app.csrf import init_csrf
from datetime import datetime, timedelta
from sqlalchemy import text as sa_text
import os
import time
import uuid

db = SQLAlchemy()
migrate = Migrate()
login_manager = LoginManager()
limiter = Limiter(
    key_func=get_remote_address,
    default_limits=[],
    storage_uri=os.environ.get("RATELIMIT_STORAGE_URI", "memory://"),
    headers_enabled=True,
)


def create_app(config_object="config.Config"):
    app = Flask(__name__)
    app.config.from_object(config_object)
    app.permanent_session_lifetime = timedelta(minutes=30)

    @app.before_request
    def attach_request_id():
        """Give every request a short correlation ID for logs and support diagnostics."""
        incoming = (request.headers.get("X-Request-ID") or "").strip()
        g.request_id = incoming[:128] if incoming else uuid.uuid4().hex

    @app.after_request
    def expose_request_id(response):
        response.headers["X-Request-ID"] = getattr(g, "request_id", "")
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
        response.headers.setdefault(
            "Permissions-Policy",
            "camera=(), microphone=(), geolocation=()",
        )

        # Public/static assets may be cached, but never apply this policy to
        # API responses or the Flutter SPA entrypoint.
        if (
            request.path.startswith("/static/")
            or request.path.startswith("/webapp/")
        ):
            lower_path = request.path.lower()
            if not lower_path.endswith("/") and not lower_path.endswith("index.html"):
                response.headers.setdefault(
                    "Cache-Control", "public, max-age=86400"
                )
        return response

    db.init_app(app)
    migrate.init_app(app, db)
    login_manager.init_app(app)
    limiter.init_app(app)
    init_csrf(app)
    login_manager.login_view = "auth.login"
    @app.before_request
    def enforce_classic_inactivity_timeout():
        # Flask-Login sessions are separate from the mobile bearer-token API.
        # Refresh the activity timestamp on every authenticated browser request.
        if not request.path.startswith("/api/"):
            from flask_login import current_user, logout_user
            if current_user.is_authenticated:
                now = time.time()
                last = session.get("last_activity")
                if last is not None and now - float(last) >= 30 * 60:
                    user = current_user
                    from app.services.audit import record_audit
                    record_audit(
                        "logout.timeout",
                        target_type="user",
                        target_id=user.id,
                        details={"source": "classic", "timeout_minutes": 30},
                        user=user,
                    )
                    db.session.commit()
                    logout_user()
                    session.clear()
                    flash("You were logged out after 30 minutes of inactivity.", "error")
                    return redirect(url_for("auth.login", next=request.url))
                session["last_activity"] = now
                session.permanent = True


    # /api/* is called from the mobile app (no browser, no CORS involved)
    # and now also from the Flutter Web build — browsers enforce CORS on
    # any cross-origin fetch, so without this every request from the web
    # build fails before it even reaches these routes. Every /api/* route
    # authenticates via an Authorization: Bearer <token> header, not
    # cookies, so an open origin policy here doesn't expose any session.
    cors_env = os.environ.get("OMA_CORS_ORIGINS", "").strip()
    if cors_env:
        cors_origins = [
            origin.strip()
            for origin in cors_env.split(",")
            if origin.strip()
        ]
    elif os.environ.get("DATABASE_URL"):
        # Production Flutter Web is served by this Flask application, so it
        # does not need cross-origin API access. Require explicit origins for
        # any separately hosted web client.
        cors_origins = []
    else:
        cors_origins = "*"

    CORS(app, resources={r"/api/*": {"origins": cors_origins}})

    with app.app_context():
        from app import models  # noqa: F401  (register models for migrations)

        from app.auth import auth_bp
        app.register_blueprint(auth_bp)

        from app.sales import sales_bp
        app.register_blueprint(sales_bp)

        from app.batches import batches_bp
        app.register_blueprint(batches_bp)

        from app.delivery import delivery_bp
        app.register_blueprint(delivery_bp)

        from app.data_tools import data_tools_bp
        app.register_blueprint(data_tools_bp)

        from app.reports import reports_bp
        app.register_blueprint(reports_bp)

        from app.api import api_bp
        app.register_blueprint(api_bp)

        from app.classic_chat import classic_chat_bp
        app.register_blueprint(classic_chat_bp)

        from app.settings import settings_bp
        app.register_blueprint(settings_bp)

        from app.webapp import webapp_bp
        app.register_blueprint(webapp_bp)

        from app.verify import verify_bp
        app.register_blueprint(verify_bp)

        from app.admin_views import init_admin
        init_admin(app)

        register_cli(app)

    def public_base_url():
        """Return the configured canonical public origin for SEO URLs."""
        configured = os.environ.get("OMA_PUBLIC_BASE_URL", "").strip().rstrip("/")
        if configured.startswith(("https://", "http://")):
            return configured
        if configured:
            app.logger.warning("Ignoring invalid OMA_PUBLIC_BASE_URL; expected an http(s) URL.")
        return request.url_root.rstrip("/")

    @app.errorhandler(404)
    def handle_not_found(error):
        if request.path.startswith("/api/"):
            return {"error": "Not found.", "message": "The requested API endpoint does not exist.", "request_id": getattr(g, "request_id", "unknown")}, 404
        return error

    @app.errorhandler(405)
    def handle_method_not_allowed(error):
        if request.path.startswith("/api/"):
            return {"error": "Method not allowed.", "message": "This HTTP method is not supported for the requested API endpoint.", "request_id": getattr(g, "request_id", "unknown")}, 405
        return error

    @app.errorhandler(415)
    def handle_unsupported_media_type(error):
        if request.path.startswith("/api/"):
            return {"error": "Unsupported media type.", "message": "This API endpoint expects a JSON request body.", "request_id": getattr(g, "request_id", "unknown")}, 415
        return error

    @app.errorhandler(500)
    def handle_internal_error(error):
        if request.path.startswith("/api/"):
            app.logger.exception("Unhandled application exception request_id=%s", getattr(g, "request_id", "unknown"))
            db.session.rollback()
            return {"error": "Internal server error.", "message": "The server could not complete this request.", "request_id": getattr(g, "request_id", "unknown")}, 500
        raise error

    @app.route("/")
    def root():
        use_cases = use_cases_for_marketing()
        schema = {
            "@context": "https://schema.org",
            "@graph": [
                {"@type": "Organization", "name": "OmaSales", "url": public_base_url()},
                {"@type": "SoftwareApplication", "name": "OmaSales", "applicationCategory": "BusinessApplication", "operatingSystem": "Android, Web", "description": "Sales, inventory, shipping and delivery management for businesses."},
                {"@type": "WebSite", "name": "OmaSales", "url": public_base_url()},
                {"@type": "FAQPage", "mainEntity": [
                    {"@type": "Question", "name": "Does OmaSales work when the internet is unavailable?", "acceptedAnswer": {"@type": "Answer", "text": "The mobile application is designed around local data and an offline write queue, then synchronizes changes when connectivity returns."}},
                    {"@type": "Question", "name": "Can OmaSales manage shipping?", "acceptedAnswer": {"@type": "Answer", "text": "OmaSales supports shipment batches, sea and air shipping workflows, shipping rates, delivery preparation and customer shipping settlement."}},
                    {"@type": "Question", "name": "Can I use OmaSales on Android and the web?", "acceptedAnswer": {"@type": "Answer", "text": "Yes. OmaSales includes Flutter Android and Flutter Web clients backed by the same Flask API."}}
                ]}
            ]
        }
        return render_template("marketing_home.html", use_cases=use_cases, year=datetime.utcnow().year,
                               canonical_url=public_base_url() + "/", og_image=public_base_url() + url_for("static", filename="logo.png"),
                               schema=schema)


    @app.route("/use-case/<slug>")
    def use_case(slug):
        item = next((x for x in use_cases_for_marketing() if x["slug"] == slug), None)
        if item is None:
            from flask import abort
            abort(404)
        schema = {
            "@context": "https://schema.org",
            "@type": "WebPage",
            "name": item["seo_title"],
            "description": item["description"],
            "url": public_base_url() + request.path,
            "isPartOf": {"@type": "WebSite", "name": "OmaSales", "url": public_base_url()},
        }
        return render_template("marketing_use_case.html", item=item, canonical_url=public_base_url() + request.path, 
                               og_image=url_for("static", filename="logo.png", _external=True),
                               schema=schema)

    @app.route("/robots.txt")
    def robots_txt():
        from flask import Response
        base = public_base_url()
        body = f"User-agent: *\nAllow: /\nAllow: /use-case/\nDisallow: /api/\nDisallow: /classic/\nDisallow: /webapp/\nSitemap: {base}/sitemap.xml\n"
        return Response(body, mimetype="text/plain")

    @app.route("/sitemap.xml")
    def sitemap_xml():
        from flask import Response
        from xml.sax.saxutils import escape
        base = public_base_url()
        urls = [base + "/", *[base + "/use-case/" + x["slug"] for x in use_cases_for_marketing()]]
        xml = '<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' + "".join(f"<url><loc>{escape(u)}</loc></url>" for u in urls) + "</urlset>"
        return Response(xml, mimetype="application/xml")


    @app.route("/classic")
    @login_required
    def classic_home():
        from app.services.dashboard import get_kpis
        return render_template("home.html", kpis=get_kpis())

    @app.route("/healthz")
    def healthz():
        """Render health probe: report healthy only when the DB is reachable."""
        try:
            db.session.execute(sa_text("SELECT 1"))
            db.session.rollback()
            return {"status": "ok", "database": "ok"}, 200
        except Exception:
            db.session.rollback()
            app.logger.exception("Health check database probe failed")
            return {"status": "degraded", "database": "unavailable"}, 503

    return app


def register_cli(app):
    @app.cli.command("seed-admin")
    @click.option(
        "--reset",
        is_flag=True,
        help="Reset the existing configured admin password and invalidate its sessions.",
    )
    def seed_admin(reset=False):
        """Create the configured admin if missing; only reset it when explicitly requested."""
        from werkzeug.security import generate_password_hash
        from app.models import User

        username = app.config["ADMIN_USERNAME"]
        password = app.config["ADMIN_PASSWORD"]

        user = User.query.filter_by(username=username).first()
        if user:
            if reset:
                user.password_hash = generate_password_hash(password)
                user.api_token = None
                user.api_last_activity_at = None
                user.biometric_credential_hash = None
                print(f"Reset password for existing admin user '{username}'.")
            else:
                print(f"Admin user '{username}' already exists; leaving its password unchanged.")
        else:
            is_first_ever = User.query.count() == 0
            user = User(
                username=username,
                password_hash=generate_password_hash(password),
                role=User.ROLE_ADMIN,
                is_primary_admin=is_first_ever,
            )
            db.session.add(user)
            print(f"Created admin user '{username}'.")

        db.session.commit()

    @app.cli.command("chat-cleanup")
    def chat_cleanup():
        """Delete stored chat photo bytes older than 30 days."""
        from app.api import _chat_cleanup_expired_photos

        before = __import__("app.models", fromlist=["ChatMessage"]).ChatMessage.query.filter(
            __import__("app.models", fromlist=["ChatMessage"]).ChatMessage.attachment_data.isnot(None),
            __import__("app.models", fromlist=["ChatMessage"]).ChatMessage.attachment_created_at < (
                __import__("datetime", fromlist=["datetime"]).datetime.utcnow()
                - __import__("datetime", fromlist=["timedelta"]).timedelta(days=30)
            ),
        ).count()
        _chat_cleanup_expired_photos()
        print(f"Removed stored bytes from {before} expired chat photo(s).")

    @app.cli.command("api-token")
    def api_token():
        """Rotate and print a fresh mobile API token for the configured admin."""
        import hashlib
        import secrets
        from app.models import User

        username = app.config["ADMIN_USERNAME"]
        user = User.query.filter_by(username=username).first()
        if not user:
            print(f"No user '{username}' found — run `flask seed-admin` first.")
            return

        raw_token = secrets.token_hex(32)
        user.api_token = hashlib.sha256(raw_token.encode("utf-8")).hexdigest()
        user.api_last_activity_at = None
        user.biometric_credential_hash = None
        db.session.commit()
        print(f"API token for '{username}': {raw_token}")


def use_cases_for_marketing():
    return [
        {"name": "Gadgets & Electronics", "slug": "gadgets-electronics", "headline": "Sales and inventory management for gadget businesses", "seo_title": "Sales App for Gadget & Electronics Businesses in Nigeria", "description": "Manage gadgets, electronics, accessories, sales, stock and profit with OmaSales.", "points": ["Track fast-moving gadgets and accessories.", "Record sales while keeping inventory accurate.", "See costs, shipping and profit in one dashboard."], "body": "OmaSales helps gadget and electronics businesses keep products, sales, stock and shipping operations together as they grow."},
        {"name": "Supermarket", "slug": "supermarket", "headline": "A sales and stock app for supermarkets", "seo_title": "Sales App for Supermarkets in Nigeria", "description": "Manage supermarket sales, inventory, stock movements and business performance with OmaSales.", "points": ["Keep stock quantities visible.", "Record sales quickly.", "Monitor low-stock items and business KPIs."], "body": "Designed for busy retail operations where accurate stock and fast sales records matter."},
        {"name": "Fashion Store", "slug": "fashion-store", "headline": "Inventory and sales management for fashion stores", "seo_title": "Sales App for Fashion Stores in Nigeria", "description": "Track fashion inventory, sales, costs and stock with OmaSales.", "points": ["Organize products and stock.", "Record customer sales and totals.", "Understand costs and profit."], "body": "Keep your fashion business numbers together as your product range and sales volume grow."},
        {"name": "Phone Accessories", "slug": "phone-accessories", "headline": "Sales and stock management for phone accessory shops", "seo_title": "Sales App for Phone Accessories Businesses in Nigeria", "description": "Manage fast-moving phone accessories, sales and stock with OmaSales.", "points": ["Track fast-moving products.", "Reduce stock surprises.", "Record sales and monitor performance."], "body": "OmaSales is suited to businesses with many small, fast-moving products and frequent stock changes."},
        {"name": "Mini Mart", "slug": "mini-mart", "headline": "Simple inventory and sales management for mini marts", "seo_title": "Sales App for Mini Marts in Nigeria", "description": "Run mini-mart sales and inventory from one business management app.", "points": ["Track inventory.", "Record daily sales.", "Monitor low stock and profit."], "body": "Use one system to keep daily retail operations visible and easier to control."},
        {"name": "Wholesaler", "slug": "wholesaler", "headline": "Sales, inventory and shipping management for wholesalers", "seo_title": "Sales App for Wholesalers in Nigeria", "description": "Manage wholesale sales, inventory, shipping batches and deliveries with OmaSales.", "points": ["Track stock and sales.", "Manage shipment batches and shipping costs.", "Prepare deliveries and settle shipping payments."], "body": "OmaSales combines inventory and sales with the shipping workflows needed by trading and wholesale businesses."},
    ]
