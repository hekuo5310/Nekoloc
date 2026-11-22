import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:provider/provider.dart';

import '../api/friendly_error.dart';
import '../app_state.dart';
import '../nested_replies.dart';

/// 嵌套视图：回复按楼中楼的层级显示，可按热门、最新、最早排序。
/// 子回复较多的楼层可以展开，展开时只加载该楼的直接回复。
class NestedTopicScreen extends StatefulWidget {
  final int topicId;
  final String title;
  final String? slug;

  const NestedTopicScreen({super.key, required this.topicId, required this.title, this.slug});

  @override
  State<NestedTopicScreen> createState() => _NestedTopicScreenState();
}

class _NestedTopicScreenState extends State<NestedTopicScreen> {
  static const _sorts = {'top': '热门', 'new': '最新', 'old': '最早'};

  final List<NestedNode> _roots = [];
  String _sort = 'top';
  int _page = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final Set<int> _expanding = {};

  String get _slug => (widget.slug == null || widget.slug!.isEmpty) ? 'topic' : widget.slug!;

  @override
  void initState() {
    super.initState();
    _loadRoots(reset: true);
  }

  Future<void> _loadRoots({required bool reset}) async {
    if (_busy) return;
    final page = reset ? 0 : _page + 1;
    setState(() {
      _busy = true;
      if (reset) _loading = true;
      _error = null;
    });
    try {
      final r = await context.read<AppState>().api.nestedTopic(
            widget.topicId,
            slug: _slug,
            sort: _sort,
            page: page,
          );
      if (!mounted) return;
      setState(() {
        if (reset) _roots.clear();
        _roots.addAll(r.roots.map((m) => NestedNode.fromJson(m)));
        _page = page;
        _hasMore = r.hasMore;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _expand(NestedNode node) async {
    final id = node.post.id;
    if (_expanding.contains(id)) return;
    setState(() => _expanding.add(id));
    try {
      final r = await context.read<AppState>().api.nestedChildren(
            widget.topicId,
            node.post.postNumber,
            slug: _slug,
            sort: _sort,
          );
      if (!mounted) return;
      setState(() {
        node.children.addAll(r.children.map((m) => NestedNode.fromJson(m, depth: node.depth + 1)));
        node.moreCount = (node.moreCount - r.children.length).clamp(0, 1 << 30);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('展开失败：${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _expanding.remove(id));
    }
  }

  void _changeSort(String sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    _loadRoots(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final rows = flattenNested(_roots);
    final scheme = Theme.of(context).colorScheme;
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _roots.isEmpty) {
      body = Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: () => _loadRoots(reset: true), child: const Text('重试')),
      ]));
    } else if (rows.isEmpty) {
      body = const Center(child: Text('还没有回复'));
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
        itemCount: rows.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == rows.length) {
            return Center(
              child: TextButton(
                onPressed: _busy ? null : () => _loadRoots(reset: false),
                child: Text(_busy ? '加载中…' : '加载更多回复'),
              ),
            );
          }
          final node = rows[i];
          final post = node.post;
          return Padding(
            padding: EdgeInsets.only(left: indentFor(node.depth), bottom: 8),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('#${post.postNumber}  ',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      Expanded(
                        child: Text(post.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w600, color: scheme.primary)),
                      ),
                      Text(post.likeCount > 0 ? '赞 ${post.likeCount}' : '',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ]),
                    const SizedBox(height: 6),
                    post.hidden
                        ? Text('该帖已被社区隐藏', style: TextStyle(color: scheme.onSurfaceVariant))
                        : HtmlWidget(post.cooked, onTapUrl: (_) async => true),
                    if (node.moreCount > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _expanding.contains(post.id) ? null : () => _expand(node),
                          child: Text(_expanding.contains(post.id)
                              ? '加载中…'
                              : '展开 ${node.moreCount} 条回复'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            tooltip: '排序',
            icon: const Icon(Icons.sort),
            onSelected: _changeSort,
            itemBuilder: (_) => [
              for (final e in _sorts.entries)
                PopupMenuItem(
                  value: e.key,
                  child: Text(e.value, style: TextStyle(
                    fontWeight: e.key == _sort ? FontWeight.w700 : FontWeight.normal,
                  )),
                ),
            ],
          ),
        ],
      ),
      body: body,
    );
  }
}
