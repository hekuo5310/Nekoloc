import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'topic_detail_screen.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});
  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<BookmarkItem> _items = [];
  String? _error;
  String? _pageError;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  int _requestId = 0;
  final Set<int> _deleting = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (!app.isLoggedIn) return;
    final requestId = ++_requestId;
    setState(() {
      _loading = true; _loadingMore = false; _error = null; _pageError = null;
    });
    try {
      final list = await app.api.bookmarks(app.user!.username);
      if (!mounted || requestId != _requestId) return;
      setState(() { _items = list; _page = 0; _hasMore = list.isNotEmpty; });
    } catch (e) {
      if (mounted && requestId == _requestId) setState(() => _error = e.toString());
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final app = context.read<AppState>();
    if (!app.isLoggedIn) return;
    final requestId = _requestId;
    setState(() { _loadingMore = true; _pageError = null; });
    try {
      final list = await app.api.bookmarks(app.user!.username, page: _page + 1);
      if (!mounted || requestId != _requestId) return;
      final seen = _items.map((b) => b.id).toSet();
      final added = list.where((b) => seen.add(b.id)).toList();
      setState(() { _items.addAll(added); _page++; _hasMore = added.isNotEmpty; });
    } catch (e) {
      if (mounted && requestId == _requestId) setState(() => _pageError = e.toString());
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loadingMore = false);
    }
  }

  Future<void> _remove(BookmarkItem item) async {
    if (_deleting.contains(item.id)) return;
    setState(() => _deleting.add(item.id));
    try {
      await context.read<AppState>().api.removeBookmark(item.id);
      if (!mounted) return;
      // Refresh the first page: deletion changes page offsets on the server.
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('取消收藏失败：$e')));
    } finally {
      if (mounted) setState(() => _deleting.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏'), actions: [
        IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
      ]),
      body: !app.isLoggedIn ? const EmptyView(text: '登录后可查看收藏', icon: Icons.bookmark_border)
        : _loading ? const LoadingView()
        : _error != null ? ErrorView(message: _error!, onRetry: _load)
        : _items.isEmpty ? const EmptyView(text: '暂无收藏', icon: Icons.bookmark_border)
        : RefreshIndicator(onRefresh: _load, child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(), itemCount: _items.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i == _items.length) {
              return Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                if (_pageError != null) Text(_pageError!, style: TextStyle(color: scheme.error)),
                if (_hasMore) TextButton(onPressed: _loadingMore ? null : _more,
                  child: Text(_loadingMore ? '加载中…' : _pageError != null ? '重试加载' : '加载更多')),
              ]));
            }
            final b = _items[i];
            return ListTile(
              leading: Icon(Icons.bookmark, color: scheme.secondary),
              title: Text(b.title.replaceAll(RegExp(r'<[^>]*>'), ''), maxLines: 2,
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text('${b.excerpt}\n${b.postNumber != null ? '#${b.postNumber} · ' : ''}${timeAgo(b.createdAt)}', maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(tooltip: '取消收藏', onPressed: _deleting.contains(b.id) ? null : () => _remove(b),
                icon: const Icon(Icons.bookmark_remove_outlined)),
              onTap: b.topicId == null ? null : () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => TopicDetailScreen(topicId: b.topicId!, initialPostId: b.postId)));
                if (mounted) _load();
              },
            );
          },
        )),
    );
  }
}
