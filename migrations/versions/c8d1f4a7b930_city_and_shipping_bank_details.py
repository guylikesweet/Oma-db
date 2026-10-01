"""add sale city and shipping bank details to settings

Revision ID: c8d1f4a7b930
Revises: b3f6a1c8e9d2
"""
from alembic import op
import sqlalchemy as sa

revision = "c8d1f4a7b930"
down_revision = "b3f6a1c8e9d2"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("sales", sa.Column("customer_city", sa.String(length=100), nullable=True))
    op.add_column("app_settings", sa.Column("bank_name", sa.String(length=100), nullable=True))
    op.add_column("app_settings", sa.Column("bank_account_number", sa.String(length=50), nullable=True))
    op.add_column("app_settings", sa.Column("bank_account_name", sa.String(length=255), nullable=True))


def downgrade():
    op.drop_column("app_settings", "bank_account_name")
    op.drop_column("app_settings", "bank_account_number")
    op.drop_column("app_settings", "bank_name")
    op.drop_column("sales", "customer_city")
