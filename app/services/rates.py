"""
Monthly shipping rate lookup — Stage 6.

The flat CBM rate changes month to month. This is the single place that
decides which rate applies for a given date, so product estimates and
batch-arrival costing never drift apart.
"""
from decimal import Decimal

from app.models import MonthlyShippingRate

DEFAULT_RATE_PER_CBM = Decimal("600000.00")  # fallback if no rate has been recorded at all


def _first_of_month(d):
    return d.replace(day=1)


def get_rate_for_month(target_date):
    """
    Returns the rate_per_cbm in effect for target_date's month.
    Falls back to the most recent earlier month's rate if that exact month
    isn't recorded, and finally to DEFAULT_RATE_PER_CBM if nothing exists yet.
    """
    month_start = _first_of_month(target_date)

    exact = MonthlyShippingRate.query.filter_by(month=month_start).first()
    if exact:
        return exact.rate_per_cbm

    most_recent_prior = (
        MonthlyShippingRate.query.filter(MonthlyShippingRate.month <= month_start)
        .order_by(MonthlyShippingRate.month.desc())
        .first()
    )
    if most_recent_prior:
        return most_recent_prior.rate_per_cbm

    return DEFAULT_RATE_PER_CBM
