# Mobile + Website production deployment

This repository is the existing Flask website with the mobile backend/API additions merged into the same project.

- Render continues to deploy from the repository root using the existing `render.yaml` / `Procfile`.
- The existing website, templates, static files, routes and database models remain in their original locations.
- The `mobile/` directory is the separate Flutter client; Render does not run it.
- The mobile client talks to the Flask `/api/v1/*` endpoints and uses the same PostgreSQL database.
- New database migrations are included for mobile sync/idempotency.

Do not deploy an intermediate milestone. Before the first production deployment, run the Flutter analyzer/build in a Flutter/Android environment and perform a staging database migration/test.
