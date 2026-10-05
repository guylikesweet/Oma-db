import 'dart:async';

import 'package:flutter/material.dart';

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

      final nextMessages = results[0]
          .whereType<Map>()
          .map((message) => Map<String, dynamic>.from(message))
          .toList();

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
      if (!silent || messages.isEmpty) {
        setState(() {
          loading = false;
          error = '${e}';
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
    if (text.isEmpty || sending) return;

    final replyId = replyTo?['id'];
    final localId = 'local-${++_localSequence}';
    final now = DateTime.now().toIso8601String();
    final optimistic = <String, dynamic>{
      'id': localId,
      'sender_user_id': AppSession.userId,
      'sender_username': AppSession.username.isEmpty ? 'You' : AppSession.username,
      'content': text,
      'created_at': now,
      'reply_to': replyTo,
      '_status': 'sending',
    };

    setState(() {
      sending = true;
      messages = [...messages, optimistic];
      composer.clear();
      replyTo = null;
    });
    _scrollToBottom();

    try {
      final sent = await widget.api.sendChatMessage(
        text,
        replyToId: replyId is int ? replyId : int.tryParse('$replyId'),
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

  void _replyTo(Map<String, dynamic> message) {
    setState(() => replyTo = message);
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
                          '${replyTo!['content'] ?? ''}',
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
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton.filled(
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageBubble(Map<String, dynamic> message) {
    final mine = message['sender_user_id'] == AppSession.userId;
    final status = '${message['_status'] ?? 'sent'}';
    final pending = status == 'sending';
    final failed = status == 'failed';
    final reply = message['reply_to'];
    final sender = '${message['sender_username'] ?? 'User'}';
    final created = '${message['created_at'] ?? ''}'
        .replaceFirst('T', ' ')
        .split('.')
        .first;

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

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: failed ? null : () => _replyTo(message),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
          decoration: BoxDecoration(
            gradient: bubbleGradient,
            borderRadius: BorderRadius.circular(18),
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
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!mine)
                Text(
                  sender,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                ),
              if (reply is Map)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 5, bottom: 7),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: scheme.surface.withOpacity(.62),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '${reply['sender_username'] ?? 'User'}: '
                    '${reply['content'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
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
