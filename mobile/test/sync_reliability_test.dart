import 'package:flutter_test/flutter_test.dart';

import '../lib/data/api_client.dart';
import '../lib/data/sync_policy.dart';

void main() {
  group('SyncPolicy', () {
    test('classifies client errors as permanent', () {
      expect(SyncPolicy.isPermanentError(ApiException(400, 'bad request')), isTrue);
      expect(SyncPolicy.isPermanentError(ApiException(401, 'unauthorized')), isTrue);
      expect(SyncPolicy.isPermanentError(ApiException(409, 'conflict')), isTrue);
      expect(SyncPolicy.isPermanentError(ApiException(422, 'invalid')), isTrue);
    });

    test('classifies server and network errors as retryable', () {
      expect(SyncPolicy.isPermanentError(ApiException(500, 'server error')), isFalse);
      expect(SyncPolicy.isPermanentError(ApiException(0, 'network')), isFalse);
      expect(SyncPolicy.isPermanentError(Exception('network')), isFalse);
    });

    test('uses bounded exponential-style retry windows', () {
      expect(SyncPolicy.retryDelay(1), const Duration(seconds: 15));
      expect(SyncPolicy.retryDelay(2), const Duration(minutes: 1));
      expect(SyncPolicy.retryDelay(4), const Duration(minutes: 5));
      expect(SyncPolicy.retryDelay(7), const Duration(minutes: 15));
      expect(SyncPolicy.retryDelay(100), const Duration(minutes: 15));
    });
  });
}
