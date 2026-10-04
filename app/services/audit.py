import json

from flask import has_request_context, request
from flask_login import current_user

from app import db
from app.models import AuditLog


_CHANGE_NOTIFICATIONS = {
    "sale.create": ("New sale", "A new sale was created."),
    "sale.status": ("Sale updated", "A sale status was changed."),
    "sale.payment_status": ("Sale payment updated", "A sale payment status was changed."),
    "sale.delete": ("Sale deleted", "A sale was deleted."),
    "stock.adjust": ("Stock updated", "Stock was manually adjusted."),
    "batch.create": ("Shipment batch created", "A new shipment batch was created."),
    "batch.add_sale": ("Sale added to shipment", "A sale was added to a shipment batch."),
    "batch.remove_sale": ("Sale removed from shipment", "A sale was removed from a shipment batch."),
    "batch.delete": ("Shipment batch deleted", "A shipment batch was deleted."),
    "batch.undo_arrival": ("Shipment arrival undone", "A shipment batch was returned to In Transit."),
    "delivery.create": ("Delivery created", "A new delivery was created."),
    "delivery.status": ("Delivery updated", "A delivery status was changed."),
    "settings.update": ("Settings updated", "Business settings were changed."),
    "user.create": ("User account created", "A user account was created."),
    "user.update": ("User account updated", "A user account was updated."),
    "user.delete": ("User account removed", "A user account was removed."),
    "journey.update": ("Order journey updated", "One or more order journey stages were changed."),
}


def record_audit(
    action,
    *,
    target_type=None,
    target_id=None,
    outcome="success",
    details=None,
    user=None,
):
    """Stage 3 audit entry.

    The caller controls the surrounding transaction. This function only adds
    the row to the current SQLAlchemy session, so the audit event commits or
    rolls back with the business operation it describes.
    """
    actor = user
    if actor is None and has_request_context() and current_user.is_authenticated:
        actor = current_user

    details_json = None
    if details is not None:
        details_json = json.dumps(
            details,
            ensure_ascii=False,
            separators=(",", ":"),
            default=str,
        )

    row = AuditLog(
        user_id=getattr(actor, "id", None),
        username=getattr(actor, "username", None),
        action=str(action),
        target_type=str(target_type) if target_type is not None else None,
        target_id=str(target_id) if target_id is not None else None,
        outcome=str(outcome),
        details_json=details_json,
        ip_address=request.remote_addr if has_request_context() else None,
        user_agent=(
            request.headers.get("User-Agent", "")[:500]
            if has_request_context()
            else None
        ),
    )
    db.session.add(row)

    notification = _CHANGE_NOTIFICATIONS.get(str(action))
    if notification and actor is not None:
        from app.services.push_notifications import queue_change_notification
        title, body = notification
        queue_change_notification(
            actor.id,
            event_type=str(action),
            title=title,
            body=body,
            data={
                "type": "business_change",
                "action": str(action),
                "target_type": str(target_type) if target_type is not None else "",
                "target_id": str(target_id) if target_id is not None else "",
            },
        )

    return row
