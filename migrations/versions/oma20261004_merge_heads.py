"""merge the two current production migration heads

Revision ID: oma20261004_merge
Revises: c4e7a1b2d903, oma20261004

This is a no-op merge migration. The schema changes in both branches
have already been defined by their respective migrations; this revision
only gives Alembic one canonical head so `flask db upgrade` can proceed.
"""

revision = "oma20261004_merge"
down_revision = ("c4e7a1b2d903", "oma20261004")
branch_labels = None
depends_on = None


def upgrade():
    pass


def downgrade():
    pass
