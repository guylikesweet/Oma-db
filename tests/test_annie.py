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


def test_annie_supports_yesterday_and_month_to_date_sales(monkeypatch):
    import app.services.annie as annie

    monkeypatch.setattr(annie, "build_business_context", lambda user, question: {
        "sales_yesterday": {"orders": 2, "product_value_ngn": 40000, "verified_product_payments_ngn": 30000, "product_balance_ngn": 10000},
        "sales_month_to_date": {"orders": 18, "product_value_ngn": 800000, "verified_product_payments_ngn": 600000, "product_balance_ngn": 200000},
    })
    yesterday = answer_question(SimpleNamespace(is_admin=False), "How much did we sell yesterday?")
    month = answer_question(SimpleNamespace(is_admin=False), "Give me sales month to date")
    assert "yesterday" in yesterday and "2 order(s)" in yesterday
    assert "this month to date" in month and "18 order(s)" in month


def test_annie_business_context_has_lagos_timezone_support():
    import app.services.annie as annie

    assert annie.timezone.utc is not None
    assert annie.ZoneInfo("Africa/Lagos").key == "Africa/Lagos"


def test_annie_help_explains_scope_and_read_only_capability():
    answer = answer_question(SimpleNamespace(is_admin=False), "What can you do?")
    assert "live Oma records" in answer
    assert "cannot change records" in answer


def test_annie_lists_inventory_preview(monkeypatch):
    import app.services.annie as annie

    monkeypatch.setattr(annie, "build_business_context", lambda user, question: {
        "inventory_preview": [{"name": "Blue Dress", "stock_pieces": 4}],
    })
    answer = answer_question(SimpleNamespace(is_admin=False), "List all products")
    assert "Blue Dress: 4 piece(s)" in answer


def test_annie_distinguishes_calendar_week_and_month_periods(monkeypatch):
    import app.services.annie as annie

    def summary(count):
        return {"orders": count, "product_value_ngn": count * 1000,
                "verified_product_payments_ngn": count * 500,
                "product_balance_ngn": count * 500}

    monkeypatch.setattr(annie, "build_business_context", lambda user, question: {
        "sales_this_week": summary(3),
        "sales_last_week": summary(4),
        "sales_last_month": summary(12),
    })
    this_week = answer_question(SimpleNamespace(is_admin=False), "Sales this week")
    last_week = answer_question(SimpleNamespace(is_admin=False), "Sales last week")
    last_month = answer_question(SimpleNamespace(is_admin=False), "Sales last month")
    assert "this calendar week" in this_week and "3 order(s)" in this_week
    assert "last calendar week" in last_week and "4 order(s)" in last_week
    assert "last calendar month" in last_month and "12 order(s)" in last_month



def test_process_annie_question_posts_a_database_answer_without_reply_queue(monkeypatch):
    import app.services.annie as annie

    message = SimpleNamespace(
        id=321, sender_user_id=7, content="@Annie how many sales today?",
        deleted_at=None,
    )
    asker = SimpleNamespace(id=7, is_active=True)
    monkeypatch.setattr(annie.db.session, "get", lambda model, key: message if model is annie.ChatMessage else asker)
    monkeypatch.setattr(annie, "answer_question", lambda user, question: f"Answer for: {question}")
    posted = {}
    monkeypatch.setattr(annie, "post_annie_message", lambda content, **kwargs: (
        posted.update(content=content, kwargs=kwargs) or SimpleNamespace(id=999), True
    ))
    commits = []
    monkeypatch.setattr(annie.db.session, "commit", lambda: commits.append(True))
    monkeypatch.setattr(annie, "_active_staff_ids", lambda: [])
    monkeypatch.setattr("app.services.audit._schedule_outbox_flush", lambda: None)

    result = annie.process_annie_question(321, 7)

    assert result.id == 999
    assert posted["content"] == "Answer for: how many sales today?"
    assert posted["kwargs"]["event_key"] == "annie-reply-321"
    assert posted["kwargs"]["recipient_user_ids"] == []
    assert commits
