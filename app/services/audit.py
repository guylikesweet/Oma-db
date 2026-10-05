import json

from flask import g, has_request_context, request, after_this_request
from flask_login import current_user

from app import db
from app.models import AuditLog


def _resolve_actor(user=None):
    """Who performed the action.

    Order: an explicitly passed user, then the logged-in web user, then the
    mobile API user (set on `g` by require_api_token). The last step matters:
    service functions such as create_sale() and mark_unarrived() are called
    from /api routes without a `user=` argument, and bearer-token requests
    have no Flask-Login session, so without it the audit row would have no
    username and the actor would receive their own push notification.
    """
    if user is not None:
        return user
    if not has_request_context():
        return None
    if current_user.is_authenticated:
        return current_user
    return g.get("api_user")


def _schedule_outbox_flush():
    """Deliver queued push notifications once, after the response is built.

    Replaces the old SQLAlchemy `after_commit` listener, which could not run
    queries (the session is already committed at that point) and so failed
    silently. A response callback runs after the view has committed, with a
    usable session. Outside a request (CLI/jobs) the rows simply stay pending
    and go out on the next flush.
    """
    if not has_request_context() or g.get("_push_flush_scheduled"):
        return
    g._push_flush_scheduled = True

    @after_this_request
    def _flush(response):
        try:
            from app.services.push_notifications import flush_outbox
            flush_outbox()
        except Exception:
            # Push delivery is best effort. The committed outbox row stays
            # pending and is retried by a later flush.
            try:
                db.session.rollback()
            except Exception:
                pass
        return response


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
    actor = _resolve_actor(user)

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

    # Meaningful business changes are also broadcast to every other mobile
    # installation. Authentication/session housekeeping deliberately does not
    # notify anyone. Batch arrival remains specialized because its sound
    # depends on air vs sea.
    notification = _change_notification_for_audit(
        action=str(action),
        target_type=target_type,
        target_id=target_id,
        details=details or {},
        actor_id=getattr(actor, "id", None),
    )
    if notification is not None:
        from app.services.push_notifications import queue_change_notification
        queue_change_notification(
            actor_user_id=notification.pop("actor_user_id"),
            **notification,
        )
        # The outbox row is part of the same transaction, so a failed business
        # write cannot produce a push notification. Delivery is attempted only
        # after the response is ready (i.e. after the commit).
        _schedule_outbox_flush()

    return row


def _change_notification_for_audit(
    *,
    action,
    target_type,
    target_id,
    details,
    actor_id,
):
    """Translate audit actions into safe, human-readable mobile notifications."""
    if action in {
        "login", "login.biometric", "logout", "logout.timeout",
        "security.password_verify",
    }:
        return None

    mappings = {
        "sale.create": ("sale_change", "New sale created", "A new sale has been created."),
        "sale.status": ("sale_change", "Sale status changed", "A sale's status has been updated."),
        "sale.payment_status": ("sale_change", "Sale payment updated", "A sale's payment status has been updated."),
        "sale.delete": ("sale_change", "Sale removed", "A sale has been removed."),
        "product.create": ("product_change", "Product created", "A new product has been created."),
        "product.update": ("product_change", "Product updated", "A product has been updated."),
        "product.delete": ("product_change", "Product removed", "A product has been removed."),
        "stock.adjust": ("stock_change", "Stock adjusted", "Inventory stock has been adjusted."),
        "batch.create": ("batch_change", "Shipment batch created", "A new shipment batch has been created."),
        "batch.add_sale": ("batch_change", "Sale added to batch", "A sale has been added to a shipment batch."),
        "batch.remove_sale": ("batch_change", "Sale removed from batch", "A sale has been removed from a shipment batch."),
        "batch.delete": ("batch_change", "Shipment batch removed", "A shipment batch has been removed."),
        "batch.undo_arrival": ("batch_change", "Shipment arrival undone", "A shipment batch has been moved back to In Transit."),
        "shipping.settle": ("shipping_change", "Shipping payment settled", "A sale's shipping payment has been settled."),
        "shipping.create": ("shipping_change", "Shipment created", "A shipment record has been created."),
        "shipping.update": ("shipping_change", "Shipment updated", "A shipment record has been updated."),
        "delivery.create": ("delivery_change", "Delivery created", "A new delivery has been created."),
        "delivery.status": ("delivery_change", "Delivery status changed", "A delivery's status has been updated."),
        "delivery.label_update": ("delivery_change", "Delivery package updated", "A delivery package's label information has been updated."),
        "journey.update": ("journey_change", "Order journey updated", "An order's journey stage has been updated."),
        "settings.update": ("settings_change", "Settings updated", "Business settings have been updated."),
        "user.create": ("user_change", "User account created", "A user account has been created."),
        "user.update": ("user_change", "User account updated", "A user account has been updated."),
        "user.delete": ("user_change", "User account removed", "A user account has been removed."),
        "username.change": ("user_change", "Username changed", "A user's username has been changed."),
        "password.change": ("user_change", "Password changed", "A user's password has been changed."),
        "rate.courier.create": ("rate_change", "Courier rate created", "A courier shipping rate has been created."),
        "rate.courier.update": ("rate_change", "Courier rate updated", "A courier shipping rate has been updated."),
        "rate.courier.delete": ("rate_change", "Courier rate removed", "A courier shipping rate has been removed."),
        "rate.air.create": ("rate_change", "Air rate created", "A monthly air shipping rate has been created."),
        "rate.air.update": ("rate_change", "Air rate updated", "A monthly air shipping rate has been updated."),
        "rate.air.delete": ("rate_change", "Air rate removed", "A monthly air shipping rate has been removed."),
        "rate.sea.create": ("rate_change", "Sea rate created", "A monthly sea shipping rate has been created."),
        "rate.sea.update": ("rate_change", "Sea rate updated", "A monthly sea shipping rate has been updated."),
        "rate.sea.delete": ("rate_change", "Sea rate removed", "A monthly sea shipping rate has been removed."),
    }

    item = mappings.get(action)
    if item is None:
        return None

    event_type, title, body = item
    data = {
        "type": event_type,
        "action": action,
        "target_type": target_type or "",
        "target_id": target_id or "",
    }

    recipient_user_ids = None

    # User creation is an admin event: only admins should be told about it.
    if action == "user.create":
        recipient_user_ids = [
            row[0]
            for row in User.query.filter(
                User.role == User.ROLE_ADMIN,
                User.is_active.is_(True),
            ).with_entities(User.id).all()
        ]

    # A role change is private to the affected account. The audit details are
    # populated by both the web admin UI and the mobile API.
    elif action == "user.update" and details.get("role_changed"):
        try:
            recipient_user_ids = [int(target_id)]
        except (TypeError, ValueError):
            recipient_user_ids = []

    # Shipment creation is an admin-only operational event.
    elif action == "batch.create":
        recipient_user_ids = [
            row[0]
            for row in User.query.filter(
                User.role == User.ROLE_ADMIN,
                User.is_active.is_(True),
            ).with_entities(User.id).all()
        ]

    return {
        "actor_user_id": actor_id,
        "recipient_user_ids": recipient_user_ids,
        "event_type": event_type,
        "title": title,
        "body": body,
        "data": data,
    }
