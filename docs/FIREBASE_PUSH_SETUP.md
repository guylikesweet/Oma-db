# Firebase push notifications

Oma uses Firebase Cloud Messaging (FCM). Firebase Cloud Messaging is a no-cost Firebase product.

## GitHub Actions secrets

Add these repository secrets before building the Flutter APK/web app:

- FCM_API_KEY
- FCM_APP_ID
- FCM_MESSAGING_SENDER_ID
- FCM_PROJECT_ID
- FCM_AUTH_DOMAIN
- FCM_STORAGE_BUCKET
- FCM_WEB_VAPID_KEY

These values come from the Firebase project Web/Android app configuration and Cloud Messaging Web Push certificates.

## Render

Add:

- FIREBASE_CREDENTIALS_JSON

Use the Firebase service-account JSON as the value. Never commit the JSON file.

## Notifications

- Sea batch arrival: ship-horn channel.
- Air batch arrival: airport-arrival channel.
- Other operational notifications: scanner-beep channel.

The backend writes notification intent to `notification_outbox` in the same database transaction as the business event. FCM delivery can therefore be retried without losing the event.

The client registers and refreshes FCM device tokens through the authenticated API.
