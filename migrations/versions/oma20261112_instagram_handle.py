"""Add the business Instagram handle to app settings (shown on receipts)."""
import sqlalchemy as sa
from alembic import op
from sqlalchemy import inspect

revision = "oma20261112_instagram_handle"
down_revision = "oma20261008_chat_schema_guard"
branch_labels = None
depends_on = None


def upgrade():
    columns = {c["name"] for c in inspect(op.get_bind()).get_columns("app_settings")}
    if "instagram_handle" not in columns:
        op.add_column("app_settings", sa.Column("instagram_handle", sa.String(length=100), nullable=True))


def downgrade():
    columns = {c["name"] for c in inspect(op.get_bind()).get_columns("app_settings")}
    if "instagram_handle" in columns:
        op.drop_column("app_settings", "instagram_handle")
