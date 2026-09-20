"""
Monthly shipping rate lookup.

The flat CBM rate changes month to month. This is the single place that
decides which rate applies for a given date, so product estimates and
batch-arrival costing never drift apart.
"""
from decimal import Decimal

from app.models import MonthlyShippingRate

DEFAULT_RATE_PER_CBM = Decimal("600000.00")  # fallback if no rate has been recorded at all


def get_rate_for_month(target_date):
    """
    Returns the rate_per_cbm in effect for target_date's month.
    Matches by YEAR + MONTH only — not by exact date — so it doesn't matter
    which day of the month a rate row was saved with (the admin form doesn't
    force the 1st; someone editing a rate "today" would naturally pick today's
    date, and this must still be recognized as that month's rate).
    Falls back to the most recent earlier month's rate if the target month
    isn't recorded, and finally to DEFAULT_RATE_PER_CBM if nothing exists yet.
    """
    month_start = target_date.replace(day=1)
    if month_start.month == 12:
        next_month_start = month_start.replace(year=month_start.year + 1, month=1)
    else:
        next_month_start = month_start.replace(month=month_start.month + 1)

    exact = (
        MonthlyShippingRate.query.filter(
            MonthlyShippingRate.month >= month_start,
            MonthlyShippingRate.month < next_month_start,
        )
        .order_by(MonthlyShippingRate.month.desc())
        .first()
    )
    if exact:
        return exact.rate_per_cbm

    most_recent_prior = (
        MonthlyShippingRate.query.filter(MonthlyShippingRate.month < month_start)
        .order_by(MonthlyShippingRate.month.desc())
        .first()
    )
    if most_recent_prior:
        return most_recent_prior.rate_per_cbm

    return DEFAULT_RATE_PER_CBM
