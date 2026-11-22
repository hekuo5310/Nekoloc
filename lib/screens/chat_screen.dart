import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/discourse_api.dart';
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
/// 发送后也会立即刷新。自己的消息可长按编辑或删除；可以发送图片附件、查看成员、离开频道。
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

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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

  Future<void> _send({List<int> uploadIds = const []}) async {
    final text = _input.text.trim();
    if ((text.isEmpty && uploadIds.isEmpty) || _sending) return;
    setState(() => _sending = true);
    try {
      await context.read<AppState>().api.sendChatMessage(
            widget.channel.id,
            text,
            uploadIds: uploadIds,
          );
      _input.clear();
      await _fetch();
    } catch (e) {
      _toast('发送失败：${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attachImage() async {
    if (_sending) return;
    final app = context.read<AppState>();
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image, allowMultiple: false);
      final file = picked.isEmpty ? null : picked.single;
      final path = file?.path;
      if (!mounted || file == null || path == null) return;
      setState(() => _sending = true);
      final resp = await app.api.uploadImage(filePath: path, filename: file.name);
      final id = int.tryParse('${resp['id']}');
      if (id == null || id <= 0) throw ApiException('上传失败，请重试');
      await _send(uploadIds: [id]);
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      _toast('图片发送失败：${friendlyError(e)}');
    }
  }

  Future<void> _editMessage(ChatMessage m) async {
    final ctl = TextEditingController(text: m.text);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(controller: ctl, maxLines: 5, minLines: 1),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (text == null || text.isEmpty || text == m.text || !mounted) return;
    try {
      await context.read<AppState>().api.editChatMessage(widget.channel.id, m.id, text);
      await _fetch();
    } catch (e) {
      _toast('编辑失败：${friendlyError(e)}');
    }
  }

  Future<void> _deleteMessage(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('删除后其他人将看不到这条消息，确定吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppState>().api.deleteChatMessage(widget.channel.id, m.id);
      await _fetch();
    } catch (e) {
      _toast('删除失败：${friendlyError(e)}');
    }
  }

  void _onLongPress(ChatMessage m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                _editMessage(m);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteMessage(m);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMembers() async {
    try {
      final members = await context.read<AppState>().api.chatMembers(widget.channel.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: members.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Text('没有成员信息'))
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final u in members)
                      ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                        title: Text('@${u.username}'),
                      ),
                  ],
                ),
        ),
      );
    } catch (e) {
      _toast('无法加载成员：${friendlyError(e)}');
    }
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('离开频道'),
        content: const Text('离开后将不再接收这个频道的消息，确定吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('离开')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppState>().api.leaveChatChannel(widget.channel.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _toast('离开失败：${friendlyError(e)}');
    }
  }

  String _absolute(String raw) => Uri.parse(AppState.baseUrl).resolve(raw).toString();

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().user?.username;
    final scheme = Theme.of(context).colorScheme;
    final title = widget.channel.title.isEmpty ? '频道 ${widget.channel.id}' : widget.channel.title;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(tooltip: '成员', icon: const Icon(Icons.group_outlined), onPressed: _showMembers),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'leave') _leave();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'leave', child: Text('离开频道')),
            ],
          ),
        ],
      ),
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
                              final bubble = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!mine && m.user != null)
                                    Text(m.user!.username,
                                        style: const TextStyle(
                                            fontSize: 11, fontWeight: FontWeight.w600)),
                                  if (m.deleted)
                                    const Text('（消息已删除）',
                                        style: TextStyle(fontStyle: FontStyle.italic))
                                  else ...[
                                    if (m.text.isNotEmpty) Text(m.text),
                                    for (final url in m.imageUrls)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: CachedNetworkImage(
                                            imageUrl: _absolute(url),
                                            width: 220,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                  ],
                                ],
                              );
                              return Align(
                                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                child: GestureDetector(
                                  onLongPress: (mine && !m.deleted) ? () => _onLongPress(m) : null,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    constraints: const BoxConstraints(maxWidth: 300),
                                    decoration: BoxDecoration(
                                      color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: bubble,
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '发送图片',
                    onPressed: _sending ? null : _attachImage,
                    icon: const Icon(Icons.image_outlined),
                  ),
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
                    onPressed: _sending ? null : () => _send(),
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
