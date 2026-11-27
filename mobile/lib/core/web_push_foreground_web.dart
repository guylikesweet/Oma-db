import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> showWebForegroundPush(Map<String, dynamic> data) async {
  if (web.Notification.permission != 'granted') return;
  final title = data['title']?.toString() ?? 'OmaSales';
  final body = data['body']?.toString() ?? '';
  final messageId = data['chat_message_id']?.toString() ?? '';
  final notification = web.Notification(
    title,
    web.NotificationOptions(body: body),
  );
  notification.addEventListener('click', ((web.Event _) {
    final query = messageId.isNotEmpty
        ? '?chat_message_id=${Uri.encodeComponent(messageId)}'
        : '';
    web.window.location.assign('/webapp/' + query);
  }).toJS);
}
