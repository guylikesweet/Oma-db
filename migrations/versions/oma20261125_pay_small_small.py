"""Create verified installment ledger and preserve existing paid sales."""
from alembic import op
import sqlalchemy as sa

revision = "oma20261125_pay_small_small"
down_revision = "oma20261112_instagram_handle"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "sale_payments",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("sale_id", sa.Integer(), sa.ForeignKey("sales.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("received_at", sa.DateTime(), nullable=False),
        sa.Column("transaction_reference", sa.String(160), nullable=False, unique=True),
        sa.Column("session_id", sa.String(160), nullable=True, unique=True),
        sa.Column("payment_method", sa.String(40), nullable=False, server_default="bank_transfer"),
        sa.Column("verified_at", sa.DateTime(), nullable=False),
        sa.Column("verified_by_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("created_by_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("is_legacy", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("notes", sa.String(500), nullable=True),
    )
    op.create_index("ix_sale_payments_sale_id", "sale_payments", ["sale_id"])
    op.create_index("ix_sale_payments_received_at", "sale_payments", ["received_at"])
    op.execute(sa.text("""
        INSERT INTO sale_payments
          (sale_id, amount, received_at, transaction_reference, payment_method, verified_at, is_legacy, notes)
        SELECT id, COALESCE(subtotal_amount, total_amount, 0), COALESCE(created_at, CURRENT_TIMESTAMP),
          'LEGACY-SALE-' || CAST(id AS VARCHAR(32)), 'legacy_import', COALESCE(created_at, CURRENT_TIMESTAMP),
          TRUE, 'Imported from legacy Paid sale status'
        FROM sales WHERE payment_status = 'Paid' AND COALESCE(subtotal_amount, total_amount, 0) > 0
    """))


def downgrade():
    op.drop_index("ix_sale_payments_received_at", table_name="sale_payments")
    op.drop_index("ix_sale_payments_sale_id", table_name="sale_payments")
    op.drop_table("sale_payments")
