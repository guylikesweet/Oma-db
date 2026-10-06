    db.session.commit()
    return jsonify({'ok':True,'id':user_id})


# ---------------------------------------------------------------------------
# TEAM CHAT
# ---------------------------------------------------------------------------
@api_bp.route("/v1/admin/chat/cleanup", methods=("POST",))
@limiter.limit("5 per minute")
def mobile_admin_chat_cleanup():
    expected = __import__("os").environ.get("CHAT_CLEANUP_SECRET", "").strip()
    provided = request.headers.get("X-Chat-Cleanup-Secret", "").strip()
    if not expected or not provided or not secrets.compare_digest(provided, expected):
        return jsonify({"error": "Unauthorized."}), 401

    before = ChatMessage.query.filter(
        ChatMessage.attachment_data.isnot(None),
        ChatMessage.attachment_created_at < datetime.utcnow() - timedelta(days=30),
    ).count()
    _chat_cleanup_expired_photos()
    return jsonify({"ok": True, "expired_photos": before})


@api_bp.route("/v1/chat/messages", methods=("GET",))
@require_api_token
def mobile_chat_messages():
    # Photo expiry is handled by the protected cleanup endpoint. Chat reads
    # must never depend on the optional cleanup query being healthy.
    limit = min(max(request.args.get("limit", 100, type=int), 1), 200)
    before_id = request.args.get("before_id", type=int)
    account_created_at = g.api_user.created_at
    query = ChatMessage.query
    if account_created_at is not None:
        query = query.filter(ChatMessage.created_at >= account_created_at)
    if before_id:
        query = query.filter(ChatMessage.id < before_id)
    try:
        rows = query.order_by(ChatMessage.id.desc()).limit(limit).all()
        rows.reverse()
        return jsonify([_chat_message_json(message) for message in rows])
    except Exception as exc:
        db.session.rollback()
        current_app.logger.exception("Team chat GET failed")
        detail = str(exc) if g.api_user.is_admin else "The team chat database is unavailable."
        return jsonify({
            "error": "Team chat is temporarily unavailable.",
            "diagnostic": detail,
        }), 503


@api_bp.route("/v1/chat/messages/<int:message_id>", methods=("GET",))
@require_api_token
def mobile_chat_message(message_id):
    message = ChatMessage.query.get_or_404(message_id)
    if (
        g.api_user.created_at is not None
        and message.created_at < g.api_user.created_at
    ):
        return jsonify({"error": "This message predates your account."}), 403
    return jsonify(_chat_message_json(message))


@api_bp.route("/v1/chat/diagnostic", methods=("GET",))
@require_api_token
def mobile_chat_diagnostic():
    if not g.api_user.is_admin:
        return jsonify({"error": "Administrator access required."}), 403

    inspector = sa_inspect(db.engine)
    required = {
        "chat_messages": [
            "id", "sender_user_id", "content", "original_content", "edited_at",
            "edited_by_user_id", "deleted_at", "deleted_by_user_id",
            "attachment_data", "attachment_mimetype", "attachment_filename",
            "attachment_created_at", "reply_to_id", "created_at",
        ],
        "chat_reactions": ["id", "message_id", "user_id", "emoji", "created_at"],
        "chat_mentions": ["id", "message_id", "user_id", "created_at"],
    }
    schema = {}
    for table, columns in required.items():
        exists = inspector.has_table(table)
        present = set()
        if exists:
            present = {column["name"] for column in inspector.get_columns(table)}
        schema[table] = {
            "exists": exists,
            "missing_columns": [column for column in columns if column not in present],
        }

    alembic_versions = []
    try:
        alembic_versions = [
            str(row[0])
            for row in db.session.execute(
                sa_text("SELECT version_num FROM alembic_version ORDER BY version_num")
            ).all()
        ]
    except Exception as exc:
        db.session.rollback()
        alembic_versions = [f"ERROR: {exc}"]

    return jsonify({
        "ok": all(item["exists"] and not item["missing_columns"] for item in schema.values()),
        "alembic_versions": alembic_versions,
        "schema": schema,
    })


