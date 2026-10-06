from flask import Flask, jsonify
from app.csrf import init_csrf


def make_app():
    app = Flask(__name__)
    app.secret_key = "test-secret"
    init_csrf(app)

    @app.route("/mutate", methods=["POST"])
    def mutate():
        return jsonify({"ok": True})

    @app.route("/api/mutate", methods=["POST"])
    def api_mutate():
        return jsonify({"ok": True})

    return app


def test_same_origin_post_is_allowed():
    client = make_app().test_client()
    response = client.post(
        "/mutate",
        headers={"Origin": "http://localhost"},
    )
    assert response.status_code == 200


def test_cross_origin_post_is_rejected():
    client = make_app().test_client()
    response = client.post(
        "/mutate",
        headers={"Origin": "https://evil.example"},
    )
    assert response.status_code == 403


def test_session_csrf_token_is_allowed_without_origin():
    app = make_app()
    client = app.test_client()

    with client.session_transaction() as session:
        # init_csrf exposes the same token through the Jinja global, but the
        # request guard creates it lazily when the request is evaluated.
        session["classic_csrf_token"] = "known-token"

    response = client.post(
        "/mutate",
        data={"_csrf_token": "known-token"},
    )
    assert response.status_code == 200


def test_api_prefix_is_exempt_from_classic_csrf():
    client = make_app().test_client()
    response = client.post(
        "/api/mutate",
        headers={"Origin": "https://evil.example"},
    )
    assert response.status_code == 200
