import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'topic_detail_screen.dart';

/// 站点标签页，与分类页共用话题列表卡片。
class TagTopicsScreen extends StatefulWidget {
  final String tag;
  const TagTopicsScreen({super.key, required this.tag});

  @override
  State<TagTopicsScreen> createState() => _TagTopicsScreenState();
}

class _TagTopicsScreenState extends State<TagTopicsScreen> {
  final _topics = <Topic>[];
  final _users = <int, UserBrief>{};
  final _scroll = ScrollController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600 && !_loading &&
          !_loadingMore && _hasMore) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await context.read<AppState>().api.tagTopics(widget.tag);
      if (!mounted) return;
      setState(() {
        _topics..clear()..addAll(r.topics);
        _users..clear()..addAll(r.users);
        _page = 0;
        _hasMore = r.hasMore && r.topics.isNotEmpty;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final r = await context.read<AppState>().api.tagTopics(widget.tag, page: _page + 1);
      if (!mounted) return;
      final seen = _topics.map((topic) => topic.id).toSet();
      final added = r.topics.where((topic) => seen.add(topic.id)).toList();
      setState(() {
        _topics.addAll(added);
        _users.addAll(r.users);
        _page++;
        _hasMore = r.hasMore && added.isNotEmpty;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载更多失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('#${widget.tag}')),
    body: _loading && _topics.isEmpty
        ? const LoadingView()
        : _error != null && _topics.isEmpty
            ? ErrorView(message: _error!, onRetry: _reload)
            : RefreshIndicator(
                onRefresh: _reload,
                child: _topics.isEmpty
                    ? ListView(children: const [SizedBox(height: 120),
                        EmptyView(text: '此标签暂无话题')])
                    : ListView.builder(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _topics.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == _topics.length) {
                            return TextButton(
                              onPressed: _loadingMore ? null : _loadMore,
                              child: _loadingMore
                                  ? const NekolocLoadingFooter()
                                  : const Text('加载更多'),
                            );
                          }
                          final topic = _topics[i];
                          return TopicTile(
                            topic: topic,
                            users: _users,
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => TopicDetailScreen(topicId: topic.id),
                            )),
                          );
                        },
                      ),
              ),
  );
}
