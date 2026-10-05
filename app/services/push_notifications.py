"""Stage 4 push notifications.

Firebase Cloud Messaging is used because Cloud Messaging is a no-cost Firebase
product. The database keeps an outbox so a committed business event is not
lost just because FCM is temporarily unavailable.

Server configuration:
  FIREBASE_CREDENTIALS_JSON = service-account JSON string
  FIREBASE_SERVICE_ACCOUNT_JSON = accepted alias for the same value
"""

import json
import logging
import os
from datetime import datetime, timedelta

from sqlalchemy import select

from app import db
from app.models import NotificationOutbox, PushDevice, User, ShipmentBatch

log = logging.getLogger(__name__)

# A notification that keeps failing is marked "failed" after this many flushes.
MAX_ATTEMPTS = 5
# A notification still pending after this long is stale and is retired, so the
# outbox cannot fill up with rows nobody can receive.
PENDING_EXPIRY = timedelta(days=7)

_firebase_app = None
_warned_missing_credentials = False


def _firebase():
    global _firebase_app, _warned_missing_credentials
    if _firebase_app is not None:
        return _firebase_app

    credentials_json = (
        os.environ.get("FIREBASE_CREDENTIALS_JSON", "").strip()
        or os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON", "").strip()
    )
    if not credentials_json:
        if not _warned_missing_credentials:
            log.warning(
                "Push notifications are disabled: FIREBASE_CREDENTIALS_JSON "
                "is not set on the server."
            )
            _warned_missing_credentials = True
        return None

    try:
        import firebase_admin
        from firebase_admin import credentials
        _firebase_app = firebase_admin.get_app()
    except Exception:
        try:
            import firebase_admin
            from firebase_admin import credentials
            info = json.loads(credentials_json)
            _firebase_app = firebase_admin.initialize_app(
                credentials.Certificate(info)
            )
        except Exception as exc:
            log.error("Firebase could not be initialised: %s", exc)
            return None

    return _firebase_app


def _push_user_ids(exclude_user_id=None):
    """Return users that actually have an enabled mobile push registration."""
    query = (
        db.session.query(PushDevice.user_id)
        .filter(PushDevice.enabled.is_(True))
        .distinct()
    )
    # Notifications are intentionally sent to all enabled registered users.
    return [row[0] for row in query.all()]


def queue_change_notification(
    *,
    actor_user_id=None,
    event_type,
    title,
    body,
    data=None,
    sound="scanner_beep",
):
    """Queue one meaningful-change notification for every other registered user."""
    payload = dict(data or {})
    payload.setdefault("type", event_type)
    payload.setdefault("sound", sound)

    for user_id in _push_user_ids(exclude_user_id=actor_user_id):
        queue_user_notification(
            user_id,
            event_type=event_type,
            title=title,
            body=body,
            data=payload,
        )


def queue_batch_arrival(batch, exclude_user_id=None):
    """Queue the specialized air/sea arrival notification for other registered users."""
    mode = "air" if batch.transport_mode == ShipmentBatch.MODE_AIR else "sea"
    sound = "airport_arrival" if mode == "air" else "ship_horn"
    title = "Air shipment arrived" if mode == "air" else "Sea shipment arrived"
    body = f"{batch.name} has arrived and is ready for shipping settlement."

    for user_id in _push_user_ids(exclude_user_id=exclude_user_id):
        queue_user_notification(
            user_id,
            event_type="batch_arrival",
            title=title,
            body=body,
            data={
                "type": "batch_arrival",
                "batch_id": str(batch.id),
                "transport_mode": mode,
                "sound": sound,
            },
        )


def queue_user_notification(
    user_id,
    *,
    event_type,
    title,
    body,
    data=None,
):
    """Queue a notification for one user in the same DB transaction."""
    payload = dict(data or {})
    payload.setdefault("type", event_type)
    db.session.add(
        NotificationOutbox(
            event_type=event_type,
            target_user_id=user_id,
            title=title,
            body=body,
            data_json=payload,
        )
    )


def flush_outbox(limit=100):
    """Best-effort delivery of pending notifications.

    FCM messages are intentionally data-only. That lets the Flutter client
    display them itself both in the foreground and from the Android background
    isolate, where it can also schedule the two-hour reminder.

    Delivery rules:
      * Only rows whose recipient currently has an enabled device are
        considered, so undeliverable rows can never crowd out new ones.
      * A row is "sent" as soon as one of the recipient's devices accepts it,
        so a single bad device cannot cause repeat deliveries to the others.
      * A row that no device accepts is retried up to MAX_ATTEMPTS flushes and
        then marked "failed".
      * Rows pending longer than PENDING_EXPIRY are marked "expired".
    """
    app = _firebase()
    if app is None:
        return 0

    from firebase_admin import messaging

    now = datetime.utcnow()

    # Retire stale rows first.
    NotificationOutbox.query.filter(
        NotificationOutbox.status == "pending",
        NotificationOutbox.created_at < now - PENDING_EXPIRY,
    ).update({"status": "expired"}, synchronize_session=False)

    users_with_devices = select(PushDevice.user_id).where(
        PushDevice.enabled.is_(True)
    )

    sent = 0
    rows = (
        NotificationOutbox.query
        .filter(
            NotificationOutbox.status == "pending",
            NotificationOutbox.target_user_id.in_(users_with_devices),
        )
        .order_by(NotificationOutbox.id.asc())
        .limit(limit)
        .all()
    )

    for row in rows:
        devices = PushDevice.query.filter_by(
            user_id=row.target_user_id,
            enabled=True,
        ).all()

        if not devices:
            # Recipient lost their last device since the query ran; leave the
            # row pending (it expires on its own if they never return).
            continue

        data = {
            str(k): str(v)
            for k, v in (row.data_json or {}).items()
        }
        data["title"] = row.title
        data["body"] = row.body
        data["notification_id"] = str(row.id)

        successful = 0
        last_error = None

        for device in devices:
            try:
                message = messaging.Message(
                    token=device.token,
                    data=data,
                    android=messaging.AndroidConfig(
                        priority="high",
                    ),
                )
                messaging.send(message, app=app)
                device.last_seen_at = datetime.utcnow()
                sent += 1
                successful += 1
            except Exception as exc:
                last_error = str(exc)[:4000]
                try:
                    if isinstance(exc, messaging.UnregisteredError):
                        device.enabled = False
                except Exception:
                    pass

        if successful:
            row.status = "sent"
            row.sent_at = datetime.utcnow()
            if last_error:
                # Some other device failed; keep the note but do not retry.
                row.last_error = last_error
        else:
            row.attempts = (row.attempts or 0) + 1
            row.last_error = last_error
            if row.attempts >= MAX_ATTEMPTS:
                row.status = "failed"

    db.session.commit()
    return sent
