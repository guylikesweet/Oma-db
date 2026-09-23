import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'sync_repository.dart';

class ConnectivitySync {
  ConnectivitySync(this.repository);
  final SyncRepository repository;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _running = false;

  void start() {
    _subscription ??= Connectivity().onConnectivityChanged.listen((_) => syncNow());
  }

  Future<SyncResult?> syncNow() async {
    if (_running) return null;
    _running = true;
    try {
      return await repository.syncOnce();
    } catch (_) {
      return null;
    } finally {
      _running = false;
    }
  }

  Future<void> dispose() async => _subscription?.cancel();
}