@api_bp.route("/v1/chat/messages", methods=("POST",))
@limiter.limit("30 per minute")
@require_api_token
def mobile_create_chat_message():
    # Photo expiry is handled separately so a cleanup/schema problem cannot
    # make ordinary chat sends fail.
    data = request.get_json(silent=True) or {}
    content = str(data.get("content") or "").strip()
    attachment_b64 = str(data.get("attachment_base64") or "").strip()
    if not content and not attachment_b64:
        return jsonify({"error": "Message cannot be empty."}), 400
    if len(content) > 4000:
        return jsonify({"error": "Message is too long. Maximum is 4000 characters."}), 400

    reply_to_id = data.get("reply_to_id")
    try:
        reply_to_id = int(reply_to_id) if reply_to_id not in (None, "", 0, "0") else None
    except (TypeError, ValueError):
        return jsonify({"error": "Invalid reply message."}), 400

    try:
        reply_to = None
        if reply_to_id is not None:
            reply_to = ChatMessage.query.get(reply_to_id)
            if (
                reply_to is None
                or (
                    g.api_user.created_at is not None
                    and reply_to.created_at < g.api_user.created_at
                )
            ):
                raise ValueError("You cannot reply to a message from before your account was created.")

        attachment = None
        attachment_mimetype = None
        attachment_filename = None
        if attachment_b64:
            try:
                raw = base64.b64decode(attachment_b64, validate=True)
            except Exception:
                raise ValueError("Invalid photo data.")
            if len(raw) > 12 * 1024 * 1024:
                raise ValueError("Photo is too large. Maximum upload is 12 MB.")
            try:
                from PIL import Image
                image = Image.open(io.BytesIO(raw))
                image = image.convert("RGB")
                image.thumbnail((1600, 1600), Image.Resampling.LANCZOS)
                out = io.BytesIO()
                image.save(out, format="JPEG", quality=78, optimize=True)
                attachment = out.getvalue()
                attachment_mimetype = "image/jpeg"
                safe_name = secure_filename(str(data.get("attachment_filename") or "photo"))[:180] or "photo"
                attachment_filename = safe_name.rsplit(".", 1)[0] + ".jpg"
                if len(attachment) > 2 * 1024 * 1024:
                    out = io.BytesIO()
                    image.save(out, format="JPEG", quality=62, optimize=True)
                    attachment = out.getvalue()
            except Exception:
                raise ValueError("The uploaded file is not a valid image.")

        message = ChatMessage(
            sender_user_id=g.api_user.id,
            content=content or "",
            original_content=None,
            reply_to_id=reply_to_id,
            attachment_data=attachment,
            attachment_mimetype=attachment_mimetype,
            attachment_filename=attachment_filename,
            attachment_created_at=datetime.utcnow() if attachment else None,
        )
        db.session.add(message)
        db.session.flush()

        active_users = User.query.filter(User.is_active.is_(True)).all()
        users_by_name = {user.username.casefold(): user for user in active_users if user.username}
        mentioned_ids = set()
        for match in re.finditer(r"(?<![A-Za-z0-9_])@([A-Za-z0-9_.-]{1,50})", content):
            mentioned = users_by_name.get(match.group(1).casefold())
            if mentioned is None or mentioned.id == g.api_user.id or mentioned.id in mentioned_ids:
                continue
            mentioned_ids.add(mentioned.id)
            db.session.add(ChatMention(message_id=message.id, user_id=mentioned.id))

        db.session.flush()
        special_user_ids = set(mentioned_ids)
        if reply_to is not None and reply_to.sender_user_id != g.api_user.id:
            special_user_ids.add(reply_to.sender_user_id)
        record_audit(
            "chat.message",
            target_type="chat_message",
            target_id=message.id,
            details={"reply_to_id": reply_to_id, "mention_user_ids": sorted(mentioned_ids), "has_photo": bool(attachment)},
            user=g.api_user,
        )

        # Queue the push in the SAME transaction as the chat message. The
        # outbox must never depend on a daemon thread that can disappear when
        # the request worker is recycled or the Render instance sleeps.
        queue_chat_message_notifications(
            message,
            special_user_ids=special_user_ids,
        )
        _schedule_outbox_flush()

        # The message and its durable push outbox rows commit together. FCM
        # delivery is attempted by the response callback after this commit.
        db.session.commit()

        return jsonify(_chat_message_json(message)), 201
    except ValueError as exc:
        db.session.rollback()
        return jsonify({"error": str(exc)}), 400
    except Exception as exc:
        db.session.rollback()
        current_app.logger.exception("Team chat POST failed")
        detail = str(exc) if g.api_user.is_admin else "The team chat database is unavailable."
        return jsonify({
            "error": "Team chat message could not be saved.",
            "diagnostic": detail,
        }), 503


@api_bp.route("/v1/chat/messages/<int:message_id>", methods=("PUT", "PATCH", "DELETE"))
@limiter.limit("60 per minute")
@require_api_token
def mobile_modify_chat_message(message_id):
    message = ChatMessage.query.get_or_404(message_id)
    if g.api_user.created_at and message.created_at < g.api_user.created_at:
        return jsonify({"error": "This message predates your account."}), 403

    if request.method == "DELETE":
        if not g.api_user.is_admin and message.sender_user_id != g.api_user.id:
            return jsonify({"error": "You can only delete your own messages."}), 403
        if message.deleted_at is not None:
            return jsonify(_chat_message_json(message))
        message.deleted_at = datetime.utcnow()
        message.deleted_by_user_id = g.api_user.id
        record_audit(
            "chat.message.delete",
            target_type="chat_message",
            target_id=message.id,
            details={"sender_user_id": message.sender_user_id},