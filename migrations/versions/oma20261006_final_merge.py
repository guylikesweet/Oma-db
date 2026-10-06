"""merge the current production migration heads

Revision ID: oma20261006_final
Revises: oma20261006_landed_cost, oma20261005_chat_fix

This is a no-op merge migration. The schema changes are already contained in
the two parent branches; this revision only gives Alembic one canonical head
after the mobile-session-security and Team Chat/landed-cost branches diverged.
"""

revision = "oma20261006_final"
down_revision = ("oma20261006_landed_cost", "oma20261005_chat_fix")
branch_labels = None
depends_on = None


def upgrade():
    pass


def downgrade():
    pass
