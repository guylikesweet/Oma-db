"""
Serves the compiled Flutter Web build (app/static/webapp/, committed by
build-oma-web.yml) under /webapp/. The same compiled Flutter Web application is also exposed
from the root route by app/__init__.py, so the Flutter Web client is now the
main application while /classic remains the legacy Jinja interface.

Not @login_required: this route only ever hands back static HTML/JS. The
Flutter app authenticates itself against /api/v1/auth/login with its own
login screen and a bearer token — gating this route with Flask-Login's
session-based login would just redirect an unauthenticated visitor to the
OLD Jinja login page instead, which is wrong for a client that manages its
own auth state.
"""
import os

from flask import Blueprint, send_from_directory

webapp_bp = Blueprint("webapp", __name__)

WEBAPP_DIR = os.path.join(os.path.dirname(__file__), "static", "webapp")


@webapp_bp.route("/firebase-messaging-sw.js")
def serve_firebase_messaging_worker():
    # Firebase Web Messaging looks for this exact origin-root filename when
    # no custom ServiceWorkerRegistration is supplied by the Flutter plugin.
    response = send_from_directory(WEBAPP_DIR, "firebase-messaging-sw.js")
    response.headers["Cache-Control"] = "no-cache"
    return response


@webapp_bp.route("/webapp/")
@webapp_bp.route("/webapp/<path:subpath>")
def serve_webapp(subpath=""):
    # A real, existing file (main.dart.js, assets/*, canvaskit/*, etc.) is
    # served directly. Anything else — including every client-side Flutter
    # route like /webapp/some/deep/link — falls back to index.html so
    # Flutter's own router handles it; this is the standard SPA pattern.
    if subpath:
        candidate = os.path.join(WEBAPP_DIR, subpath)
        if os.path.isfile(candidate):
            response = send_from_directory(WEBAPP_DIR, subpath)
            response.headers.setdefault("Cache-Control", "public, max-age=86400")
            return response

    # The SPA entrypoint must remain revalidated so a new deployment can
    # immediately point browsers at its new hashed JavaScript assets.
    response = send_from_directory(WEBAPP_DIR, "index.html")
    response.headers["Cache-Control"] = "no-cache"
    return response
