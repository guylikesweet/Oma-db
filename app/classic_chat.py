"""Classic-site bridge for the same Team Chat backend used by the mobile/Flutter Web app.

The browser UI uses Flask-Login, while the mobile and Flutter Web clients use
Bearer API tokens. These routes deliberately bridge the classic session to the
same ChatMessage API view functions so all three clients share the same data,
permissions, reply/edit/delete/reaction rules and photo storage.
"""
from flask import Blueprint, g, jsonify
from flask_login import current_user, login_required

from app.models import User
from app.api import (
    mobile_chat_messages,
    mobile_create_chat_message,
    mobile_modify_chat_message,
    mobile_react_chat_message,
    mobile_chat_attachment,
)

classic_chat_bp = Blueprint("classic_chat", __name__, url_prefix="/classic/chat")


def _as_api_user():
    g.api_user = current_user


@classic_chat_bp.route("/messages", methods=("GET", "POST"))
@login_required
def messages():
    _as_api_user()
    view = (
        mobile_chat_messages.__wrapped__
        if __import__("flask").request.method == "GET"
        else mobile_create_chat_message.__wrapped__
    )
    return view()


@classic_chat_bp.route("/messages/<int:message_id>", methods=("PUT", "PATCH", "DELETE"))
@login_required
def modify_message(message_id):
    _as_api_user()
    return mobile_modify_chat_message.__wrapped__(message_id)


@classic_chat_bp.route("/messages/<int:message_id>/react", methods=("POST", "DELETE"))
@login_required
def react(message_id):
    _as_api_user()
    return mobile_react_chat_message.__wrapped__(message_id)


@classic_chat_bp.route("/messages/<int:message_id>/attachment", methods=("GET",))
@login_required
def attachment(message_id):
    _as_api_user()
    return mobile_chat_attachment.__wrapped__(message_id)


@classic_chat_bp.route("/users", methods=("GET",))
@login_required
def users():
    rows = (
        User.query
        .filter(User.is_active.is_(True))
        .order_by(User.username.asc())
        .all()
    )
    return jsonify([
        {
            "id": user.id,
            "username": user.username,
            "is_admin": bool(user.is_admin),
            "is_primary_admin": bool(user.is_primary_admin),
        }
        for user in rows
    ])
