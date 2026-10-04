"""
Admin-only access control.

The app has two kinds of users: "admin" and "staff" (see User.role in
app/models.py). Admins can edit company settings, manage users, mark
shipment batches arrived, edit monthly shipping rates, and other sensitive
actions. Staff cannot. This module is the single place that rule is
enforced, so the web app, /admin, and the JSON API (used by the mobile app
and the compiled Flutter "webapp") all agree on it.
"""
from functools import wraps
import time

from flask import redirect, url_for, flash, request, jsonify, g, session
from flask_login import current_user


def admin_required(f):
    """For normal (session-login) web routes. Redirects to login if signed
    out, or back where they came from with a flash message if signed in but
    not an admin."""
    @wraps(f)
    def wrapper(*args, **kwargs):
        if not current_user.is_authenticated:
            return redirect(url_for("auth.login", next=request.url))
        if not current_user.is_admin:
            flash("That action is restricted to admins.", "error")
            return redirect(request.referrer or url_for("classic_home"))
        return f(*args, **kwargs)
    return wrapper


def require_admin_api(f):
    """For /api/v1/* routes. Must be applied AFTER @require_api_token so
    g.api_user is already set."""
    @wraps(f)
    def wrapper(*args, **kwargs):
        if not getattr(g, "api_user", None) or not g.api_user.is_admin:
            return jsonify({"error": "That action is restricted to admins."}), 403
        return f(*args, **kwargs)
    return wrapper


REAUTH_TTL_SECONDS = 10 * 60


def password_recently_confirmed():
    if not current_user.is_authenticated:
        return False
    try:
        return time.time() - float(session.get("reauth_at", 0)) <= REAUTH_TTL_SECONDS
    except (TypeError, ValueError):
        return False


def reauth_url(next_url):
    return url_for("auth.reauthenticate", next=next_url)
