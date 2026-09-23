# Android update safety

Future APKs can update the installed Oma Mobile app and keep its private SQLite data when the Android application ID and release signing key remain unchanged and the app is installed as an update (not uninstalled first).

## Required for production builds

Keep one release keystore permanently. Do not commit the `.jks` file or passwords to Git. Configure the keystore through GitHub Actions secrets before publishing release APKs.

The mobile SQLite database uses versioned `sqflite` migrations. When changing its schema, increase the database version and add an `onUpgrade` migration rather than deleting/recreating the database.

Uninstalling the app, clearing its storage, changing the application ID, or losing/changing the signing key can prevent an in-place update or remove local data.
