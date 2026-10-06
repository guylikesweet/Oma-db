from flask import Blueprint, render_template, redirect, url_for, request, flash, session
from flask_login import login_user, logout_user, login_required, current_user
from werkzeug.security import generate_password_hash, check_password_hash
import time
import secrets

from app import login_manager, limiter
from app.models import User
from app import db
from app.services.audit import record_audit

auth_bp = Blueprint("auth", __name__, template_folder="templates/auth")


@auth_bp.before_app_request
def enforce_classic_inactivity_timeout():
    """Enforce the same 30-minute inactivity rule for Flask web sessions."""
    if not current_user.is_authenticated:
        return None

    now = time.time()
    last = session.get("last_activity")
    if last is not None and now - float(last) >= 30 * 60:
        user = current_user
        record_audit(
            "logout.timeout",
            target_type="user",
            target_id=user.id,
            outcome="success",
            details={"source": "classic", "timeout_minutes": 30},
            user=user,
        )
        db.session.commit()
        logout_user()
        session.pop("last_activity", None)
        session.pop("reauth_at", None)
        flash("Your session expired after 30 minutes of inactivity. Please sign in again.", "error")
        return redirect(url_for("auth.login", next=request.full_path))

    session["last_activity"] = now
    return None


@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))


@auth_bp.route("/login", methods=("GET", "POST"))
@limiter.limit("10 per minute", methods=["POST"])
def login():
    if current_user.is_authenticated:
        return redirect(url_for("classic_home"))

    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")

        user = User.query.filter_by(username=username).first()
        if user and user.is_active and check_password_hash(user.password_hash, password):
            login_user(user)
            session.permanent = True
            session["last_activity"] = time.time()
            record_audit(
                "login",
                target_type="user",
                target_id=user.id,
                details={"source": "classic"},
                user=user,
            )
            db.session.commit()
            next_page = request.args.get("next")
            return redirect(next_page or url_for("classic_home"))

        flash("Invalid username or password.", "error")

    return render_template("auth/login.html")


@auth_bp.route("/logout")
@login_required
def logout():
    user = current_user
    record_audit(
        "logout",
        target_type="user",
        target_id=user.id,
        details={"source": "classic"},
        user=user,
    )
    db.session.commit()
    logout_user()
    return redirect(url_for("auth.login"))


@auth_bp.route("/reauthenticate", methods=("GET", "POST"))
@limiter.limit("20 per minute", methods=["POST"])
@login_required
def reauthenticate():
    next_url = request.args.get("next") or request.form.get("next") or url_for("classic_home")
    if not next_url.startswith("/"):
        next_url = url_for("classic_home")

    if request.method == "POST":
        password = request.form.get("password", "")
        if check_password_hash(current_user.password_hash, password):
            session["reauth_at"] = time.time()
            return redirect(next_url)
        flash("Password verification failed.", "error")

    return render_template("auth/reauthenticate.html", next_url=next_url)


@auth_bp.route("/change-password", methods=("GET", "POST"))
@limiter.limit("10 per minute", methods=["POST"])
@login_required
def change_password():
    if request.method == "POST":
        current_password = request.form.get("current_password", "")
        new_password = request.form.get("new_password", "")
        confirm_password = request.form.get("confirm_password", "")

        if not check_password_hash(current_user.password_hash, current_password):
            flash("Current password is incorrect.", "error")
        elif len(new_password) < 8:
            flash("New password must be at least 8 characters.", "error")
        elif new_password != confirm_password:
            flash("New password and confirmation do not match.", "error")
        else:
            from app import db
            current_user.password_hash = generate_password_hash(new_password)
            current_user.api_token = secrets.token_hex(32)
            current_user.biometric_credential_hash = None
            current_user.api_last_activity_at = None
            record_audit(
                "password.change",
                target_type="user",
                target_id=current_user.id,
                details={"source": "classic"},
                user=current_user,
            )
            db.session.commit()
            flash("Password updated successfully.", "success")
            return redirect(url_for("classic_home"))

    return render_template("auth/change_password.html")
