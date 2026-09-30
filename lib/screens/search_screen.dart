import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import '../search_query.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'topic_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _author = TextEditingController();
  final _tag = TextEditingController();
  SearchResult? _result;
  bool _loading = false;
  bool _loadingMore = false;
  bool _titleOnly = false;
  String _order = 'relevance';
  String _activeQuery = '';
  String? _error;
  String? _pageError;
  int _page = 1;
  int _requestId = 0;

  @override
  void dispose() {
    _requestId++;
    _ctrl.dispose(); _author.dispose(); _tag.dispose();
    super.dispose();
  }

  Future<void> _search([String? text]) async {
    final query = buildSearchQuery(text ?? _ctrl.text, titleOnly: _titleOnly,
      username: _author.text, tag: _tag.text, order: _order);
    if (query.isEmpty) return;
    final requestId = ++_requestId;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true; _loadingMore = false; _error = null;
      _pageError = null; _result = null; _page = 1; _activeQuery = query;
    });
    try {
      final r = await context.read<AppState>().api.search(query);
      if (!mounted || requestId != _requestId) return;
      setState(() => _result = r);
    } catch (e) {
      if (mounted && requestId == _requestId) setState(() => _error = e.toString());
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_loadingMore || _loading || _result?.hasMore != true) return;
    final requestId = _requestId;
    setState(() { _loadingMore = true; _pageError = null; });
    try {
      final r = await context.read<AppState>().api.search(_activeQuery, page: _page + 1);
      if (!mounted || requestId != _requestId) return;
      final existing = _result!.items;
      String key(SearchPostItem p) => p.id > 0 ? '${p.id}' : '${p.topicId}:${p.postNumber}';
      final seen = existing.map(key).toSet();
      final added = r.items.where((p) => seen.add(key(p))).toList();
      setState(() {
        _page++;
        _result = SearchResult(items: [...existing, ...added],
          hasMore: r.hasMore && added.isNotEmpty);
      });
    } catch (e) {
      if (mounted && requestId == _requestId) setState(() => _pageError = e.toString());
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: TextField(controller: _ctrl, autofocus: true,
          textInputAction: TextInputAction.search, onSubmitted: _search,
          decoration: const InputDecoration(hintText: '搜索话题、帖子…', isDense: true)),
        actions: [IconButton(icon: const Icon(Icons.search), onPressed: _search)],
      ),
      body: Column(children: [
        ExpansionTile(title: const Text('搜索筛选'), leading: const Icon(Icons.tune),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12), children: [
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilterChip(label: const Text('仅标题'), selected: _titleOnly,
              onSelected: (v) => setState(() => _titleOnly = v)),
            DropdownButton<String>(value: _order, items: const [
              DropdownMenuItem(value: 'relevance', child: Text('相关程度')),
              DropdownMenuItem(value: 'latest', child: Text('最新发布')),
              DropdownMenuItem(value: 'likes', child: Text('最多点赞')),
            ], onChanged: (v) => setState(() => _order = v ?? 'relevance')),
          ]),
          TextField(controller: _author, decoration: const InputDecoration(
            labelText: '作者用户名（可选）', prefixIcon: Icon(Icons.alternate_email))),
          TextField(controller: _tag, decoration: const InputDecoration(
            labelText: '标签（可选）', prefixIcon: Icon(Icons.tag))),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: _search, icon: const Icon(Icons.search), label: const Text('应用筛选'))),
        ]),
        Expanded(child: _loading ? const LoadingView()
          : _error != null ? ErrorView(message: _error!, onRetry: _search)
          : _result == null ? const EmptyView(text: '输入关键词开始搜索', icon: Icons.search)
          : _result!.items.isEmpty ? const EmptyView(text: '没有找到相关内容')
          : ListView.separated(
            itemCount: _result!.items.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == _result!.items.length) {
                return Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                  if (_pageError != null) Text(_pageError!, style: TextStyle(color: scheme.error)),
                  if (_result!.hasMore)
                    TextButton(onPressed: _loadingMore ? null : _more,
                      child: Text(_loadingMore ? '加载中…' : _pageError != null ? '重试加载' : '加载更多'))
                  else const Text('已显示全部结果'),
                ]));
              }
              final item = _result!.items[i];
              return ListTile(
                leading: UserAvatar(avatarTemplate: item.avatarTemplate, username: item.username, size: 34),
                title: Text(item.topicTitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text('${item.blurb}\n${item.username} · #${item.postNumber} · ${timeAgo(item.createdAt)}',
                  maxLines: 3, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                  TopicDetailScreen(topicId: item.topicId, initialPostId: item.id > 0 ? item.id : null))),
              );
            },
          )),
      ]),
    );
  }
}
