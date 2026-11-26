import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/friendly_error.dart';
import '../app_state.dart';
import '../chat_models.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// 私信列表。新版站点的私信就是聊天里的一对一对话（以及多人群聊），
/// 不再是话题；公开频道在右上角的“聊天”里。
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => MessagesScreenState();
}

class MessagesScreenState extends State<MessagesScreen> with AutomaticKeepAliveClientMixin {
  List<ChatChannel> _chats = const [];
  bool _loading = true;
  String? _error;
  void Function()? _busCancel;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    // 任何聊天变化都会改变会话列表（新消息、未读数）。
    _busCancel = context.read<AppState>().bus.subscribe('/chat/list', () => _load(quiet: true));
  }

  @override
  void dispose() {
    _busCancel?.call();
    super.dispose();
  }

  Future<void> reload() => _load();

  Future<void> _load({bool quiet = false}) async {
    final app = context.read<AppState>();
    if (!app.isLoggedIn) return;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final all = await app.api.chatChannels();
      if (!mounted) return;
      final blocked = app.blockedUsernames;
      setState(() {
        _chats = all
            .where((c) => c.isDirect)
            .where((c) => c.directUsername == null || !blocked.contains(c.directUsername))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted || quiet) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  /// 输入用户名，打开与他的对话（还没聊过也可以）。
  Future<void> _newMessage() async {
    final ctl = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新私信'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '对方的用户名', prefixText: '@'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('开始聊天')),
        ],
      ),
    );
    final name = username?.replaceFirst('@', '').trim();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final channel = await context.read<AppState>().api.openDirectChat(name);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatConversationScreen(channel: channel)),
      );
      _load(quiet: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法打开对话：${friendlyError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    if (!app.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('私信')),
        body: const EmptyView(text: '登录后可查看私信', icon: Icons.mail_outline),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('私信'),
        actions: [
          IconButton(
            tooltip: '聊天频道',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatChannelsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_pm',
        onPressed: _newMessage,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('写私信'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _chats.isEmpty
                  ? const EmptyView(text: '暂无私信', icon: Icons.mail_outline)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _chats.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 66, endIndent: 12),
                        itemBuilder: (context, i) {
                          final c = _chats[i];
                          return ListTile(
                            leading: c.isGroup
                                ? const CircleAvatar(child: Icon(Icons.group_outlined))
                                : UserAvatar(avatarTemplate: null, username: c.directUsername ?? c.title, size: 42),
                            title: Text(
                              c.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: c.unreadCount > 0 ? FontWeight.w700 : FontWeight.w600,
                              ),
                            ),
                            subtitle: (c.lastExcerpt ?? '').isNotEmpty
                                ? Text(c.lastExcerpt!,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))
                                : null,
                            trailing: c.unreadCount > 0
                                ? CircleAvatar(
                                    radius: 10,
                                    backgroundColor: scheme.primary,
                                    child: Text('${c.unreadCount}',
                                        style: TextStyle(fontSize: 11, color: scheme.onPrimary)),
                                  )
                                : (c.muted ? Icon(Icons.notifications_off_outlined, size: 16, color: scheme.onSurfaceVariant) : null),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => ChatConversationScreen(channel: c)),
                              );
                              _load(quiet: true);
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}
