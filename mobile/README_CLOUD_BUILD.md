# Build the OmaSales Android APK from a phone or Chromebook

OmaSales can build its Android APK and AAB in GitHub Actions. You do **not** need Android Studio or Flutter installed on your phone or Chromebook.

## GitHub setup

1. Open the repository's **Actions** tab.
2. Select **Build OmaSales Mobile**.
3. Press **Run workflow**.
4. In the **Backend API base URL** input, leave the default unless you are intentionally building against another HTTPS backend.
   - Production default: `https://oma-db.onrender.com/api`
5. Start the workflow.
6. Wait for the build to finish.
7. Open the completed workflow run and download the artifact named **OmaSales-APK-<run number>** for the APK, or **OmaSales-AAB-<run number>** for the Android App Bundle.
8. Install `OmaSales-Mobile.apk` on Android, or use the AAB for Play Console distribution.

## Important

- The workflow performs a backend/mobile compatibility preflight before the Flutter build.
- The Android project is generated automatically when `mobile/android` is not present.
- The production API URL is supplied at build time; it is not hard-coded into the release build.
- Release builds require an HTTPS API URL.
- Firebase Web configuration is required for the Web build, while the Android build uses the configured Firebase Android setup.
- Do not deploy the Flutter `mobile` directory directly to Render. Render continues to host the Flask backend and website.
