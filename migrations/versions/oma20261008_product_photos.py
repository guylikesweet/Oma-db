"""add product catalogue photos (defensive)

Revision ID: oma20261008_product_photos
Revises: oma20261006_performance
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "oma20261008_product_photos"
down_revision = "oma20261006_performance"
branch_labels = None
depends_on = None

def upgrade():
    bind = op.get_bind()
    inspector = inspect(bind)
    if "products" not in inspector.get_table_names():
        return
    existing = {c["name"] for c in inspector.get_columns("products")}
    definitions = (
        sa.Column("image_data", sa.LargeBinary(), nullable=True),
        sa.Column("image_mimetype", sa.String(length=50), nullable=True),
        sa.Column("image_filename", sa.String(length=255), nullable=True),
        sa.Column("image_updated_at", sa.DateTime(), nullable=True),
    )
    for column in definitions:
        if column.name not in existing:
            op.add_column("products", column)
            existing.add(column.name)
            inspector.clear_cache()

def downgrade():
    # Keep production media durable during rollback.
    pass
