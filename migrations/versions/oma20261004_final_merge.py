"""merge the remaining Alembic migration heads

Revision ID: oma20261004_final
Revises: 6d4f8a1b2c30, oma20261004_merge

The previous merge migration incorrectly merged c4e7a1b2d903 directly
with oma20261004. c4e7a1b2d903 is already an ancestor of 6d4f8a1b2c30,
so 6d4f8a1b2c30 remained a separate head. This migration consumes the
actual remaining heads and leaves one canonical Alembic head.
"""

revision = "oma20261004_final"
down_revision = ("6d4f8a1b2c30", "oma20261004_merge")
branch_labels = None
depends_on = None


def upgrade():
    pass


def downgrade():
    pass
