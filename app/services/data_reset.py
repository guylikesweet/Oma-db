"""
Data reset tool — Stage 9.

Wipes every transactional/test table EXCEPT Products (and Users, obviously,
since that would lock the admin out). Deletion order respects foreign key
dependencies: Sale is deleted before ShipmentBatch/Delivery (which it
references), and SaleItem/Shipping cascade automatically from Sale via
their ON DELETE CASCADE constraints. StockLog, CourierRate, and
MonthlyShippingRate have no dependents and are deleted directly.

Product rows (including stock counts, dimensions, cost) are left completely
untouched — only the transactional data referencing them is removed.
"""
from app import db
from app.models import (
    Sale, StockLog, ShipmentBatch, Delivery, CourierRate, MonthlyShippingRate,
)


def clear_test_data():
    """
    Returns a dict of {table_label: row_count_deleted} for the confirmation message.
    Runs as a single transaction — if anything fails, nothing is deleted.
    """
    counts = {}

    # StockLog first: no FK dependents, but also not touched by Sale's cascade.
    counts["Stock Log entries"] = StockLog.query.delete()

    # Deleting Sale cascades SaleItem and Shipping automatically (ON DELETE CASCADE).
    counts["Sales (and their line items + shipments)"] = Sale.query.delete()

    # Now safe: no Sale rows reference these anymore.
    counts["Shipment Batches"] = ShipmentBatch.query.delete()
    counts["Deliveries"] = Delivery.query.delete()
    counts["Courier Rates"] = CourierRate.query.delete()
    counts["Monthly Shipping Rates"] = MonthlyShippingRate.query.delete()

    db.session.commit()
    return counts
