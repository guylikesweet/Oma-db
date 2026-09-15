from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_login import LoginManager

db = SQLAlchemy()
migrate = Migrate()
login_manager = LoginManager()


def create_app(config_object="config.Config"):
    app = Flask(__name__)
    app.config.from_object(config_object)

    db.init_app(app)
    migrate.init_app(app, db)
    login_manager.init_app(app)
    login_manager.login_view = "auth.login"

    with app.app_context():
        from app import models  # noqa: F401  (register models for migrations)

        from app.auth import auth_bp
        app.register_blueprint(auth_bp)

        from app.admin_views import init_admin
        init_admin(app)

        register_cli(app)

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
            user = User(username=username, password_hash=generate_password_hash(password))
            db.session.add(user)
            print(f"Created admin user '{username}'.")

        db.session.commit()
