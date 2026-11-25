from types import SimpleNamespace

from app.services.annie import answer_question, build_audit_update, is_annie_mention


def test_annie_mention_is_case_insensitive_and_requires_a_real_tag():
    assert is_annie_mention("@Annie how many batches are in transit?")
    assert is_annie_mention("Hi @ANNIE, what's our sales total?")
    assert not is_annie_mention("Annie how are you?")
    assert not is_annie_mention("@anniversary update please")


def test_annie_audit_updates_skip_private_account_changes():
    assert build_audit_update("password.change", "user", 4, {}) is None
    assert build_audit_update("username.change", "user", 4, {}) is None
    assert build_audit_update("user.update", "user", 4, {"role_changed": True}) is None


def test_annie_audit_update_describes_batch_creation_without_sensitive_data():
    result = build_audit_update(
        "batch.create", "shipment_batch", 24,
        {"name": "Sea Batch 024", "transport_mode": "sea"},
    )
    assert result["title"] == "Shipment batch created"
    assert "Sea Batch 024" in result["body"]
    assert "SEA" in result["body"]
    assert "cost" not in result["body"].lower()


def test_annie_payment_update_uses_only_payment_and_outstanding_values():
    result = build_audit_update(
        "sale.payment.verified", "sale", 81,
        {"amount": "5000.00", "outstanding": "12000.00"},
    )
    assert "₦5,000.00" in result["body"]
    assert "₦12,000.00" in result["body"]
    assert "unit cost" not in result["body"].lower()


def test_annie_without_provider_key_explains_configuration(monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    answer = answer_question(SimpleNamespace(is_admin=False), "How many batches are in transit?")
    assert "OPENAI_API_KEY" in answer
