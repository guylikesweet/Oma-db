"""Device channel compatibility migration."""
from alembic import op
import sqlalchemy as sa

revision = "oma20261006_push_channels"
down_revision = "oma20261006_final"
branch_labels = None
depends_on = None

def upgrade():
    op.add_column("push_devices", sa.Column("notification_channel_version", sa.String(length=20), nullable=True))

def downgrade():
    op.drop_column("push_devices", "notification_channel_version")
