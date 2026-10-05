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

  List<dynamic> messages = [];
  List<Map<String, dynamic>> users = [];
  Map<String, dynamic>? replyTo;
  bool loading = true;
  bool sending = false;
  String? error;
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

      final nextMessages = List<dynamic>.from(results[0] as List);
      final previousLastId =
          messages.isEmpty ? null : (messages.last as Map)['id'];

      final nextUsers = users.isEmpty
          ? List<Map<String, dynamic>>.from(
              (results[1] as List)
                  .whereType<Map>()
                  .map((x) => Map<String, dynamic>.from(x)),
            )
          : users;

      if (!mounted) return;

      setState(() {
        messages = nextMessages;
        users = nextUsers;
        loading = false;
        error = null;
      });

      final nextLastId =
          nextMessages.isEmpty ? null : (nextMessages.last as Map)['id'];

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

    setState(() => sending = true);

    try {
      await widget.api.sendChatMessage(
        text,
        replyToId: replyTo?['id'] as int?,
      );
      composer.clear();
      setState(() => replyTo = null);
      await load();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${e}')),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
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
    final reply = message['reply_to'];
    final sender = '${message['sender_username'] ?? 'User'}';
    final created = '${message['created_at'] ?? ''}'
        .replaceFirst('T', ' ')
        .split('.')
        .first;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _replyTo(message),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
          decoration: BoxDecoration(
            color: mine
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(15),
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
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              if (reply is Map)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 5, bottom: 7),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withOpacity(.65),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${reply['sender_username'] ?? 'User'}: '
                    '${reply['content'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${message['content'] ?? ''}',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                created,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                ),
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
                              _messageBubble(
                            Map<String, dynamic>.from(
                              messages[index] as Map,
                            ),
                          ),
                        ),
                ),
                _composer(),
              ],
            ),
    );
  }
}
