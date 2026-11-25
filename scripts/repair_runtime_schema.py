"""Repair critical production columns before the web process starts.

This is a defensive runtime guard for Oma's external PostgreSQL database.
It is intentionally idempotent and only adds nullable/defaulted columns that
the current application models require. It never deletes or rewrites data.

The normal Alembic migrations remain authoritative; this guard exists because
the production database has previously reported Alembic revisions as applied
while the physical columns were missing.
"""

from __future__ import annotations

import os
import sys

from sqlalchemy import create_engine, text


REQUIRED_COLUMNS = {
    "products": {
        "supplier_cost": "NUMERIC(12, 2) DEFAULT 0",
        "inbound_shipping_cost": "NUMERIC(12, 2) DEFAULT 0",
        "markup_percent": "NUMERIC(8, 2) DEFAULT 0",
        "selling_price": "NUMERIC(12, 2) DEFAULT 0",
        "image_data": "BYTEA",
        "image_mimetype": "VARCHAR(50)",
        "image_filename": "VARCHAR(255)",
        "image_updated_at": "TIMESTAMP",
    },
    "users": {
        "profile_photo_data": "BYTEA",
        "profile_photo_mimetype": "VARCHAR(50)",
        "profile_photo_updated_at": "TIMESTAMP",
        "is_system": "BOOLEAN NOT NULL DEFAULT FALSE",
    },
    "app_settings": {
        "instagram_handle": "VARCHAR(100)",
    },
    "chat_messages": {
        "audio_data": "BYTEA",
        "audio_mimetype": "VARCHAR(50)",
        "audio_filename": "VARCHAR(255)",
        "audio_created_at": "TIMESTAMP",
        "client_operation_id": "VARCHAR(100)",
    },
}


def database_url() -> str:
    value = os.environ.get("DATABASE_URL", "").strip()
    if not value:
        raise RuntimeError("DATABASE_URL is not configured")
    if value.startswith("postgres://"):
        value = "postgresql://" + value[len("postgres://") :]
    return value


def table_exists(connection, table: str) -> bool:
    return bool(
        connection.execute(
            text("SELECT to_regclass(:table_name) IS NOT NULL"),
            {"table_name": f"public.{table}"},
        ).scalar()
    )


