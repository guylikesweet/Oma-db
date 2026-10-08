"""add product catalogue photos

Revision ID: oma20261008_product_photos
Revises: oma20261006_performance
"""
from alembic import op
import sqlalchemy as sa

revision = "oma20261008_product_photos"
down_revision = "oma20261006_performance"
branch_labels = None
depends_on = None

def upgrade():
    op.add_column("products", sa.Column("image_data", sa.LargeBinary(), nullable=True))
    op.add_column("products", sa.Column("image_mimetype", sa.String(length=50), nullable=True))
    op.add_column("products", sa.Column("image_filename", sa.String(length=255), nullable=True))
    op.add_column("products", sa.Column("image_updated_at", sa.DateTime(), nullable=True))

def downgrade():
    op.drop_column("products", "image_updated_at")
    op.drop_column("products", "image_filename")
    op.drop_column("products", "image_mimetype")
    op.drop_column("products", "image_data")
