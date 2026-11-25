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


def test_annie_answers_from_database_snapshot_without_provider_or_api_key(monkeypatch):
    import app.services.annie as annie

    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.setattr(annie, "build_business_context", lambda user, question: {
        "sales_today": {
            "orders": 3, "product_value_ngn": 150000,
            "verified_product_payments_ngn": 90000,
            "product_balance_ngn": 60000,
        },
        "sales_last_7_days": {},
        "outstanding_product_balance_recent_500_open_orders_ngn": 60000,
        "largest_outstanding_orders_recent_500": [],
        "matching_customer_orders": [],
        "shipment_batches": [],
        "shipment_batch_status_counts": {},
        "product_count": 12,
        "total_stock_pieces": 80,
        "matching_products": [],
        "low_stock_products": [],
        "recent_deliveries": [],
        "app_process_guide": [],
        "staff_role": "staff",
        "data_scope_note": "recent 500",
    })
    answer = answer_question(SimpleNamespace(is_admin=False), "How many sales today?")
    assert "3 order(s)" in answer
    assert "₦150,000.00" in answer
    assert "OPENAI_API_KEY" not in answer


def test_annie_does_not_disclose_profit_to_staff(monkeypatch):
    import app.services.annie as annie

    monkeypatch.setattr(annie, "build_business_context", lambda user, question: {
        "staff_role": "staff",
    })
    answer = answer_question(SimpleNamespace(is_admin=False), "What is our profit?")
    assert "can't share profit" in answer


def test_annie_answers_process_questions_from_oma_guide(monkeypatch):
    import app.services.annie as annie

    monkeypatch.setattr(annie, "build_business_context", lambda user, question: {
        "app_process_guide": [
            "Pay Small Small applies to preorder sales: a customer may pay in full or by instalments.",
            "After the first payment, the plan allows up to two further settlements.",
        ],
    })
    answer = answer_question(SimpleNamespace(is_admin=False), "How does Pay Small Small work?")
    assert "Pay Small Small" in answer
    assert "instalments" in answer


def test_only_the_main_branch_annie_scheduler_workflow_is_trusted():
    from app.services.annie import is_trusted_annie_scheduler_claims

    claims = {
        "repository": "guylikesweet/Oma-db",
        "ref": "refs/heads/main",
        "workflow_ref": "guylikesweet/Oma-db/.github/workflows/annie-scheduler.yml@refs/heads/main",
        "event_name": "schedule",
    }
    assert is_trusted_annie_scheduler_claims(claims)
    assert is_trusted_annie_scheduler_claims({**claims, "event_name": "workflow_dispatch"})
    assert not is_trusted_annie_scheduler_claims({**claims, "repository": "attacker/other"})
    assert not is_trusted_annie_scheduler_claims({**claims, "ref": "refs/heads/feature"})
    assert not is_trusted_annie_scheduler_claims({**claims, "workflow_ref": "other.yml"})
    assert not is_trusted_annie_scheduler_claims({**claims, "event_name": "push"})
