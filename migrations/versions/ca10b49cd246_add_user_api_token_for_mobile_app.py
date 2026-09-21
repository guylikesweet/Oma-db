"""add user api_token for mobile app

Revision ID: ca10b49cd246
Revises: b11bd6d0ad19
Create Date: 2026-09-20 19:33:05.721876

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'ca10b49cd246'
down_revision = 'b11bd6d0ad19'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.add_column(sa.Column('api_token', sa.String(length=64), nullable=True))
        batch_op.create_unique_constraint('uq_users_api_token', ['api_token'])


def downgrade():
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.drop_constraint('uq_users_api_token', type_='unique')
        batch_op.drop_column('api_token')
