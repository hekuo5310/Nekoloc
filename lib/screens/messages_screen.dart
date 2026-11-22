import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'composer_screen.dart';
import 'topic_detail_screen.dart';
import '../api/friendly_error.dart';
import '../blocked_users.dart';

/// 私信会话列表
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => MessagesScreenState();
}

class MessagesScreenState extends State<MessagesScreen>
    with AutomaticKeepAliveClientMixin {
  final _topics = <Topic>[];
  final _users = <int, UserBrief>{};
  final _scroll = ScrollController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600 &&
          !_loadingMore &&
          _hasMore &&
          !_loading) {
        _loadMore();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (!app.isLoggedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await app.api.privateMessages(app.user!.username, page: 0);
      if (!mounted) return;
      setState(() {
        _topics
          ..clear()
          ..addAll(r.withoutBlocked(context.read<AppState>().blockedUsernames).topics);
        _users
          ..clear()
          ..addAll(r.users);
        _hasMore = r.hasMore;
        _page = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final app = context.read<AppState>();
    setState(() => _loadingMore = true);
    try {
      final r =
          await app.api.privateMessages(app.user!.username, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _topics.addAll(r.withoutBlocked(context.read<AppState>().blockedUsernames).topics);
        _users.addAll(r.users);
        _hasMore = r.hasMore;
        _page += 1;
      });
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
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
            tooltip: '新私信',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ComposerScreen(isPrivateMessage: true),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_pm',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ComposerScreen(isPrivateMessage: true),
          ),
        ),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('写私信'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _topics.isEmpty
                  ? const EmptyView(text: '暂无私信', icon: Icons.mail_outline)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _topics.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 66, endIndent: 12),
                        itemBuilder: (context, i) {
                          if (i >= _topics.length) {
                            return const NekolocLoadingFooter();
                          }
                          final t = _topics[i];
                          final latest = t.posters.isNotEmpty
                              ? _users[t.posters.last.userId]
                              : null;
                          return ListTile(
                            leading: UserAvatar(
                              avatarTemplate: latest?.avatarTemplate,
                              username: latest?.username ?? '?',
                              size: 42,
                            ),
                            title: Text(
                              t.title.replaceAll(RegExp(r'<[^>]*>'), ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            subtitle: t.excerpt?.isNotEmpty == true
                                ? Text(
                                    t.excerpt!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5),
                                  )
                                : null,
                            trailing: Text(
                              '${t.postsCount} 条',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: scheme.onSurfaceVariant),
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TopicDetailScreen(topicId: t.id),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
