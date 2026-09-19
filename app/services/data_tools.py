"""
Data-clear tool — Stage 9.

Wipes everything except Products (and Users — never touch admin logins).
SaleItem and Shipping are deleted explicitly (not left to the DB's
ON DELETE CASCADE) so this behaves identically on every backend — SQLite
doesn't enforce foreign keys by default even though the constraint is
defined, while Postgres/Neon does; relying on that difference would make
local testing lie about what actually happens in production.
"""
from app import db
from app.models import (
    Sale, SaleItem, Shipping, StockLog, ShipmentBatch, Delivery,
    CourierRate, MonthlyShippingRate,
)

# Tables wiped, and the order they must be deleted in (children before parents).
# Products and Users are deliberately never included here.
CLEARABLE_MODELS = [
    ("Sale Items", SaleItem),
    ("Shipping", Shipping),
    ("Stock Log", StockLog),
    ("Sales", Sale),
    ("Shipment Batches", ShipmentBatch),
    ("Deliveries", Delivery),
    ("Courier Rates", CourierRate),
    ("Monthly Shipping Rates", MonthlyShippingRate),
]

CONFIRMATION_PHRASE = "DELETE ALL TEST DATA"


def get_row_counts():
    """Row counts for each table this tool would clear — shown before confirming."""
    return [(label, model.query.count()) for label, model in CLEARABLE_MODELS]


def clear_test_data(typed_confirmation):
    if typed_confirmation != CONFIRMATION_PHRASE:
        raise ValueError(f"Confirmation text didn't match. You must type exactly: {CONFIRMATION_PHRASE}")

    counts = {}
    for label, model in CLEARABLE_MODELS:
        counts[label] = model.query.delete()
    db.session.commit()
    return counts
