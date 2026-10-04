import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../data/api_client.dart';

class OmaPushNotifications {
  OmaPushNotifications._();

  static bool _ready = false;

  static Future<void> initialize(ApiClient api) async {
    if (_ready) return;

    final options = _options();
    if (options == null) return;

    try {
      await Firebase.initializeApp(options: options);
      final messaging = FirebaseMessaging.instance;

      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await messaging.getToken(
        vapidKey: const String.fromEnvironment('FCM_WEB_VAPID_KEY'),
      );
      if (token != null && token.isNotEmpty) {
        await api.registerPushDevice(
          token,
          kIsWeb ? 'web' : defaultTargetPlatform.name,
        );
      }

      messaging.onTokenRefresh.listen((next) async {
        if (next.isNotEmpty) {
          await api.registerPushDevice(
            next,
            kIsWeb ? 'web' : defaultTargetPlatform.name,
          );
        }
      });

      FirebaseMessaging.onMessage.listen((message) {
        // Foreground messages are intentionally kept quiet here. The native
        // system notification handles background delivery; foreground UI can
        // surface the same event without producing duplicate alerts.
      });

      _ready = true;
    } catch (_) {
      // Notification setup must never prevent the sales app from opening.
    }
  }

  static FirebaseOptions? _options() {
    const apiKey = String.fromEnvironment('FCM_API_KEY');
    const appId = String.fromEnvironment('FCM_APP_ID');
    const messagingSenderId = String.fromEnvironment('FCM_MESSAGING_SENDER_ID');
    const projectId = String.fromEnvironment('FCM_PROJECT_ID');

    if ([apiKey, appId, messagingSenderId, projectId]
        .any((x) => x.isEmpty)) {
      return null;
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: const String.fromEnvironment('FCM_AUTH_DOMAIN'),
      storageBucket: const String.fromEnvironment('FCM_STORAGE_BUCKET'),
    );
  }
}
