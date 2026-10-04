import json

from flask import has_request_context, request
from flask_login import current_user

from app import db
from app.models import AuditLog


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
    return row
