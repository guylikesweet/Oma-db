from datetime import datetime, timedelta
from decimal import Decimal
from types import SimpleNamespace

import pytest

from app.models import ShipmentBatch
from app.services.payments import PaymentError, build_batch_payment_reminders


def _sale(sale_id, phone, subtotal, paid, qty, estimate=0):
    item = SimpleNamespace(qty=qty, product=SimpleNamespace(name="Test product"))
    payment_rows = [SimpleNamespace(amount=Decimal(str(paid)))] if paid else []
    return SimpleNamespace(
        id=sale_id,
        order_id=f"OMB-{sale_id}",
        is_stock_sale=False,
        order_status="New",
        customer_phone=phone,
        customer_name="Ada",
        subtotal_amount=Decimal(str(subtotal)),
        estimated_shipping_cost=Decimal(str(estimate)),
        estimated_shipping_sea=None,
        estimated_shipping_air=None,
        payments=payment_rows,
        items=[item],
    )


def test_batch_payment_reminders_require_45_days():
    created = datetime(2026, 1, 1)
    batch = SimpleNamespace(
        status=ShipmentBatch.STATUS_IN_TRANSIT,
        is_air=False,
        created_at=created,
        sales=[],
    )
    with pytest.raises(PaymentError, match="45 days"):
        build_batch_payment_reminders(batch, now=created + timedelta(days=44))


def test_batch_payment_reminders_merge_normalized_phone_within_one_batch():
    created = datetime(2026, 1, 1)
    batch = SimpleNamespace(
        status=ShipmentBatch.STATUS_IN_TRANSIT,
        is_air=False,
        created_at=created,
        sales=[
            _sale(1, "08012345678", 20000, 5000, 2, 1500),
            _sale(2, "+234 801 234 5678", 10000, 10000, 1, 700),
            _sale(3, "", 5000, 0, 1, 200),
        ],
    )
    notices = build_batch_payment_reminders(batch, now=created + timedelta(days=45))
    assert len(notices) == 1
    notice = notices[0]
    assert notice["phone"] == "2348012345678"
    assert notice["sale_ids"] == [1, 2]
    assert notice["piece_count"] == 3
    assert notice["product_outstanding"] == 15000
    assert notice["estimated_shipping"] == 2200
    assert notice["daily_demurrage"] == 450
    assert "7 days" in notice["message"]
    assert "day 8" in notice["message"]


def test_same_customer_in_different_batches_gets_separate_notices():
    created = datetime(2026, 1, 1)
    first = SimpleNamespace(
        status=ShipmentBatch.STATUS_IN_TRANSIT,
        is_air=False,
        created_at=created,
        sales=[_sale(1, "08012345678", 10000, 0, 1)],
    )
    second = SimpleNamespace(
        status=ShipmentBatch.STATUS_IN_TRANSIT,
        is_air=False,
        created_at=created,
        sales=[_sale(2, "2348012345678", 15000, 5000, 2)],
    )
    now = created + timedelta(days=46)
    one = build_batch_payment_reminders(first, now=now)
    two = build_batch_payment_reminders(second, now=now)
    assert len(one) == len(two) == 1
    assert one[0]["sale_ids"] == [1]
    assert two[0]["sale_ids"] == [2]
    assert one[0]["phone"] == two[0]["phone"]



def test_first_payment_minimum_uses_nearest_thousand_without_exposing_cost():
    from app.api import _first_payment_minimum

    sale = SimpleNamespace(items=[
        SimpleNamespace(unit_cost=Decimal("5500"), qty=1),
        SimpleNamespace(unit_cost=Decimal("2400"), qty=1),
    ])
    assert _first_payment_minimum(sale) == Decimal("8000")


def test_partial_order_can_receive_server_order_receipt_after_verified_payment():
    from app.services.invoices import receipt_block_reason

    sale = SimpleNamespace(
        order_status="New",
        payment_status="Partially Paid",
        payments=[SimpleNamespace(amount=Decimal("5000"))],
    )
    assert receipt_block_reason(sale) is None


def test_batch_reminders_use_the_batch_transport_estimate():
    created = datetime(2026, 1, 1)
    sale = _sale(9, "08012345678", 10000, 0, 1, estimate=100)
    sale.estimated_shipping_sea = Decimal("1200")
    sale.estimated_shipping_air = Decimal("3400")
    sea = SimpleNamespace(
        status=ShipmentBatch.STATUS_IN_TRANSIT,
        is_air=False,
        created_at=created,
        sales=[sale],
    )
    air = SimpleNamespace(
        status=ShipmentBatch.STATUS_IN_TRANSIT,
        is_air=True,
        created_at=created,
        sales=[sale],
    )
    now = created + timedelta(days=45)
    assert build_batch_payment_reminders(sea, now=now)[0]["estimated_shipping"] == 1200
    assert build_batch_payment_reminders(air, now=now)[0]["estimated_shipping"] == 3400
