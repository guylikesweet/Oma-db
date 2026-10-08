import 'package:firebase_messaging/firebase_messaging.dart';

Future<String?> getWebFcmToken(
  FirebaseMessaging messaging,
  String vapidKey,
) {
  return messaging.getToken(vapidKey: vapidKey);
}
