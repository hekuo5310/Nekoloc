import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'topic_detail_screen.dart';
import '../api/friendly_error.dart';

/// 通知中心
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => NotificationsScreenState();
}

class NotificationsScreenState extends State<NotificationsScreen>
    with AutomaticKeepAliveClientMixin {
  List<NotificationItem>? _items;
  String? _error;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<AppState>().api.notifications();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    try {
      await context.read<AppState>().api.markAllNotificationsRead();
      await _load();
      if (mounted) {
        context.read<AppState>().refreshUser();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _onTap(NotificationItem n) async {
    if (!n.read) {
      try {
        await context.read<AppState>().api.markNotificationRead(n.id);
        if (mounted) {
          context.read<AppState>().refreshUser();
        }
      } catch (_) {}
    }
    if (!mounted) return;
    if (n.topicId != null) {
      final ok = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TopicDetailScreen(topicId: n.topicId!,
            initialPostNumber: n.postNumber != null && n.postNumber! > 0 ? n.postNumber : null),
        ),
      );
      if (ok == null && mounted) _load();
    }
  }

  // 类型编号与 v1_mapping.dart 中的映射一致（沿用 Discourse 的编号）。
  IconData _iconFor(int type) {
    return switch (type) {
      1 => Icons.alternate_email, // 提及
      2 => Icons.reply, // 回复
      5 || 19 => Icons.thumb_up_alt_outlined, // 赞同
      9 => Icons.forum_outlined, // 关注的话题有新回帖
      11 => Icons.repeat, // 转发
      30 => Icons.mail_outline, // 私信
      36 => Icons.hub_outlined, // 节点新帖
      800 => Icons.person_add_alt_1, // 新关注者
      801 => Icons.article_outlined, // 关注的人发了新主题
      _ => Icons.notifications_none, // 系统通知
    };
  }

  String _verbFor(int type) {
    return switch (type) {
      1 => '提及了你',
      2 => '回复了你',
      5 => '赞同了你的帖子',
      19 => '等人赞同了你的帖子',
      9 => '回复了你关注的话题',
      11 => '转发了你的帖子',
      30 => '给你发来私信',
      36 => '在你加入的节点发了新帖',
      800 => '关注了你',
      801 => '发布了新话题',
      _ => '向你发来了通知',
    };
  }

  /// 系统通知没有发起人，标题就是通知本身。
  String _titleFor(NotificationItem n) {
    if (n.type == 0 || n.displayUsername.isEmpty) {
      return n.topicTitle.isEmpty ? '系统通知' : n.topicTitle.replaceAll(RegExp(r'<[^>]*>'), '');
    }
    return '${n.displayUsername} ${_verbFor(n.type)}';
  }

  String _subtitleFor(NotificationItem n) =>
      n.type == 0 || n.displayUsername.isEmpty ? '' : n.topicTitle.replaceAll(RegExp(r'<[^>]*>'), '');


  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    if (!app.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('通知')),
        body: const EmptyView(
            text: '登录后可查看通知', icon: Icons.notifications_off_outlined),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          if (_items != null && _items!.any((n) => !n.read))
            TextButton(
              onPressed: _markAllRead,
              child: const Text('全部已读', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _items == null || _items!.isEmpty
                  ? const EmptyView(text: '暂无通知')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _items!.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 62, endIndent: 12),
                        itemBuilder: (context, i) {
                          final n = _items![i];
                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: n.read
                                    ? scheme.surfaceContainerHighest
                                        .withOpacity(0.6)
                                    : scheme.primary.withOpacity(0.16),
                              ),
                              child: Icon(
                                _iconFor(n.type),
                                size: 19,
                                color: n.read
                                    ? scheme.onSurfaceVariant
                                    : scheme.primary,
                              ),
                            ),
                            title: Text(
                              _titleFor(n),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight:
                                    n.read ? FontWeight.w500 : FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              _subtitleFor(n),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          trailing: Text(
                            timeAgo(n.createdAt),
                            style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant),
                          ),
                            onTap: () => _onTap(n),
                          );
                        },
                      ),
                    ),
    );
  }
}

