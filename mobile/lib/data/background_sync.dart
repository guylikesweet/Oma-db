import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:workmanager/workmanager.dart';

import 'api_client.dart';
import 'local_database.dart';
import 'sync_repository.dart';

const omaBackgroundSyncTask = 'oma_background_sync';
const _periodicSyncName = 'oma_periodic_sync';
const _startupSyncName = 'oma_startup_sync';

@pragma('vm:entry-point')
void omaBackgroundCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != omaBackgroundSyncTask) return true;

    try {
      final api = ApiClient();
      final token = await api.token();

      // A logged-out device cannot authenticate queued work. Do not turn that
      // into a permanent queue failure; the next login/foreground sync will
      // resume it with a fresh token.
      if (token == null || token.isEmpty) return true;

      final local = LocalDatabase.instance;
      await local.db;
      final repository = SyncRepository(api, local);
      await repository.syncOnce();
      return true;
    } catch (_) {
      // Returning false lets the OS scheduler retry the worker using its
      // persisted backoff policy. The SQLite queue itself remains untouched.
      return false;
    }
  });
}

class OmaBackgroundSync {
  OmaBackgroundSync._();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_initialized) return;

    await Workmanager().initialize(
      omaBackgroundCallbackDispatcher,
      isInDebugMode: false,
    );
    _initialized = true;

    await Workmanager().registerPeriodicTask(
      _periodicSyncName,
      omaBackgroundSyncTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  /// Requests a prompt one-off sync after app startup. KEEP makes repeated
  /// launches harmless; the periodic worker remains the long-lived fallback.
  static Future<void> requestStartupSync() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (!_initialized) await initialize();

    await Workmanager().registerOneOffTask(
      _startupSyncName,
      omaBackgroundSyncTask,
      initialDelay: const Duration(seconds: 15),
      constraints: const Constraints(
        networkType: NetworkType.connected,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }
}
