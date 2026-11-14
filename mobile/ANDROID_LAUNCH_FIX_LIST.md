# OmaSales Android launch and mobile defect fix list

Source of truth: `main`  
Last audited: 2026-11-14  
Scope: Flutter mobile app, Android release packaging, and launch/runtime behavior.

This is a tracking list, not a claim that every item is already proven to cause the Samsung launch crash. Items marked **Investigate** require runtime evidence before changing behavior.

## Priority 0 — Android launch reliability

- [ ] **Investigate Firebase initialization and background-handler registration order.**
  - Files: `mobile/lib/main.dart`, `mobile/lib/core/push_notifications.dart`.
  - The background handler is registered in `main()`, while Firebase initialization is performed later by the notification service (and separately in the background handler).
  - Verify the exact FlutterFire version behavior. If required, initialize the default Firebase app before registering the handler, while keeping notification failures from blocking the first usable screen.
  - Do not treat this as the confirmed crash cause until Android Logcat/runtime evidence supports it.

- [ ] **Complete release-APK cold-start smoke testing and diagnose any crash from runtime logs.**
  - Test the signed release APK on the Android 16 emulator and, when possible, the Samsung S22 Ultra / Android 16.
  - Capture `FATAL EXCEPTION`, Flutter/Dart errors, native linker errors, process exit reason, and relevant startup logs.
  - Verify first launch, subsequent launch, and launch after device reboot.
  - A successful compile, `flutter analyze`, or Flutter Web build is not a substitute for this test.

## Priority 1 — Confirmed mobile reliability defects

- [ ] **Do not permanently mark notification permissions as handled after a failed setup.**
  - File: `mobile/lib/core/push_notifications.dart`, `requestInitialPermissions()`.
  - The `finally` block writes `initial_permissions_prompted = 1` even when local-notification initialization or permission setup throws.
  - This can suppress retries on later launches after a transient setup failure. Only persist the completion marker after the intended initialization/prompt flow succeeds, or store a separate failure/retry state.

## Priority 2 — Build and regression hardening

- [ ] **Make release signing configuration safe when local signing properties are absent.**
  - File: `mobile/android/app/build.gradle.kts`.
  - The release signing config force-casts values from `key.properties` even when that file does not exist. This can fail Gradle configuration for local debug builds before a release task is requested.
  - Configure signing only when properties are present; fail with a clear message only when a release build is requested without signing material. Never commit keystores or passwords.

- [ ] **Add explicit SQLite migration regression tests for every supported upgrade path.**
  - File: `mobile/lib/data/local_database.dart`.
  - The database is currently at schema version 9. Test fresh creation and upgrades from each prior supported version, including the version 5-to-9 path and index creation. Verify existing sales, sync queue rows, and product fields survive upgrades.

- [ ] **Add an Android-only startup integration test to CI that installs and launches the release APK.**
  - Keep the existing analysis, unit, architecture, and sync tests, but make the APK launch test a required release gate.
  - Preserve the diagnostic artifact (Logcat, emulator output, manifest, Gradle configuration, Flutter version, source commit) on both success and failure.

## Confirmed runtime evidence — 2026-11-14

- The release APK builds, installs, and is accepted by Android Activity Manager. The failure occurs after MainActivity.onStart() begins and while super.onStart() is executing.
- The captured logcat contains the entry marker `OmaStartup: MainActivity.onStart entering`, followed by a fatal NullPointerException in obfuscated frame `V.z.onStart(SourceFile:34)`. The exception is a call to `o0.c.d(String, z4.d)` on a null object.
- This places the observed failure in the native Android activity/lifecycle chain. It occurs before the first Flutter frame and before `_initializeOptionalServices()` runs. The unrelated Google `UpdateDataCacheStorageWorker` line is not the OmaSales crash.
- The previous release-only smoke test could not distinguish a release packaging issue from an activity/plugin lifecycle issue common to debug and release. The manual APK workflow now builds both variants, tests both on Android 16, and saves Gradle runtime dependency reports to its diagnostics artifact.
- The exact native library/plugin responsible is **not yet identified**. Do not remove `FlutterFragmentActivity`, disable the smoke test, or upgrade several plugins together before comparing the debug and release results and examining the dependency graph.

## Audit notes

- The current manifest declares the expected launcher activity and the package/namespace/application ID are consistently `com.omagroup.salesapp`.
- The current `MainActivity` extends `FlutterFragmentActivity`, matching the biometric-plugin requirement.
- The local database initialization is awaited before the app enters its session gate; its failure is rendered as an initialization error screen rather than intentionally exiting the process.
- These checks do not prove the absence of device-specific native/plugin crashes. Runtime logs remain the deciding evidence.
