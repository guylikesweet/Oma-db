"""Stage 4 push notifications.

Firebase Cloud Messaging is used because Cloud Messaging is a no-cost Firebase
product. The database keeps an outbox so a committed business event is not
lost just because FCM is temporarily unavailable.

Server configuration:
  FIREBASE_CREDENTIALS_JSON = service-account JSON string
"""

import json
import os
from datetime import datetime

from app import db
from app.models import NotificationOutbox, PushDevice, User, ShipmentBatch


_firebase_app = None


def _firebase():
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app

    credentials_json = os.environ.get("FIREBASE_CREDENTIALS_JSON", "").strip()
    if not credentials_json:
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
        except Exception:
            return None

    return _firebase_app


def queue_batch_arrival(batch):
    """Queue one arrival notification for every active user/device.

    The actual business change is committed by the caller. The outbox rows are
    committed in the same transaction, so notification intent cannot disappear
    independently of the batch arrival.
    """
    mode = "air" if batch.transport_mode == ShipmentBatch.MODE_AIR else "sea"
    sound = "airport_arrival" if mode == "air" else "ship_horn"
    title = "Air shipment arrived" if mode == "air" else "Sea shipment arrived"
    body = f"{batch.name} has arrived and is ready for shipping settlement."

    users = User.query.all()
    for user in users:
        db.session.add(NotificationOutbox(
            event_type="batch_arrival",
            target_user_id=user.id,
            title=title,
            body=body,
            data_json={
                "type": "batch_arrival",
                "batch_id": str(batch.id),
                "transport_mode": mode,
                "sound": sound,
            },
        ))


def flush_outbox(limit=100):
    """Best-effort delivery of pending notifications.

    A deployment without Firebase credentials remains safe: rows stay pending
    until credentials are supplied and the next flush runs.
    """
    app = _firebase()
    if app is None:
        return 0

    from firebase_admin import messaging

    sent = 0
    rows = (
        NotificationOutbox.query
        .filter(NotificationOutbox.status == "pending")
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
            row.status = "sent"
            row.sent_at = datetime.utcnow()
            continue

        data = {str(k): str(v) for k, v in (row.data_json or {}).items()}
        sound = data.get("sound", "scanner_beep")
        channel_id = "oma_arrival_air_v2" if sound == "airport_arrival" else "oma_arrival_sea_v2" if sound == "ship_horn" else "oma_scanner_v2"

        successful = 0
        failures = 0
        for device in devices:
            try:
                message = messaging.Message(
                    token=device.token,
                    notification=messaging.Notification(
                        title=row.title,
                        body=row.body,
                    ),
                    data=data,
                    android=messaging.AndroidConfig(
                        priority="high",
                        notification=messaging.AndroidNotification(
                            sound=f"{sound}.wav",
                            channel_id=channel_id,
                        ),
                    ),
                )
                messaging.send(message, app=app)
                device.last_seen_at = datetime.utcnow()
                sent += 1
                successful += 1
            except Exception as exc:
                failures += 1
                row.attempts = (row.attempts or 0) + 1
                row.last_error = str(exc)[:4000]

        if successful and not failures:
            row.status = "sent"
            row.sent_at = datetime.utcnow()
        elif successful:
            row.status = "pending"
        else:
            row.status = "pending"

    db.session.commit()
    return sent
