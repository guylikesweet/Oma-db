"""
App settings — a single row (id=1) holding shipping label size, business
info, and the logo image (as bytes, so it survives Render redeploys).
"""
from app import db
from app.models import AppSettings

DEFAULT_LABEL_WIDTH_MM = 100
DEFAULT_LABEL_HEIGHT_MM = 150


def get_settings():
    settings = AppSettings.query.get(1)
    if not settings:
        settings = AppSettings(
            id=1,
            label_width_mm=DEFAULT_LABEL_WIDTH_MM,
            label_height_mm=DEFAULT_LABEL_HEIGHT_MM,
        )
        db.session.add(settings)
        db.session.commit()
    return settings


def update_settings(label_width_mm=None, label_height_mm=None, business_name=None,
                     business_phone=None, business_address=None,
                     logo_data=None, logo_mimetype=None):
    settings = get_settings()

    if label_width_mm is not None:
        settings.label_width_mm = label_width_mm
    if label_height_mm is not None:
        settings.label_height_mm = label_height_mm
    if business_name is not None:
        settings.business_name = business_name
    if business_phone is not None:
        settings.business_phone = business_phone
    if business_address is not None:
        settings.business_address = business_address
    if logo_data is not None:
        settings.logo_data = logo_data
        settings.logo_mimetype = logo_mimetype or "image/png"

    db.session.commit()
    return settings
