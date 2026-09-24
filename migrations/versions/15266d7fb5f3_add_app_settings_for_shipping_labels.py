"""add app_settings for shipping labels

Revision ID: 15266d7fb5f3
Revises: ca10b49cd246
Create Date: 2026-09-21 01:25:52.408860

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '15266d7fb5f3'
down_revision = 'ca10b49cd246'
branch_labels = None
depends_on = None

def upgrade():
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = insp.get_table_names()
    
    if 'app_settings' not in tables:
        op.create_table('app_settings',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('label_width_mm', sa.Integer(), nullable=True),
        sa.Column('label_height_mm', sa.Integer(), nullable=True),
        sa.Column('business_name', sa.String(length=255), nullable=True),
        sa.Column('business_phone', sa.String(length=50), nullable=True),
        sa.Column('business_address', sa.Text(), nullable=True),
        sa.Column('logo_data', sa.LargeBinary(), nullable=True),
        sa.Column('logo_mimetype', sa.String(length=50), nullable=True),
        sa.PrimaryKeyConstraint('id')
        )

def downgrade():
    bind = op.get_bind()
    insp = sa.inspect(bind)
    if 'app_settings' in insp.get_table_names():
        op.drop_table('app_settings')
