import 'dart:html' as html;

Future<void> showWebForegroundPush(Map<String, dynamic> data) async {
  if (html.Notification.permission != 'granted') return;
  final title = data['title']?.toString() ?? 'OmaSales';
  final body = data['body']?.toString() ?? '';
  final messageId = data['chat_message_id']?.toString() ?? '';
  final notification = html.Notification(title, body: body);
  notification.onClick.listen((_) {
    final query = messageId.isNotEmpty ? '?chat_message_id='+Uri.encodeComponent(messageId) : '';
    html.window.location.assign('/webapp/'+query);
  });
}
