import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'topic_detail_screen.dart';
import '../api/friendly_error.dart';
import '../blocked_users.dart';

/// 用户发布的话题
class UserTopicsScreen extends StatefulWidget {
  final String username;
  const UserTopicsScreen({super.key, required this.username});

  @override
  State<UserTopicsScreen> createState() => _UserTopicsScreenState();
}

class _UserTopicsScreenState extends State<UserTopicsScreen> {
  final _topics = <Topic>[];
  final _users = <int, UserBrief>{};
  final _scroll = ScrollController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 0;

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

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r =
          await context.read<AppState>().api.userTopics(widget.username, page: 0);
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
    setState(() => _loadingMore = true);
    try {
      final r = await context.read<AppState>()
          .api
          .userTopics(widget.username, page: _page + 1);
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
    return Scaffold(
      appBar: AppBar(title: Text('${widget.username} 的主题')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _topics.isEmpty
                  ? const EmptyView(text: '暂无主题')
                  : ListView.builder(
                      controller: _scroll,
                      itemCount: _topics.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= _topics.length) {
                          return const NekolocLoadingFooter();
                        }
                        final t = _topics[i];
                        return TopicTile(
                          topic: t,
                          users: _users,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TopicDetailScreen(topicId: t.id),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
