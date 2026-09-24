"""add client operation id to sales for offline idempotency

Revision ID: e71c8b4f2d10
Revises: d4f2c7a91e60
"""
from alembic import op
import sqlalchemy as sa

revision = "e71c8b4f2d10"
down_revision = "d4f2c7a91e60"
branch_labels = None
depends_on = None

def upgrade():
    bind = op.get_bind()
    insp = sa.inspect(bind)
    cols = [c['name'] for c in insp.get_columns('sales')]
    
    if 'client_operation_id' not in cols:
        with op.batch_alter_table("sales", schema=None) as batch_op:
            batch_op.add_column(sa.Column("client_operation_id", sa.String(length=100), nullable=True))
            batch_op.create_unique_constraint("uq_sales_client_operation_id", ["client_operation_id"])
            batch_op.create_index("ix_sales_client_operation_id", ["client_operation_id"], unique=False)

def downgrade():
    bind = op.get_bind()
    insp = sa.inspect(bind)
    cols = [c['name'] for c in insp.get_columns('sales')]
    
    if 'client_operation_id' in cols:
        with op.batch_alter_table("sales", schema=None) as batch_op:
            try:
                batch_op.drop_index("ix_sales_client_operation_id")
            except:
                pass
            try:
                batch_op.drop_constraint("uq_sales_client_operation_id", type_="unique")
            except:
                pass
            batch_op.drop_column("client_operation_id")
