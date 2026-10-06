import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'brand_loader.dart';
import 'data/api_client.dart';
import 'data/app_session.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController composer = TextEditingController();
  final ScrollController scroll = ScrollController();
  final ImagePicker picker = ImagePicker();
  Uint8List? attachmentBytes;
  String? attachmentName;
  bool emojiOpen = false;
  final Map<int, Uint8List> photoCache = {};
  final Map<int, Uint8List> avatarCache = {};
  final Map<int, GlobalKey> messageKeys = {};
  static const emojiChoices = <String>[
    '😀','😂','😍','🥰','😎','😭','😅','😮','😢','😡',
    '👍','👎','👏','🙌','🙏','❤️','🔥','🎉','💯','✅',
    '👀','🤝','💪','🚀','⭐','🤣','😊','😉','😘','🤔',
    '😴','🥳','🤩','😇','😱','🤗','🫡','❤️‍🔥','🎯','📦',
  ];

  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> users = [];
  Map<String, dynamic>? replyTo;
  bool loading = true;
  bool sending = false;
  String? error;
  int _localSequence = 0;
  Timer? poller;

  @override
  void initState() {
    super.initState();
    load();
    poller = Timer.periodic(
      const Duration(seconds: 4),
      (_) => load(silent: true),
    );
  }

  @override
  void dispose() {
    poller?.cancel();
    composer.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    try {
      final results = await Future.wait([
        widget.api.chatMessages(limit: 100),
        if (users.isEmpty) widget.api.users(),
      ]);

      final serverMessages = results[0]
          .whereType<Map>()
          .map((message) => Map<String, dynamic>.from(message))
          .toList();

      // Polling must never make an optimistic bubble disappear while a
      // request is still in flight (or after a failed send).
      final localMessages = messages
          .where((message) => '${message['id'] ?? ''}'.startsWith('local-'))
          .toList();

      final serverIds = serverMessages
          .map((message) => '${message['id'] ?? ''}')
          .toSet();

      final nextMessages = [
        ...serverMessages,
        ...localMessages.where(
          (message) => !serverIds.contains('${message['id'] ?? ''}'),
        ),
      ];

      final previousLastId =
          messages.isEmpty ? null : messages.last['id'];

      final nextUsers = users.isEmpty
          ? results[1]
              .whereType<Map>()
              .map((user) => Map<String, dynamic>.from(user))
              .toList()
          : users;

      if (!mounted) return;

      setState(() {
        messages = nextMessages;
        users = nextUsers;
        loading = false;
        error = null;
      });

      final nextLastId =
          nextMessages.isEmpty ? null : nextMessages.last['id'];

      if (previousLastId == null) {
        _scrollToBottom(animated: false);
      } else if (nextLastId != previousLastId) {
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      var message = '${e}';
      if (e is ApiException &&
          e.statusCode == 503 &&
          AppSession.isAdmin) {
        try {
          final diagnostic = await widget.api.chatDiagnostic();
          message = '${e}\\nDiagnostic: ${jsonEncode(diagnostic)}';
        } catch (_) {
          // Keep the original server error if the protected diagnostic
          // endpoint is itself unavailable.
        }
      }
      if (!silent || messages.isEmpty) {
        setState(() {
          loading = false;
          error = message;
        });
      }
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      final target = scroll.position.maxScrollExtent;
      if (animated) {
        scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        scroll.jumpTo(target);
      }
    });
  }

  Future<void> send() async {
    final text = composer.text.trim();
    if ((text.isEmpty && attachmentBytes == null) || sending) return;

    final replyId = replyTo?['id'];
    final localId = 'local-${++_localSequence}';
    final now = DateTime.now().toIso8601String();
    final localPhoto = attachmentBytes;
    final localName = attachmentName;
    final optimistic = <String, dynamic>{
      'id': localId,
      'sender_user_id': AppSession.userId,
      'sender_username': AppSession.username.isEmpty ? 'You' : AppSession.username,
      'content': text,
      'created_at': now,
      'reply_to': replyTo,
      '_status': 'sending',
      '_attachment_bytes': localPhoto,
      'attachment_filename': localName,
    };

    setState(() {
      sending = true;
      messages = [...messages, optimistic];
      composer.clear();
      replyTo = null;
      attachmentBytes = null;
      attachmentName = null;
      emojiOpen = false;
    });
    _scrollToBottom();

    try {
      final sent = await widget.api.sendChatMessage(
        text,
        replyToId: replyId is int ? replyId : int.tryParse('$replyId'),
        attachmentBase64: localPhoto == null ? null : base64Encode(localPhoto),
        attachmentFilename: localName,
      );

      if (!mounted) return;
      setState(() {
        messages = messages
            .map(
              (message) => message['id'] == localId
                  ? <String, dynamic>{...sent, '_status': 'sent'}
                  : message,
            )
            .toList();
        sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        messages = messages
            .map(
              (message) => message['id'] == localId
                  ? <String, dynamic>{...message, '_status': 'failed'}
                  : message,
            )
            .toList();
        sending = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> pickPhoto() async {
    try {
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        attachmentBytes = bytes;
        attachmentName = file.name;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not select photo: $e')),
        );
      }
    }
  }

  void insertEmoji(String emoji) {
    final value = composer.value;
    final start = value.selection.start < 0 ? value.text.length : value.selection.start;
    final end = value.selection.end < 0 ? start : value.selection.end;
    final next = value.text.replaceRange(start, end, emoji);
    composer.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    setState(() => emojiOpen = false);
  }

  Future<void> editMessage(Map<String, dynamic> message) async {
    final id = int.tryParse('${message['id']}');
    if (id == null) return;
    final controller = TextEditingController(text: '${message['content'] ?? ''}');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, shape: BoxShape.circle), child: const Icon(Icons.auto_fix_high_rounded)), const SizedBox(width: 10), const Text('Polish your message')]),
        content: TextField(controller: controller, autofocus: true, maxLines: 6, decoration: InputDecoration(hintText: 'Make it better…', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep it')),
          FilledButton.icon(onPressed: () => Navigator.pop(context, controller.text.trim()), icon: const Icon(Icons.check_rounded), label: const Text('Update')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty || !mounted) return;
    try {
      final updated = await widget.api.updateChatMessage(id, result);
      if (mounted) setState(() => messages = messages.map((m) => '${m['id']}' == '$id' ? updated : m).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not edit message: $e')));
    }
  }

  Future<void> deleteMessage(Map<String, dynamic> message) async {
    final id = int.tryParse('${message['id']}');
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('The message will be marked as deleted. Administrators can still review it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final updated = await widget.api.deleteChatMessage(id);
      if (mounted) setState(() => messages = messages.map((m) => '${m['id']}' == '$id' ? updated : m).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete message: $e')));
    }
  }

  Future<void> react(Map<String, dynamic> message, String emoji) async {
    final id = int.tryParse('${message['id']}');
    if (id == null) return;
    try {
      final updated = await widget.api.reactToChatMessage(id, emoji);
      if (mounted) setState(() => messages = messages.map((m) => '${m['id']}' == '$id' ? updated : m).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not react: $e')));
    }
  }

  Future<void> copyMessage(Map<String, dynamic> message) async {
    final text = '${message['content'] ?? ''}';
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied ✨'), behavior: SnackBarBehavior.floating));
  }

  Future<void> downloadPhoto(Map<String, dynamic> message) async {
    final id = int.tryParse('${message['id']}');
    final url = '${message['attachment_url'] ?? ''}';
    if (id == null || url.isEmpty) return;
    try {
      final bytes = photoCache[id] ?? await widget.api.downloadChatAttachment(url);
      photoCache[id] = bytes;
      await Share.shareXFiles([
        XFile.fromData(bytes, name: '${message['attachment_filename'] ?? 'chat-photo.jpg'}', mimeType: 'image/jpeg'),
      ], text: 'Oma team chat photo');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not download photo: $e')));
    }
  }

  Future<void> showReactionPicker(Map<String, dynamic> message) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          alignment: WrapAlignment.center,
          children: emojiChoices.map((emoji) => InkWell(
            onTap: () { Navigator.pop(context); react(message, emoji); },
            child: Padding(padding: const EdgeInsets.all(12), child: Text(emoji, style: const TextStyle(fontSize: 28))),
          )).toList(),
        ),
      ),
    );
  }

  void _replyTo(Map<String, dynamic> message) {
    setState(() => replyTo = message);
  }

  String _quoteText(Map<String, dynamic> message) {
    final deleted = message['deleted'] == true;
    if (deleted) return 'Message deleted';

    final content = '${message['content'] ?? ''}'.trim();
    if (content.isNotEmpty) return content;

    if ('${message['attachment_url'] ?? ''}'.isNotEmpty ||
        message['_attachment_bytes'] is Uint8List) {
      return 'Photo';
    }

    return 'Message';
  }

  Widget _quotedMessage(Map<String, dynamic> reply, {String? replyAuthor}) {
    final scheme = Theme.of(context).colorScheme;
    final sender = '${reply['sender_username'] ?? 'User'}';
    final deleted = reply['deleted'] == true;
    final hasPhoto = '${reply['attachment_url'] ?? ''}'.isNotEmpty ||
        reply['_attachment_bytes'] is Uint8List;
    final quote = _quoteText(reply);
    final replyId = reply['id'] is int ? reply['id'] as int : int.tryParse('${reply['id']}');

    return InkWell(
      onTap: replyId == null ? null : () => _jumpToMessage(replyId),
      borderRadius: BorderRadius.circular(10),
      child: Container(
      margin: const EdgeInsets.only(top: 5, bottom: 7),
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(.55),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: mineQuoteColor(reply),
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          if (hasPhoto) ...[
            Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.only(right: 8),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.photo_outlined, size: 20),
            ),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  replyAuthor == null || replyAuthor.isEmpty ? 'Replying to $sender' : '$replyAuthor → $sender',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: mineQuoteColor(reply),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  quote,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: deleted ? FontStyle.italic : FontStyle.normal,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Color mineQuoteColor(Map<String, dynamic> reply) {
    final isMine = reply['sender_user_id'] == AppSession.userId;
    final scheme = Theme.of(context).colorScheme;
    return isMine ? scheme.primary : scheme.secondary;
  }

  void _selectMention(
    Map<String, dynamic> user,
    TextEditingController controller,
  ) {
    final text = controller.text;
    final cursor = controller.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) return;

    final before = text.substring(0, cursor);
    final match = RegExp(
      r'(^|\s)@([A-Za-z0-9_.-]*)$',
    ).firstMatch(before);
    if (match == null) return;

    final start = match.start + (match.group(1)?.length ?? 0);
    final replacement = '@${user['username'] ?? ''} ';
    final next = text.replaceRange(start, cursor, replacement);

    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: start + replacement.length,
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyTo != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.reply, size: 18),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Replying to ${replyTo!['sender_username'] ?? 'user'}: '
                          '${_quoteText(replyTo!)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => replyTo = null),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              if (replyTo != null) const SizedBox(height: 7),
              RawAutocomplete<Map<String, dynamic>>(
                textEditingController: composer,
                optionsViewOpenDirection: OptionsViewOpenDirection.up,
                displayStringForOption: (user) =>
                    '@${user['username'] ?? ''}',
                optionsBuilder: (value) {
                  final text = value.text;
                  final cursor = value.selection.baseOffset;
                  if (cursor < 0 || cursor > text.length) {
                    return const <Map<String, dynamic>>[];
                  }
                  final before = text.substring(0, cursor);
                  final match = RegExp(
                    r'(^|\s)@([A-Za-z0-9_.-]*)$',
                  ).firstMatch(before);
                  if (match == null) {
                    return const <Map<String, dynamic>>[];
                  }

                  final query =
                      '${match.group(2) ?? ''}'.toLowerCase();

                  return users.where((user) {
                    if (user['is_active'] == false) return false;
                    final username =
                        '${user['username'] ?? ''}'.toLowerCase();
                    return username.startsWith(query);
                  }).take(8);
                },
                onSelected: (user) =>
                    _selectMention(user, composer),
                optionsViewBuilder: (
                  context,
                  onSelected,
                  options,
                ) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 240,
                          minWidth: 220,
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final user = options.elementAt(index);
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.person_outline),
                              title: Text(
                                '@' + (user['username'] ?? ''),
                              ),
                              onTap: () => onSelected(user),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
                fieldViewBuilder: (
                  context,
                  controller,
                  focusNode,
                  onFieldSubmitted,
                ) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Message the team… use @ to mention',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  );
                },
              ),
              if (attachmentBytes != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Image.memory(attachmentBytes!, width: 54, height: 54, fit: BoxFit.cover),
                      const SizedBox(width: 8),
                      Expanded(child: Text(attachmentName ?? 'Photo')),
                      IconButton(
                        onPressed: () => setState(() {
                          attachmentBytes = null;
                          attachmentName = null;
                        }),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              if (emojiOpen)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: emojiChoices.map((emoji) => InkWell(
                      onTap: () => insertEmoji(emoji),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Text(emoji, style: const TextStyle(fontSize: 22)),
                      ),
                    )).toList(),
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Emoji',
                    onPressed: sending ? null : () => setState(() => emojiOpen = !emojiOpen),
                    icon: const Icon(Icons.emoji_emotions_outlined),
                  ),
                  IconButton(
                    tooltip: 'Photo',
                    onPressed: sending ? null : pickPhoto,
                    icon: const Icon(Icons.photo_outlined),
                  ),
                  const Spacer(),
                  IconButton.filled(
                  onPressed: sending ? null : send,
                  icon: sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send),
                ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoWidget(Map<String, dynamic> message) {
    final local = message['_attachment_bytes'];
    if (local is Uint8List) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(local, width: 260, height: 220, fit: BoxFit.cover),
      );
    }
    final id = int.tryParse('${message['id']}');
    final url = '${message['attachment_url'] ?? ''}';
    if (id == null || url.isEmpty) return const SizedBox.shrink();
    if (photoCache[id] != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(photoCache[id]!, width: 260, height: 220, fit: BoxFit.cover),
      );
    }
    return FutureBuilder<Uint8List>(
      future: widget.api.downloadChatAttachment(url),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          photoCache[id] = snapshot.data!;
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(snapshot.data!, width: 260, height: 220, fit: BoxFit.cover),
          );
        }
        return const SizedBox(
          width: 260,
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Future<void> _jumpToMessage(int id) async {
    final key = messageKeys[id];
    final target = key?.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: .35,
    );
  }

  Widget _chatAction({
    required IconData icon,
    required String label,
    required bool mine,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = mine ? Colors.white : scheme.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: Material(
        color: mine ? Colors.white.withOpacity(.12) : scheme.surface.withOpacity(.72),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: foreground),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: foreground)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _lagosTime(dynamic raw) {
    if (raw == null || raw.toString().trim().isEmpty) return '';
    try {
      var value = raw.toString().trim();
      if (!value.endsWith('Z') &&
          !RegExp(r'[+-]\\d{2}:?\\d{2}$').hasMatch(value)) {
        value = '${value}Z';
      }
      final utc = DateTime.parse(value).toUtc();
      final lagos = utc.add(const Duration(hours: 1));
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(lagos.day)}/${two(lagos.month)}/${lagos.year} ${two(lagos.hour)}:${two(lagos.minute)}';
    } catch (_) {
      return raw.toString().replaceFirst('T', ' ').split('.').first;
    }
  }
  Widget _senderAvatar(Map<String, dynamic> message, String sender) {
    final scheme = Theme.of(context).colorScheme;
    final rawId = message['sender_user_id'];
    final userId = rawId is int ? rawId : int.tryParse('$rawId');
    final url = message['sender_profile_photo_url']?.toString() ?? '';

    if (userId == null || url.isEmpty) {
      return CircleAvatar(
        radius: 13,
        backgroundColor: scheme.primaryContainer,
        child: Text(
          sender.trim().isEmpty ? '?' : sender.trim()[0].toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: scheme.onPrimaryContainer,
          ),
        ),
      );
    }

    final cached = avatarCache[userId];
    if (cached != null) {
      return CircleAvatar(
        radius: 13,
        backgroundImage: MemoryImage(cached),
        backgroundColor: scheme.primaryContainer,
      );
    }

    return FutureBuilder<Uint8List>(
      future: widget.api.downloadChatAttachment(url),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          avatarCache[userId] = snapshot.data!;
          return CircleAvatar(
            radius: 13,
            backgroundImage: MemoryImage(snapshot.data!),
            backgroundColor: scheme.primaryContainer,
          );
        }
        return CircleAvatar(
          radius: 13,
          backgroundColor: scheme.primaryContainer,
          child: Text(
            sender.trim().isEmpty ? '?' : sender.trim()[0].toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: scheme.onPrimaryContainer,
            ),
          ),
        );
      },
    );
  }

  Widget _messageBubble(Map<String, dynamic> message) {
    final mine = message['sender_user_id'] == AppSession.userId;
    final status = '${message['_status'] ?? 'sent'}';
    final pending = status == 'sending';
    final failed = status == 'failed';
    final reply = message['reply_to'];
    final sender = mine ? 'Me' : '${message['sender_username'] ?? 'User'}';
    final created = _lagosTime(message['created_at']);
    final deleted = message['deleted'] == true;
    final canModify = !pending && !failed && !deleted && (mine || AppSession.isAdmin);

    final scheme = Theme.of(context).colorScheme;
    final bubbleGradient = mine
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: pending || failed
                ? [
                    scheme.surfaceContainerHighest,
                    scheme.surfaceContainer,
                  ]
                : [
                    scheme.primary,
                    scheme.primary.withOpacity(.78),
                    scheme.primaryContainer,
                  ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surfaceContainerHighest,
              scheme.surface,
            ],
          );

    final messageId = message['id'] is int ? message['id'] as int : int.tryParse('${message['id']}');
    final messageKey = messageId == null
        ? null
        : (messageKeys[messageId] ??= GlobalKey());

    return Align(
      key: messageKey,
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: failed ? null : () => _replyTo(message),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            IgnorePointer(
              child: Positioned(
                bottom: 10,
                left: mine ? null : 5,
                right: mine ? 5 : null,
                child: Transform.rotate(
                  angle: 0.785398,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      gradient: bubbleGradient,
                      border: Border(
                        right: BorderSide(
                          color: mine && !pending && !failed
                              ? Colors.white.withOpacity(.22)
                              : scheme.outline.withOpacity(.45),
                        ),
                        bottom: BorderSide(
                          color: mine && !pending && !failed
                              ? Colors.white.withOpacity(.22)
                              : scheme.outline.withOpacity(.45),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(maxWidth: 380),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
          decoration: BoxDecoration(
            gradient: bubbleGradient,
            borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(mine ? 20 : 5),
            bottomRight: Radius.circular(mine ? 5 : 20),
          ),
            border: Border.all(
              color: mine && !pending && !failed
                  ? Colors.white.withOpacity(.22)
                  : scheme.outline.withOpacity(.45),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(
                  pending || failed ? .04 : .12,
                ),
                blurRadius: pending || failed ? 5 : 14,
                offset: const Offset(0, 5),
              ),
              if (mine && !pending && !failed)
                BoxShadow(
                  color: Colors.white.withOpacity(.14),
                  blurRadius: 1,
                  offset: const Offset(0, -1),
                ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!mine) ...[
                    _senderAvatar(message, sender),
                    const SizedBox(width: 7),
                  ],
                  Text(
                    sender,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: mine ? Colors.white : scheme.primary,
                    ),
                  ),
                ],
              ),
              if (deleted && !AppSession.isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                  decoration: BoxDecoration(color: scheme.surface.withOpacity(.75), borderRadius: BorderRadius.circular(14)),
                  child: Column(children: [
                    Icon(Icons.delete_sweep_rounded, size: 40, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 5),
                    Text('Message deleted', style: TextStyle(fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant)),
                  ]),
                ),
              if (deleted && AppSession.isAdmin)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
                  child: Text('DELETED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: scheme.onErrorContainer)),
                ),
              if (!deleted || AppSession.isAdmin) ...[
                if ('${message['attachment_url'] ?? ''}'.isNotEmpty || message['_attachment_bytes'] is Uint8List) _photoWidget(message),
              if (reply is Map)
                _quotedMessage(Map<String, dynamic>.from(reply), replyAuthor: sender),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${message['content'] ?? ''}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: mine ? FontWeight.w600 : FontWeight.w500,
                    color: mine && !pending && !failed
                        ? Colors.white
                        : scheme.onSurface,
                  ),
                ),
              ),
              if (message['edited'] == true && !deleted)
                Text('edited', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: mine ? Colors.white70 : scheme.onSurfaceVariant)),
              if (message['original_content'] != null && AppSession.isPrimaryAdmin && message['edited'] == true)
                Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(9)), child: Text('Original: ${message['original_content']}')),
              if ((message['reactions'] as Map?)?.isNotEmpty == true)
                Wrap(spacing: 4, children: (message['reactions'] as Map).entries.map((entry) => ActionChip(visualDensity: VisualDensity.compact, avatar: Text('${entry.key}'), label: Text('${entry.value}'), onPressed: () => react(message, '${entry.key}'))).toList()),
              ],
              if (!deleted && !pending && !failed)
                Wrap(
                  spacing: 3,
                  children: [
                    _chatAction(icon: Icons.reply_rounded, label: 'Reply', mine: mine, onTap: () => _replyTo(message)),
                    _chatAction(icon: Icons.add_reaction_rounded, label: 'React', mine: mine, onTap: () => showReactionPicker(message)),
                    if (message['content']?.toString().trim().isNotEmpty == true)
                      _chatAction(icon: Icons.content_copy_rounded, label: 'Copy', mine: mine, onTap: () => copyMessage(message)),
                    if (canModify)
                      _chatAction(icon: Icons.edit_rounded, label: 'Edit', mine: mine, onTap: () => editMessage(message)),
                    if (canModify)
                      _chatAction(icon: Icons.delete_outline_rounded, label: 'Delete', mine: mine, onTap: () => deleteMessage(message)),
                    if (message['attachment_url']?.toString().isNotEmpty == true || message['_attachment_bytes'] is Uint8List)
                      _chatAction(icon: Icons.download_rounded, label: 'Save', mine: mine, onTap: () => downloadPhoto(message)),
                  ],
                ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pending) ...[
                    Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Sending…',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ] else if (failed) ...[
                    Icon(
                      Icons.error_outline_rounded,
                      size: 13,
                      color: scheme.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Not sent',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: scheme.error,
                      ),
                    ),
                  ] else ...[
                    Text(
                      created,
                      style: TextStyle(
                        fontSize: 10,
                        color: mine
                            ? Colors.white.withOpacity(.78)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    if (mine) ...[
                      const SizedBox(width: 5),
                      Icon(
                        Icons.done_all_rounded,
                        size: 13,
                        color: Colors.white.withOpacity(.82),
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ),

      ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Team chat'),
        actions: [
          IconButton(
            onPressed: () => load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: BrandLoader())
          : Column(
              children: [
                if (error != null)
                  MaterialBanner(
                    content: Text(error!),
                    actions: [
                      TextButton(
                        onPressed: () => load(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                Expanded(
                  child: messages.isEmpty
                      ? const Center(
                          child: Text(
                            'No messages yet. Start the conversation.',
                          ),
                        )
                      : ListView.builder(
                          controller: scroll,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: messages.length,
                          itemBuilder: (_, index) =>
                              _messageBubble(messages[index]),
                        ),
                ),
                _composer(),
              ],
            ),
    );
  }
}
