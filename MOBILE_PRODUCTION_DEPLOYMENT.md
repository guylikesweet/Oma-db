# Mobile + Flutter Web production deployment

This repository contains the Flask backend/database plus the Flutter Web and Android client.

- Render deploys the Flask backend from the repository root using render.yaml / run.py.
- The Flutter Web application is served from / and the compiled SPA is also available under /webapp/.
- The legacy Flask/Jinja interface remains available under /classic.
- The Flutter client uses the Flask /api/v1/* endpoints and the same PostgreSQL database.
- Android uses an offline SQLite/IndexedDB-compatible local data layer and an idempotent sync queue; the Web build intentionally performs online writes rather than exposing the mobile sync queue.
- Database migrations for mobile sync, session security, chat, profile data and landed-cost pricing are part of the production migration chain.

## Before releasing an APK

1. Run the manual .github/workflows/build-oma-apk.yml workflow.
2. Confirm the backend/mobile compatibility preflight passes.
3. Confirm flutter analyze passes.
4. Confirm the APK/AAB build completes.
5. Keep the Android signing configuration stable so updates preserve the installed app's local data.

## Before promoting Flutter Web

Run the manual .github/workflows/build-oma-web.yml workflow and verify the compiled Web application against the deployed /api/v1/* backend. The workflow publishes the compiled build to app/static/webapp/; the next Render deployment serves that build from / and /webapp/.

Do not deploy an intermediate milestone without checking both the backend migration result and the generated client build.
