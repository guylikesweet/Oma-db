# Build the Android APK from your phone or Chromebook

This project is prepared to build the Android APK in GitHub Actions. You do **not** need Android Studio or Flutter installed on your phone/Chromebook.

## GitHub setup

1. Create a GitHub repository and upload the contents of this project.
2. Open **Actions**.
3. Select **Build Oma Mobile APK**.
4. Press **Run workflow**.
5. In `api_base_url`, enter your Render API URL, for example:
   `https://YOUR-RENDER-SERVICE.onrender.com/api`
6. Start the workflow.
7. Wait for both `Check Flask backend` and `Analyze and build Android APK` to succeed.
8. Open the completed workflow run and download the artifact named **oma-mobile-release-apk**.
9. Extract the artifact and install `app-release.apk` on your Android phone.

## Important

- The workflow builds the Android wrapper automatically if the `mobile/android` directory is not present.
- The production API URL is supplied at build time; it is not hard-coded into the source.
- Do not use an HTTP Render URL. Use the HTTPS URL.
- Do not deploy the Flutter `mobile` directory to Render. Render continues to host the Flask backend/website.
