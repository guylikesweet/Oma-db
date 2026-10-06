import 'api_client.dart';

class SyncPolicy {
  const SyncPolicy._();

  static bool isPermanentError(Object error) {
    if (error is ApiException) {
      return const {400, 403, 404, 409, 410, 422}.contains(error.statusCode);
    }
    return false;
  }

  static Duration retryDelay(int attempts) {
    if (attempts <= 1) return const Duration(seconds: 15);
    if (attempts <= 3) return const Duration(minutes: 1);
    if (attempts <= 6) return const Duration(minutes: 5);
    return const Duration(minutes: 15);
  }
}
