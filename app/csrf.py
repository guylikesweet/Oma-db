"""CSRF protection for the session-authenticated classic Flask interface.

The mobile/Flutter API is bearer-token authenticated and is intentionally
excluded.  The classic chat bridge has its own request token and is also
excluded so its existing contract remains unchanged.

For ordinary classic POST/PUT/PATCH/DELETE requests we prefer a synchronizer
token when a form/header supplies one, and otherwise require a same-origin
Origin/Referer header.  This protects existing forms without requiring every
legacy template to be rewritten at once.
"""

from urllib.parse import urlparse

from flask import abort, current_app, request, session
import secrets


UNSAFE_METHODS = frozenset({"POST", "PUT", "PATCH", "DELETE"})
EXEMPT_PREFIXES = ("/api/", "/classic/chat/")


def _token():
    token = session.get("classic_csrf_token")
    if not token:
        token = secrets.token_urlsafe(32)
        session["classic_csrf_token"] = token
    return token


def csrf_token():
    """Return the current session CSRF token for templates/AJAX callers."""
    return _token()


def _configured_origins():
    configured = current_app.config.get("OMA_CSRF_ORIGINS", "")
    if isinstance(configured, str):
        return {x.strip().rstrip("/") for x in configured.split(",") if x.strip()}
    return {str(x).strip().rstrip("/") for x in (configured or []) if str(x).strip()}


def _same_origin():
    expected = f"{request.scheme}://{request.host}"
    configured = _configured_origins()
    if configured:
        return expected.rstrip("/") in configured

    origin = request.headers.get("Origin")
    if origin:
        return origin.rstrip("/") == expected.rstrip("/")

    referer = request.headers.get("Referer")
    if referer:
        parsed = urlparse(referer)
        return f"{parsed.scheme}://{parsed.netloc}".rstrip("/") == expected.rstrip("/")

    return False


def _valid_token():
    expected = _token()
    supplied = (
        request.form.get("_csrf_token")
        or request.headers.get("X-CSRF-Token")
        or request.headers.get("X-CSRFToken")
        or ""
    )
    return bool(supplied and secrets.compare_digest(str(supplied), expected))


def protect_request():
    """Reject unsafe cross-site requests to the classic session interface."""
    if request.method not in UNSAFE_METHODS:
        return
    if request.path.startswith(EXEMPT_PREFIXES):
        return

    # The Flutter Web app authenticates with a bearer token under /api and is
    # therefore outside this browser-session CSRF boundary.
    if request.path.startswith("/webapp/"):
        return

    if _valid_token() or _same_origin():
        return

    abort(403, description="Invalid or missing CSRF protection for this request.")


def init_csrf(app):
    app.jinja_env.globals["csrf_token"] = csrf_token
    app.before_request(protect_request)
