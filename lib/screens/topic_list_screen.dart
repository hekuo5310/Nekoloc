import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'composer_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'topic_detail_screen.dart';
import '../api/friendly_error.dart';

/// 首页：话题流（最新 / 热门 / 新帖 / 未读）
class TopicListScreen extends StatefulWidget {
  const TopicListScreen({super.key});

  @override
  State<TopicListScreen> createState() => _TopicListScreenState();
}

class _TopicListScreenState extends State<TopicListScreen>
    with AutomaticKeepAliveClientMixin {
  static const _filters = [
    ('latest', '最新'),
    ('top', '热门'),
    ('new', '新帖'),
    ('unread', '未读'),
  ];

  String _filter = 'latest';
  final _topics = <Topic>[];
  final _users = <int, UserBrief>{};
  Map<int, Category>? _categories;
  final _scroll = ScrollController();

  bool _loading = true;
  bool _refreshing = false;
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
      if (_scroll.position.extentAfter < 600 && !_loadingMore && _hasMore && !_loading) {
        _loadMore();
      }
    });
    _reload();
    _loadCategories();
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
      final result = await context.read<AppState>().api.topicList(_filter, page: 0);
      if (!mounted) return;
      setState(() {
        _topics
          ..clear()
          ..addAll(result.topics);
        _users
          ..clear()
          ..addAll(result.users);
        _hasMore = result.hasMore;
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

  Future<void> _loadCategories() async {
    try {
      final cats = await context.read<AppState>().api.categories();
      final map = <int, Category>{};
      for (final c in cats) {
        map[c.id] = c;
      }
      if (mounted) setState(() => _categories = map);
    } catch (_) {}
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result =
          await context.read<AppState>().api.topicList(_filter, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _topics.addAll(result.topics);
        _users.addAll(result.users);
        _hasMore = result.hasMore;
        _page += 1;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.asset('assets/icon/app_icon.png', width: 26, height: 26),
            ),
            const SizedBox(width: 9),
            Text(app.siteInfo?.title ?? 'NodeLoc'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          if (app.isLoggedIn)
            IconButton(
              tooltip: '发帖',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ComposerScreen(isNewTopic: true),
                ),
              ),
            ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (final (value, label) in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: _filter == value,
                      label: Text(label),
                      showCheckmark: false,
                      selectedColor: scheme.primary.withOpacity(0.25),
                      onSelected: (_) {
                        if (_filter == value) return;
                        setState(() {
                          _filter = value;
                          _loading = true;
                        });
                        _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: _error != null && _topics.isEmpty
          ? ErrorView(
              message: '$_error${_filter == 'unread' || _filter == 'new' ? '\n（该列表可能需要登录后查看）' : ''}',
              onRetry: _reload)
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
                        categories: _categories,
                        onTap: () => _openTopic(t.id),
                      );
                    },
                  ),
                ),
    );
  }

  void _openTopic(int id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TopicDetailScreen(topicId: id),
      ),
    );
  }
}