def repair() -> None:
    engine = create_engine(database_url(), pool_pre_ping=True)
    repaired: list[str] = []

    with engine.connect() as connection:
        # Prevent two Render processes/deploy hooks from modifying the schema
        # concurrently. PostgreSQL releases this automatically if the process
        # dies.
        connection.execute(
            text("SELECT pg_advisory_lock(hashtext('oma-runtime-schema-repair'))")
        )

        try:
            for table, columns in REQUIRED_COLUMNS.items():
                if not table_exists(connection, table):
                    print(f"[schema-repair] table {table} is absent; skipping")
                    continue

                for column, definition in columns.items():
                    connection.execute(
                        text(
                            f'ALTER TABLE public."{table}" '
                            f'ADD COLUMN IF NOT EXISTS "{column}" {definition}'
                        )
                    )
                    repaired.append(f"{table}.{column}")

            # These two tables are required by current application code. The
            # normal Alembic migrations create them; this idempotent fallback
            # repairs databases whose revision marker advanced without the
            # physical tables. Existing rows are never dropped or rewritten.
            if table_exists(connection, "sales") and table_exists(connection, "users"):
                connection.execute(text("""
                    CREATE TABLE IF NOT EXISTS public.sale_payments (
                        id SERIAL PRIMARY KEY,
                        sale_id INTEGER NOT NULL REFERENCES public.sales(id) ON DELETE RESTRICT,
                        amount NUMERIC(12, 2) NOT NULL,
                        received_at TIMESTAMP NOT NULL,
                        transaction_reference VARCHAR(160) NOT NULL UNIQUE,
                        session_id VARCHAR(160) UNIQUE,
                        payment_method VARCHAR(40) NOT NULL DEFAULT 'bank_transfer',
                        verified_at TIMESTAMP NOT NULL,
                        verified_by_user_id INTEGER REFERENCES public.users(id),
                        created_by_user_id INTEGER REFERENCES public.users(id),
                        is_legacy BOOLEAN NOT NULL DEFAULT FALSE,
                        notes VARCHAR(500)
                    )
                """))
                connection.execute(text("""
                    CREATE INDEX IF NOT EXISTS ix_sale_payments_sale_id
                    ON public.sale_payments (sale_id)
                """))
                connection.execute(text("""
                    CREATE INDEX IF NOT EXISTS ix_sale_payments_received_at
                    ON public.sale_payments (received_at)
                """))
                # Preserve the legacy Paid-sale balances exactly once. These
                # entries are explicitly marked legacy and cannot duplicate
                # a verified payment with the same reference.
                connection.execute(text("""
                    INSERT INTO public.sale_payments
                        (sale_id, amount, received_at, transaction_reference,
                         payment_method, verified_at, is_legacy, notes)
                    SELECT s.id,
                           COALESCE(s.subtotal_amount, s.total_amount, 0),
                           COALESCE(s.created_at, CURRENT_TIMESTAMP),
                           'LEGACY-SALE-' || CAST(s.id AS VARCHAR(32)),
                           'legacy_import',
                           COALESCE(s.created_at, CURRENT_TIMESTAMP),
                           TRUE,
                           'Imported from legacy Paid sale status'
                    FROM public.sales s
                    WHERE s.payment_status = 'Paid'
                      AND COALESCE(s.subtotal_amount, s.total_amount, 0) > 0
                      AND NOT EXISTS (
                          SELECT 1 FROM public.sale_payments p
                          WHERE p.transaction_reference =
                              'LEGACY-SALE-' || CAST(s.id AS VARCHAR(32))
                      )
                """))

            if table_exists(connection, "chat_messages") and table_exists(connection, "users"):
                connection.execute(text("""
                    CREATE TABLE IF NOT EXISTS public.annie_reply_tasks (
                        id SERIAL PRIMARY KEY,
                        message_id INTEGER NOT NULL UNIQUE
                            REFERENCES public.chat_messages(id) ON DELETE CASCADE,
                        asker_user_id INTEGER
                            REFERENCES public.users(id) ON DELETE SET NULL,
                        status VARCHAR(20) NOT NULL DEFAULT 'pending',
                        attempts INTEGER NOT NULL DEFAULT 0,
                        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        processed_at TIMESTAMP NULL,
                        last_error TEXT NULL
                    )
                """))
                connection.execute(text("""
                    CREATE INDEX IF NOT EXISTS ix_annie_reply_tasks_status
                    ON public.annie_reply_tasks (status)
                """))
                connection.execute(text("""
                    CREATE INDEX IF NOT EXISTS ix_annie_reply_tasks_created_at
                    ON public.annie_reply_tasks (created_at)
                """))

            # The ORM selects every mapped User column even for the admin seed
            # command. Seed Annie here as well as in Alembic so this defensive
            # pre-migration repair keeps the production build self-consistent.
            if table_exists(connection, "users"):
                connection.execute(text("""
                    INSERT INTO public.users
                        (username, password_hash, created_at, is_active, role, is_primary_admin, is_system)
                    SELECT '__annie__', '!system-account-disabled!', CURRENT_TIMESTAMP,
                           FALSE, 'staff', FALSE, TRUE
                    WHERE NOT EXISTS (
                        SELECT 1 FROM public.users WHERE username = '__annie__'
                    )
                """))

            connection.commit()

            # The unique idempotency index is useful but should never prevent
            # the critical columns above from being repaired. If an old database
            # already contains conflicting non-null operation IDs, leave that
            # index to the Alembic migration and report it without rolling back
            # the successful column repair.
            if table_exists(connection, "chat_messages"):
                try:
                    connection.execute(
                        text(
                            "CREATE UNIQUE INDEX IF NOT EXISTS "
                            "ix_chat_messages_client_operation_id "
                            "ON public.chat_messages (client_operation_id)"
                        )
                    )
                    connection.commit()
                except Exception as exc:
                    connection.rollback()
                    print(
                        "[schema-repair] warning: could not create "
                        f"chat idempotency index: {exc}",
                        file=sys.stderr,
                    )

            print(
                "[schema-repair] checked/ensured "
                f"{len(repaired)} required columns"
            )
        finally:
            connection.execute(
                text(
                    "SELECT pg_advisory_unlock("
                    "hashtext('oma-runtime-schema-repair'))"
                )
            )
            connection.commit()

    engine.dispose()


if __name__ == "__main__":
    try:
        repair()
    except Exception as exc:
        print(f"[schema-repair] FAILED: {exc}", file=sys.stderr)
        raise
