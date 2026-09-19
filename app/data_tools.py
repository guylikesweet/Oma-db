from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required

from app.services.data_tools import get_row_counts, clear_test_data, CONFIRMATION_PHRASE

data_tools_bp = Blueprint("data_tools", __name__, url_prefix="/data-tools", template_folder="templates/data_tools")


@data_tools_bp.route("/clear", methods=("GET",))
@login_required
def clear_form():
    return render_template(
        "data_tools/clear.html",
        row_counts=get_row_counts(),
        confirmation_phrase=CONFIRMATION_PHRASE,
    )


@data_tools_bp.route("/clear", methods=("POST",))
@login_required
def clear_submit():
    typed = request.form.get("confirmation", "")
    try:
        counts = clear_test_data(typed)
        summary = ", ".join(f"{label}: {n}" for label, n in counts.items())
        flash(f"Cleared. {summary}. Products were left untouched.", "success")
        return redirect(url_for("admin.index"))
    except ValueError as e:
        flash(str(e), "error")
        return redirect(url_for("data_tools.clear_form"))
