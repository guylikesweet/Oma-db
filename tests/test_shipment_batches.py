from app.models import ShipmentBatch
from app.services import shipment_batches


def test_new_batch_requires_a_complete_sales_manifest():
    import pytest

    with pytest.raises(
        shipment_batches.BatchValidationError,
        match="Select at least one sale",
    ):
        shipment_batches.create_batch("November Sea 01", sale_ids=[])


def test_departed_batch_rejects_individual_sale_addition():
    import pytest

    with pytest.raises(
        shipment_batches.BatchValidationError,
        match="locked when the batch is created",
    ):
        shipment_batches.add_sale_to_batch(7, 12)


def test_departed_batch_rejects_bulk_manifest_changes():
    import pytest

    with pytest.raises(
        shipment_batches.BatchValidationError,
        match="locked when the batch is created",
    ):
        shipment_batches.update_batch_sales(7, add_sale_ids=[12])

    with pytest.raises(
        shipment_batches.BatchValidationError,
        match="locked when the batch is created",
    ):
        shipment_batches.update_batch_sales(7, remove_sale_ids=[12])


def test_departed_batch_rejects_removing_an_assigned_sale():
    import pytest

    with pytest.raises(
        shipment_batches.BatchValidationError,
        match="locked when the batch is created",
    ):
        shipment_batches.remove_sale_from_batch(12)
