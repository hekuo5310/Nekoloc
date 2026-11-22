import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/friendly_error.dart';
import '../app_state.dart';
import '../chat_models.dart';

/// 聊天频道列表：公开频道与私聊分开显示。
class ChatChannelsScreen extends StatefulWidget {
  const ChatChannelsScreen({super.key});

  @override
  State<ChatChannelsScreen> createState() => _ChatChannelsScreenState();
}

class _ChatChannelsScreenState extends State<ChatChannelsScreen> {
  List<ChatChannel>? _channels;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await context.read<AppState>().api.chatChannels();
      if (mounted) setState(() => _channels = list);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_error != null) {
      body = Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _load, child: const Text('重试')),
      ]));
    } else if (_channels == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_channels!.isEmpty) {
      body = const Center(child: Text('暂时没有可以加入的聊天频道'));
    } else {
      final channels = _channels!;
      body = ListView.separated(
        itemCount: channels.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final c = channels[i];
          return ListTile(
            leading: CircleAvatar(
              child: Icon(c.isDirect ? Icons.person_outline : Icons.forum_outlined),
            ),
            title: Text(c.title.isEmpty ? '频道 ${c.id}' : c.title),
            subtitle: c.lastExcerpt == null
                ? null
                : Text(c.lastExcerpt!, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatConversationScreen(channel: c),
              ),
            ),
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('聊天')),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}

/// 单个频道的会话。收到 MessageBus 的频道事件时立即刷新；未连接时每 20 秒拉取一次兜底。
/// 发送后也会立即刷新。
class ChatConversationScreen extends StatefulWidget {
  final ChatChannel channel;

  const ChatConversationScreen({super.key, required this.channel});

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  // 实时推送可用时以推送为准；定时拉取只作为兜底，间隔放宽到 20 秒。
  static const _pollInterval = Duration(seconds: 20);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  void Function()? _busCancel;
  List<ChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  bool _fetching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch(initial: true);
    _timer = Timer.periodic(_pollInterval, (_) => _fetch());
    _busCancel = context.read<AppState>().bus.subscribe(
          '/chat/${widget.channel.id}',
          () => _fetch(),
        );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _busCancel?.call();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool initial = false}) async {
    // 上一次还没返回就跳过，避免慢网络下请求堆积。
    if (_fetching) return;
    _fetching = true;
    try {
      final list = await context.read<AppState>().api.chatMessages(widget.channel.id);
      if (!mounted) return;
      setState(() {
        _messages = mergeChatMessages(_messages, list);
        _error = null;
      });
    } catch (e) {
      if (mounted && (initial || _messages.isEmpty)) {
        setState(() => _error = friendlyError(e));
      }
    } finally {
      _fetching = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await context.read<AppState>().api.sendChatMessage(widget.channel.id, text);
      _input.clear();
      await _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败：${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().user?.username;
    final title = widget.channel.title.isEmpty ? '频道 ${widget.channel.id}' : widget.channel.title;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _messages.isEmpty
                    ? Center(child: Text(_error!))
                    : _messages.isEmpty
                        ? const Center(child: Text('还没有消息'))
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.all(12),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) {
                              final m = _messages[i];
                              final mine = m.user?.username == me;
                              return Align(
                                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  constraints: const BoxConstraints(maxWidth: 300),
                                  decoration: BoxDecoration(
                                    color: mine
                                        ? Theme.of(context).colorScheme.primaryContainer
                                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!mine && m.user != null)
                                        Text(m.user!.username,
                                            style: const TextStyle(
                                                fontSize: 11, fontWeight: FontWeight.w600)),
                                      Text(m.deleted ? '（消息已删除）' : m.text),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: '发送消息…', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
