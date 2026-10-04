import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/api_client.dart';
import '../data/local_database.dart';
import 'package:location/location.dart';

class OmaPushNotifications {
  OmaPushNotifications._();

  static bool _ready = false;

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const AndroidInitializationSettings _androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  static const InitializationSettings _initSettings =
      InitializationSettings(android: _androidInit);

  static Future<void> requestInitialPermissions(LocalDatabase local) async {
    const key = 'initial_permissions_prompted';
    if (await local.getMeta(key) == '1') return;

    try {
      await _local.initialize(_initSettings);

      final android = _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();

      final location = Location();
      var permission = await location.hasPermission();
      if (permission == PermissionStatus.denied ||
          permission == PermissionStatus.deniedForever) {
        await location.requestPermission();
      }
    } catch (_) {
      // Permission prompts must never prevent the app from opening.
    } finally {
      await local.setMeta(key, '1');
    }
  }

  static Future<void> initialize(ApiClient api) async {
    if (_ready) return;

    final options = _options();
    if (options == null) return;

    try {
      await Firebase.initializeApp(options: options);
      final messaging = FirebaseMessaging.instance;

      await _local.initialize(_initSettings);

      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final vapid = const String.fromEnvironment('FCM_WEB_VAPID_KEY');
      final token = kIsWeb
          ? await messaging.getToken(vapidKey: vapid)
          : await messaging.getToken();

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

      FirebaseMessaging.onMessage.listen((message) async {
        if (kIsWeb) return;
        await _showAndRepeat(message.data);
      });

      _ready = true;
    } catch (_) {
      // Notification setup must never prevent the sales app from opening.
    }
  }

  /// Called by the Firebase background isolate on Android.
  @pragma('vm:entry-point')
  static Future<void> handleBackgroundMessage(
    RemoteMessage message,
  ) async {
    final options = _options();
    if (options == null) return;

    try {
      await Firebase.initializeApp(options: options);
      await _local.initialize(_initSettings);
      await _showAndRepeat(message.data);
    } catch (_) {
      // A notification failure must never crash the background isolate.
    }
  }

  static Future<void> _showAndRepeat(Map<String, dynamic> data) async {
    final title = '${data['title'] ?? 'OmaSales'}';
    final body = '${data['body'] ?? ''}';

    final mode = '${data['transport_mode'] ?? ''}'.toLowerCase();
    final soundName = mode == 'air'
        ? 'airport_arrival'
        : mode == 'sea'
            ? 'ship_horn'
            : '${data['sound'] ?? 'scanner_beep'}';

    final channelId = mode == 'air'
        ? 'oma_arrival_air_v2'
        : mode == 'sea'
            ? 'oma_arrival_sea_v2'
            : 'oma_scanner_v2';

    final channelName = mode == 'air'
        ? 'Air shipment arrivals'
        : mode == 'sea'
            ? 'Sea shipment arrivals'
            : 'Oma notifications';

    final details = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'OmaSales notifications',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(soundName),
      enableVibration: true,
    );

    final notificationDetails = NotificationDetails(
      android: details,
    );

    final rawId = int.tryParse(
      '${data['notification_id'] ?? ''}',
    );
    final id =
        rawId ?? DateTime.now().millisecondsSinceEpoch.remainder(2147483647);

    await _local.show(
      id,
      title,
      body,
      notificationDetails,
      payload: data['batch_id']?.toString() ??
          '${data['operation_id'] ?? ''}',
    );

    // Keep the exact same notification repeating every two hours until the
    // user opens the app. Opening/resuming Oma cancels all outstanding
    // reminders in clearPendingReminders().
    await _local.periodicallyShowWithDuration(
      id,
      title,
      body,
      const Duration(hours: 2),
      notificationDetails: notificationDetails,
      payload: data['batch_id']?.toString() ??
          '${data['operation_id'] ?? ''}',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> clearPendingReminders() async {
    try {
      await _local.cancelAll();
    } catch (_) {
      // Notification cleanup must never block app startup/resume.
    }
  }

  static FirebaseOptions? _options() {
    const apiKey = String.fromEnvironment('FCM_API_KEY');
    const appId = String.fromEnvironment('FCM_APP_ID');
    const messagingSenderId =
        String.fromEnvironment('FCM_MESSAGING_SENDER_ID');
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
