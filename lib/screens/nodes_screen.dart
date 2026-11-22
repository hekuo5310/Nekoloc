import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/friendly_error.dart';
import '../app_state.dart';
import '../models.dart';
import 'category_topics_screen.dart';
import 'create_node_screen.dart';

/// 节点目录（NodeLoc 的社区节点，即 nodes.json 中的分类）。
class NodesScreen extends StatefulWidget {
  const NodesScreen({super.key});

  @override
  State<NodesScreen> createState() => _NodesScreenState();
}

class _NodesScreenState extends State<NodesScreen> {
  List<Category>? _nodes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _create() async {
    final parents = (_nodes ?? const <Category>[]).where((c) => c.parentId == null).toList();
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CreateNodeScreen(parents: parents)),
    );
    if (created == true) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final nodes = await context.read<AppState>().api.nodes();
      if (mounted) setState(() => _nodes = nodes);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    } else if (_nodes == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_nodes!.isEmpty) {
      body = const Center(child: Text('暂时没有节点'));
    } else {
      final nodes = _nodes!;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          itemCount: nodes.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final node = nodes[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: node.color,
                child: Text(node.name.isEmpty ? '?' : node.name.substring(0, 1)),
              ),
              title: Text(node.name),
              subtitle: node.descriptionExcerpt.isEmpty
                  ? null
                  : Text(node.descriptionExcerpt,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text('${node.topicCount}'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CategoryTopicsScreen(
                    categoryId: node.id,
                    categoryName: node.name,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('节点'), actions: [
        IconButton(
          tooltip: '创建节点',
          icon: const Icon(Icons.add),
          onPressed: _create,
        ),
      ]),
      body: body,
    );
  }
}
