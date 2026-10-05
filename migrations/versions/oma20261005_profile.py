"""add user profile photos

Revision ID: oma20261005_profile
Revises: oma20261005_chat
"""

from alembic import op
import sqlalchemy as sa


revision = "oma20261005_profile"
down_revision = "oma20261005_chat"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("users", sa.Column("profile_photo_data", sa.LargeBinary(), nullable=True))
    op.add_column("users", sa.Column("profile_photo_mimetype", sa.String(length=50), nullable=True))
    op.add_column("users", sa.Column("profile_photo_updated_at", sa.DateTime(), nullable=True))


def downgrade():
    op.drop_column("users", "profile_photo_updated_at")
    op.drop_column("users", "profile_photo_mimetype")
    op.drop_column("users", "profile_photo_data")
