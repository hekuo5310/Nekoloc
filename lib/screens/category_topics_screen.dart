import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'topic_detail_screen.dart';
import '../api/friendly_error.dart';

/// 某分类下的话题列表（无限滚动）
class CategoryTopicsScreen extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  const CategoryTopicsScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<CategoryTopicsScreen> createState() => _CategoryTopicsScreenState();
}

class _CategoryTopicsScreenState extends State<CategoryTopicsScreen> {
  final _topics = <Topic>[];
  final _users = <int, UserBrief>{};
  final _scroll = ScrollController();
  bool _loading = true;
  bool _refreshing = false;
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
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final r =
          await context.read<AppState>().api.categoryTopics(widget.categoryId, page: 0);
      if (!mounted) return;
      setState(() {
        _topics
          ..clear()
          ..addAll(r.topics);
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
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final r = await context.read<AppState>()
          .api
          .categoryTopics(widget.categoryId, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _topics.addAll(r.topics);
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
      appBar: AppBar(title: Text(widget.categoryName)),
      body: _error != null && _topics.isEmpty
          ? ErrorView(message: _error!, onRetry: _reload)
          : _loading
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.builder(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
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
                ),
    );
  }
}
