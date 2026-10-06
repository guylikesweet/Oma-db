# Stage 3 — Architecture Foundations

Stage 3 establishes the architecture boundary without replacing working Oma functionality.

## Boundaries

- **Presentation**: Flutter widgets/controllers under `mobile/lib/presentation/`.
- **Domain**: entities, repository contracts and use cases under `mobile/lib/domain/`.
- **Data**: API, SQLite and sync implementations under `mobile/lib/data/`.
- UI code should depend on domain contracts/use cases, not SQL or HTTP details.

## Current migration strategy

This is an incremental migration. Existing screens are not mass-rewritten in one risky change.

The first migrated paths are:

1. Authentication/session restoration → `SessionRepository` → `SessionController`.
2. Dashboard loading → `DashboardRepository` → `DashboardController`.
3. Sale creation → `SalesRepository` → `CreateSale` use case → existing `SyncRepository`.

The existing SQLite/sync engine remains the source of truth for offline work. No new cache or duplicate database has been introduced.

## Rules for subsequent stages

- Do not let widgets perform direct SQL/API work when a repository/use-case boundary already exists.
- New features must enter through a domain contract and data implementation.
- Keep offline writes optimistic and local-first.
- Do not remove existing sync/idempotency behavior.
- Extract large legacy screens incrementally, one feature at a time.
- Do not combine architecture migration with unrelated visual redesigns.

## Why Riverpod

Riverpod provides scoped dependency injection and observable async state without forcing the whole application into one giant provider tree. Existing `StatefulWidget` screens can therefore be migrated gradually.

## Completion gate

Stage 3 is considered complete only when:

- Riverpod is wired into the application.
- Domain/data/presentation boundaries exist.
- Session, dashboard and sale creation use those boundaries.
- At least one domain use case has automated tests.
- Existing backend regression tests remain green.
- Flutter analysis and tests remain green.
- Android release build remains available through the existing CI pipeline.

The remaining large-screen extraction is intentionally incremental and continues in Stage 4+ rather than being performed as a destructive rewrite.
