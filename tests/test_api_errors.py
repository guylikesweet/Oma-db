from app import create_app


class TestConfig:
    SECRET_KEY = "test-secret"
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SESSION_COOKIE_SECURE = False
    TESTING = True
    PROPAGATE_EXCEPTIONS = False


def make_app():
    app = create_app(TestConfig)

    @app.route("/api/test-error")
    def api_test_error():
        raise RuntimeError("boom")

    @app.route("/classic-test-error")
    def classic_test_error():
        raise RuntimeError("boom")

    return app


def test_unknown_api_route_returns_json_request_id():
    client = make_app().test_client()
    response = client.get("/api/v1/does-not-exist")

    assert response.status_code == 404
    assert response.is_json
    payload = response.get_json()
    assert payload["error"] == "Not found."
    assert payload["request_id"]


def test_api_wrong_method_returns_json_request_id():
    client = make_app().test_client()
    response = client.get("/api/v1/auth/login")

    assert response.status_code == 405
    assert response.is_json
    payload = response.get_json()
    assert payload["error"] == "Method not allowed."
    assert payload["request_id"]


def test_api_internal_error_returns_json_request_id():
    client = make_app().test_client()
    response = client.get("/api/test-error")

    assert response.status_code == 500
    assert response.is_json
    payload = response.get_json()
    assert payload["error"] == "Internal server error."
    assert payload["request_id"]


def test_non_api_internal_error_keeps_html_response():
    client = make_app().test_client()
    response = client.get("/classic-test-error")

    assert response.status_code == 500
    assert not response.is_json
    assert b"Internal Server Error" in response.data
