from flask import Flask, redirect, url_for, render_template, session, request, flash, g, jsonify, make_response, current_app
import click
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_login import LoginManager, login_required
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from app.csrf import init_csrf
from datetime import timedelta
from sqlalchemy import text as sa_text
from werkzeug.exceptions import HTTPException
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
            "camera=(), microphone=(self), geolocation=()",
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

    @app.errorhandler(HTTPException)
    def handle_http_error(error):
        """Return JSON errors for API clients while keeping staff pages HTML."""
        if request.path.startswith("/api/"):
            api_error_names = {
                400: "Bad request.",
                401: "Unauthorized.",
                403: "Forbidden.",
                404: "Not found.",
                405: "Method not allowed.",
                409: "Conflict.",
                413: "Request is too large.",
                415: "Unsupported media type.",
                429: "Too many requests.",
            }
            return jsonify({
                "error": api_error_names.get(error.code, error.name),
                "message": error.description,
                "request_id": getattr(g, "request_id", "unknown"),
            }), error.code
        return error

    @app.errorhandler(Exception)
    def handle_unexpected_error(error):
        """Return a safe JSON 500 for APIs and a simple HTML 500 for staff pages."""
        if request.path.startswith("/api/"):
            current_app.logger.exception(
                "Unhandled application exception request_id=%s",
                getattr(g, "request_id", "unknown"),
            )
            db.session.rollback()
            return jsonify({
                "error": "Internal server error.",
                "message": "The server could not complete this request.",
                "request_id": getattr(g, "request_id", "unknown"),
            }), 500
        current_app.logger.exception("Unhandled browser exception request_id=%s", getattr(g, "request_id", "unknown"))
        return make_response("Internal Server Error", 500)

    @app.route("/")
    def root():
        """Internal staff entrypoint.

        Oma is currently a private business operations system. The public
        storefront is a future phase, so the root URL must not expose a SaaS
        marketing surface or imply that Oma is a multi-business service.
        """
        return redirect(url_for("classic_home"))

    @app.route("/robots.txt")
    def robots_txt():
        """Keep the private operations application out of search indexes."""
        from flask import Response
        body = "User-agent: *\\nDisallow: /\\n"
        return Response(body, mimetype="text/plain")


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
