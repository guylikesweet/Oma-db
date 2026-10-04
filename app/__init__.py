from flask import Flask, redirect, url_for, render_template, session, request, flash
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_login import LoginManager, login_required
from flask_cors import CORS
from datetime import timedelta
import time

db = SQLAlchemy()
migrate = Migrate()
login_manager = LoginManager()


def create_app(config_object="config.Config"):
    app = Flask(__name__)
    app.config.from_object(config_object)
    app.permanent_session_lifetime = timedelta(minutes=30)

    db.init_app(app)
    migrate.init_app(app, db)
    login_manager.init_app(app)
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
    CORS(app, resources={r"/api/*": {"origins": "*"}})

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

        from app.settings import settings_bp
        app.register_blueprint(settings_bp)

        from app.webapp import webapp_bp
        app.register_blueprint(webapp_bp)

        from app.verify import verify_bp
        app.register_blueprint(verify_bp)

        from app.admin_views import init_admin
        init_admin(app)

        register_cli(app)

    @app.route("/")
    def root():
        # The Flutter web app is now the main site. Its index.html declares
        # <base href="/webapp/">, so every asset it loads still resolves
        # under /webapp/ (served by webapp_bp) - no rebuild needed. The app
        # handles its own login, hence no @login_required here.
        from app.webapp import serve_webapp
        return serve_webapp("")

    @app.route("/classic")
    @login_required
    def classic_home():
        from app.services.dashboard import get_kpis
        return render_template("home.html", kpis=get_kpis())

    @app.route("/healthz")
    def healthz():
        return {"status": "ok"}, 200

    return app


def register_cli(app):
    @app.cli.command("seed-admin")
    def seed_admin():
        """Create (or reset) the admin user from ADMIN_USERNAME / ADMIN_PASSWORD env vars."""
        from werkzeug.security import generate_password_hash
        from app.models import User

        username = app.config["ADMIN_USERNAME"]
        password = app.config["ADMIN_PASSWORD"]

        user = User.query.filter_by(username=username).first()
        if user:
            user.password_hash = generate_password_hash(password)
            print(f"Updated password for existing admin user '{username}'.")
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

    @app.cli.command("api-token")
    def api_token():
        """Show the admin user's API token (used by the mobile app), generating one if it doesn't exist yet."""
        import secrets
        from app.models import User

        username = app.config["ADMIN_USERNAME"]
        user = User.query.filter_by(username=username).first()
        if not user:
            print(f"No user '{username}' found — run `flask seed-admin` first.")
            return

        if not user.api_token:
            user.api_token = secrets.token_hex(32)
            db.session.commit()
            print("Generated a new API token.")

        print(f"API token for '{username}': {user.api_token}")
