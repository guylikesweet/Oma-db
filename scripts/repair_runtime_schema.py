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
