import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'topic_detail_screen.dart';

/// 搜索页
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  SearchResult? _result;
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  @override
  void dispose() {
    _requestId++;
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await context.read<AppState>().api.search(q.trim());
      if (!mounted || requestId != _requestId) return;
      setState(() => _result = r);
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: const InputDecoration(
            hintText: '搜索话题、帖子…',
            isDense: true,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _search(_ctrl.text),
          ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: () => _search(_ctrl.text))
              : _result == null
                  ? const EmptyView(text: '输入关键词开始搜索', icon: Icons.search)
                  : _result!.items.isEmpty
                      ? const EmptyView(text: '没有找到相关内容')
                      : ListView.separated(
                          itemCount: _result!.items.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 58, endIndent: 12),
                          itemBuilder: (context, i) {
                            final item = _result!.items[i];
                            return ListTile(
                              leading: UserAvatar(
                                avatarTemplate: item.avatarTemplate,
                                username: item.username,
                                size: 34,
                              ),
                              title: Text(
                                item.topicTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                item.blurb,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              trailing: Text(
                                '${item.username} · ${timeAgo(item.createdAt)}',
                                style: TextStyle(
                                    fontSize: 11, color: scheme.onSurfaceVariant),
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      TopicDetailScreen(topicId: item.topicId),
                                ),
                              ),
                            );
                          },
                        ),
    );
  }
}
