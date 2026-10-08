from types import SimpleNamespace

from flask import Flask

from app.services.invoices import verify_url


def test_invoice_verification_uses_canonical_public_base_url(monkeypatch):
    monkeypatch.setenv("OMA_PUBLIC_BASE_URL", "https://oma.example")

    app = Flask(__name__)
    app.config["SECRET_KEY"] = "test-secret"

    sale = SimpleNamespace(
        id=42,
        public_tracking_code="TRACK-42",
        order_id="ORD-42",
        sale_date=None,
        customer_name="Customer",
        subtotal_amount=1000,
        items=[],
    )

    with app.test_request_context("/", base_url="http://attacker.example"):
        url = verify_url(sale)

    assert url.startswith("https://oma.example/track/TRACK-42?sig=")
    assert "attacker.example" not in url
