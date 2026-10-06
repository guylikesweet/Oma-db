import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/api_client.dart';
import '../data/local_database.dart';
import 'package:location/location.dart';

import 'web_push_foreground.dart';

class OmaPushNotifications {
  OmaPushNotifications._();

  static bool _firebaseReady = false;
  static bool _tokenRefreshAttached = false;
  static bool _foregroundListenerAttached = false;
  static bool _messageTapListenerAttached = false;
  static ApiClient? _api;

  static final ValueNotifier<Map<String, dynamic>?> chatOpenRequest = ValueNotifier<Map<String, dynamic>?>(null);

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const AndroidInitializationSettings _androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  static const InitializationSettings _initSettings = InitializationSettings(android: _androidInit, iOS: DarwinInitializationSettings(), macOS: DarwinInitializationSettings());

  static Future<void> requestInitialPermissions(LocalDatabase local) async {
    const key = 'initial_permissions_prompted';
    if (await local.getMeta(key) == '1') return;

    try {
      await _local.initialize(_initSettings, onDidReceiveNotificationResponse: _handleLocalNotificationTap);

      final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      final ios = _local.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);

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
    _api = api;
    try {
      if (!_firebaseReady) {
        if (kIsWeb) {
          final options = _options();
          if (options == null) return;
          await Firebase.initializeApp(options: options);
        } else {
          // Android uses the native Firebase configuration generated from
          // google-services.json by the Google Services Gradle plugin.
          await Firebase.initializeApp();
        }
        _firebaseReady = true;
      }
      final messaging = FirebaseMessaging.instance;

      await _local.initialize(
        _initSettings,
        onDidReceiveNotificationResponse: _handleLocalNotificationTap,
      );

      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint(
          'OmaPush: notification permission is denied; FCM device registration skipped.',
        );
        return;
      }

      final vapid = const String.fromEnvironment('FCM_WEB_VAPID_KEY');
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        for (var attempt = 0; attempt < 10; attempt++) {
          if (await messaging.getAPNSToken() != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }

      final token = kIsWeb
          ? await messaging.getToken(vapidKey: vapid)
          : await messaging.getToken();

      if (token == null || token.isEmpty) {
        debugPrint('OmaPush: Firebase returned no FCM token.');
      } else {
        await _registerTokenWithRetry(
          api,
          token,
          kIsWeb ? 'web' : defaultTargetPlatform.name,
          notificationChannelVersion: kIsWeb ? null : 'v3',
        );
      }

      if (!_tokenRefreshAttached) {
        messaging.onTokenRefresh.listen((next) async {
          if (next.isNotEmpty) {
            try {
              await _registerTokenWithRetry(
                api,
                next,
                kIsWeb ? 'web' : defaultTargetPlatform.name,
                notificationChannelVersion: kIsWeb ? null : 'v3',
              );
            } catch (error, stackTrace) {
              debugPrint('OmaPush: refreshed FCM token registration failed: $error');
              debugPrint('$stackTrace');
            }
          }
        });
        _tokenRefreshAttached = true;
      }

      if (!_foregroundListenerAttached) {
        FirebaseMessaging.onMessage.listen((message) async {
          if (kIsWeb) {
            await showWebForegroundPush(message.data);
            return;
          }
          await _showAndRepeat(message.data);
        });
        _foregroundListenerAttached = true;
      }

      if (!_messageTapListenerAttached) {
        FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessageTap);
        _messageTapListenerAttached = true;
      }

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleRemoteMessageTap(initialMessage);
      }

