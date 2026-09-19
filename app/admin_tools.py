from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required

from app.services.data_reset import clear_test_data

admin_tools_bp = Blueprint(
    "admin_tools", __name__, url_prefix="/admin-tools", template_folder="templates/admin_tools"
)

CONFIRM_PHRASE = "CLEAR ALL DATA"


@admin_tools_bp.route("/clear-data", methods=("GET", "POST"))
@login_required
def clear_data():
    if request.method == "POST":
        typed = request.form.get("confirm_phrase", "").strip()
        if typed != CONFIRM_PHRASE:
            flash(f'Type exactly "{CONFIRM_PHRASE}" to confirm. Nothing was deleted.', "error")
            return redirect(url_for("admin_tools.clear_data"))

        counts = clear_test_data()
        summary = "; ".join(f"{label}: {n}" for label, n in counts.items())
        flash(f"Cleared. {summary}. Products and your admin login were not touched.", "success")
        return redirect(url_for("admin_tools.clear_data"))

    return render_template("admin_tools/clear_data.html", confirm_phrase=CONFIRM_PHRASE)
