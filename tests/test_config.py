import importlib


def test_production_requires_valid_public_base_url(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql://example.invalid/db")
    monkeypatch.setenv("SECRET_KEY", "test-secret")
    monkeypatch.setenv("ADMIN_USERNAME", "admin")
    monkeypatch.setenv("ADMIN_PASSWORD", "password")
    monkeypatch.setenv("OMA_PUBLIC_BASE_URL", "not-a-url")

    config_module = None
    try:
        try:
            config_module = importlib.import_module("config")
        except RuntimeError as exc:
            assert "OMA_PUBLIC_BASE_URL" in str(exc)
        else:
            importlib.reload(config_module)
            raise AssertionError("Config accepted an invalid production public base URL")
    finally:
        monkeypatch.setenv("OMA_PUBLIC_BASE_URL", "https://oma.example")
        config_module = importlib.import_module("config")
        importlib.reload(config_module)


def test_production_public_base_url_is_exposed(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql://example.invalid/db")
    monkeypatch.setenv("SECRET_KEY", "test-secret")
    monkeypatch.setenv("ADMIN_USERNAME", "admin")
    monkeypatch.setenv("ADMIN_PASSWORD", "password")
    monkeypatch.setenv("OMA_PUBLIC_BASE_URL", "https://oma.example")

    import config

    importlib.reload(config)
    try:
        assert config.Config.OMA_PUBLIC_BASE_URL == "https://oma.example"
    finally:
        importlib.reload(config)