      await restoreNotificationLaunch();
    } catch (error, stackTrace) {
      debugPrint('OmaPush initialize failed: $error');
      debugPrint('$stackTrace');
      // Notification setup must never prevent the sales app from opening.
    }
  }

  static Future<void> _registerTokenWithRetry(
    ApiClient api,
    String token,
    String platform, {
    String? notificationChannelVersion,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await api.registerPushDevice(
          token,
          platform,
          notificationChannelVersion: notificationChannelVersion,
        );
        debugPrint(
          'OmaPush: FCM device registered '
          '(platform=$platform, channel=${notificationChannelVersion ?? 'legacy'}, '
          'attempt=$attempt, response=$response)',
        );
        return;
      } catch (error, stackTrace) {
        lastError = error;
        debugPrint(
          'OmaPush: FCM device registration failed '
          '(attempt=$attempt/3): $error',
        );
        debugPrint('$stackTrace');
        if (attempt < 3) {
          await Future<void>.delayed(
            Duration(milliseconds: 700 * attempt),
          );
        }
      }
    }
    throw StateError(
      'Unable to register this device for push notifications: $lastError',
    );
  }
  /// Called by the Firebase background isolate on Android.
  @pragma('vm:entry-point')
  static Future<void> handleBackgroundMessage(
    RemoteMessage message,
  ) async {
    try {
      if (!_firebaseReady) {
        if (kIsWeb) {
          final options = _options();
          if (options == null) return;
          await Firebase.initializeApp(options: options);
        } else {
          // Background Android isolates use the same native Firebase
          // configuration installed from google-services.json.
          await Firebase.initializeApp();
        }
        _firebaseReady = true;
      }
      await _local.initialize(_initSettings, onDidReceiveNotificationResponse: _handleLocalNotificationTap);
      // Android/iOS now receive a native visible notification from FCM for
      // background/terminated delivery. Do not create a second local copy.
      // Data-only messages (older server/client combinations) still use the
      // local notification fallback.
      if (message.notification == null) {
        await _showAndRepeat(message.data);
      }
    } catch (_) {
      // A notification failure must never crash the background isolate.
    }
  }

  static Future<void> _showAndRepeat(Map<String, dynamic> data) async {
    final title = '${data['title'] ?? 'OmaSales'}';
    final body = '${data['body'] ?? ''}';

    final type = '${data['type'] ?? ''}';
    final isChat = type == 'chat_message';
    final mode = '${data['transport_mode'] ?? ''}'.toLowerCase();

    final soundName = isChat
        ? 'chat_message'
        : mode == 'air'
            ? 'airport_arrival'
            : mode == 'sea'
                ? 'ship_horn'
                : '${data['sound'] ?? 'scanner_beep'}';

    final channelId = isChat
        ? 'oma_chat_v3'
        : mode == 'air'
            ? 'oma_arrival_air_v3'
            : mode == 'sea'
                ? 'oma_arrival_sea_v3'
                : 'oma_scanner_v3';

    final channelName = isChat
        ? 'Oma team chat'
        : mode == 'air'
            ? 'Air shipment arrivals'
            : mode == 'sea'
                ? 'Sea shipment arrivals'
                : 'Oma notifications';

    AndroidBitmap<Object>? largeIcon;
    final avatarUrl = '${data['sender_avatar_url'] ?? ''}'.trim();
    if (isChat && avatarUrl.isNotEmpty && !kIsWeb) {
      try {
        final bytes = await ApiClient().downloadChatAttachment(avatarUrl);
        if (bytes.isNotEmpty) {
          largeIcon = ByteArrayAndroidBitmap(bytes);
        }
      } catch (_) {
        // Avatar loading is best-effort; the notification must still appear.
      }
    }
    final details = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'OmaSales notifications',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(soundName),
      enableVibration: true,
      largeIcon: largeIcon,
    );

    final notificationDetails = NotificationDetails(
      android: details,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      ),
    );

    final rawId = int.tryParse(
      '${data['notification_id'] ?? ''}',
    );
    final id =
        rawId ?? DateTime.now().millisecondsSinceEpoch.remainder(2147483647);

    final payload = jsonEncode(data);
    await _local.show(id, title, body, notificationDetails, payload: payload);

    // Business notifications keep the existing two-hour reminder.
    // Chat messages intentionally do not repeat: a busy team chat should not
    // create an endless stream of scheduled reminders.
    if (isChat) return;

    await _local.periodicallyShowWithDuration(
      id,
      title,
      body,
      const Duration(hours: 2),
      notificationDetails,
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static void _handleRemoteMessageTap(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    if (data.isEmpty) return;
    chatOpenRequest.value = data;
  }

  static void _handleLocalNotificationTap(NotificationResponse response) {
    final raw = response.payload;
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) chatOpenRequest.value = Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }

  static Future<void> restoreNotificationLaunch() async {
    try {
      final details = await _local.getNotificationAppLaunchDetails();
      final raw = details?.notificationResponse?.payload;
      if (details?.didNotificationLaunchApp == true && raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) chatOpenRequest.value = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
  }

  static Future<void> retryRegistration() async {
    final api = _api;
    if (api == null || !_firebaseReady) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.getNotificationSettings();
      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('OmaPush: retry skipped because notification permission is denied.');
        return;
      }
      final token = kIsWeb
          ? await messaging.getToken(vapidKey: const String.fromEnvironment('FCM_WEB_VAPID_KEY'))
          : await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _registerTokenWithRetry(
        api,
        token,
        kIsWeb ? 'web' : defaultTargetPlatform.name,
        notificationChannelVersion: kIsWeb ? null : 'v3',
      );
    } catch (error, stackTrace) {
      debugPrint('OmaPush: retry registration failed: $error');
      debugPrint('$stackTrace');
    }
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
