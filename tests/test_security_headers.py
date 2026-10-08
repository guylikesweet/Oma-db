from app import create_app


def test_permissions_policy_allows_same_origin_microphone():
    app = create_app()
    with app.test_client() as client:
        response = client.get("/healthz")
        policy = response.headers.get("Permissions-Policy", "")
        assert "microphone=(self)" in policy
        assert "microphone=()" not in policy
