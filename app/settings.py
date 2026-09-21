from flask import Blueprint, render_template, request, redirect, url_for, flash, Response
from flask_login import login_required

from app.services.settings import get_settings, update_settings
from app.services.labels import STATIC_LOGO_PATH
import os

settings_bp = Blueprint("settings", __name__, url_prefix="/settings", template_folder="templates/settings")


@settings_bp.route("/", methods=("GET", "POST"))
@login_required
def edit():
    settings = get_settings()

    if request.method == "POST":
        try:
            width = int(request.form.get("label_width_mm", "").strip())
            height = int(request.form.get("label_height_mm", "").strip())
            if width <= 0 or height <= 0:
                raise ValueError
        except (ValueError, TypeError):
            flash("Label width and height must be positive whole numbers (in mm).", "error")
            return redirect(url_for("settings.edit"))

        logo_data = None
        logo_mimetype = None
        logo_file = request.files.get("logo")
        if logo_file and logo_file.filename:
            logo_data = logo_file.read()
            logo_mimetype = logo_file.mimetype or "image/png"

        update_settings(
            label_width_mm=width,
            label_height_mm=height,
            business_name=request.form.get("business_name", "").strip(),
            business_phone=request.form.get("business_phone", "").strip(),
            business_address=request.form.get("business_address", "").strip(),
            logo_data=logo_data,
            logo_mimetype=logo_mimetype,
        )
        flash("Settings saved.", "success")
        return redirect(url_for("settings.edit"))

    return render_template("settings/edit.html", settings=settings, has_static_logo=os.path.exists(STATIC_LOGO_PATH))


@settings_bp.route("/logo")
def logo():
    settings = get_settings()
    if not settings.logo_data:
        return "", 404
    return Response(settings.logo_data, mimetype=settings.logo_mimetype or "image/png")
