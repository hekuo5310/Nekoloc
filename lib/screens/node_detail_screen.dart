import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/friendly_error.dart';
import '../app_state.dart';
import '../models.dart';
import 'category_topics_screen.dart';

/// 节点详情：介绍、成员数、加入或退出，以及子节点。话题列表在 [CategoryTopicsScreen] 中查看。
class NodeDetailScreen extends StatefulWidget {
  final Category node;

  const NodeDetailScreen({super.key, required this.node});

  @override
  State<NodeDetailScreen> createState() => _NodeDetailScreenState();
}

class _NodeDetailScreenState extends State<NodeDetailScreen> {
  late Category _node = widget.node;
  List<Category> _children = const [];
  bool _childrenHasMore = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren({int page = 0}) async {
    try {
      final r = await context.read<AppState>().api.nodeBrowse(_node.id, page: page);
      if (!mounted) return;
      setState(() {
        _children = page == 0 ? r.nodes : [..._children, ...r.nodes];
        _childrenHasMore = r.hasMore;
      });
    } catch (_) {
      // 子节点加载失败不影响主要内容。
    }
  }

  Future<void> _toggleJoin() async {
    if (_busy) return;
    final app = context.read<AppState>();
    if (!app.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    final target = !_node.isJoined;
    setState(() => _busy = true);
    try {
      final joined = await app.api.setNodeJoined(_node.id, target);
      if (!mounted) return;
      setState(() => _node = _copy(joined: joined));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败：${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Category _copy({required bool joined}) => Category(
        id: _node.id,
        name: _node.name,
        color: _node.color,
        textColor: _node.textColor,
        slug: _node.slug,
        topicCount: _node.topicCount,
        descriptionExcerpt: _node.descriptionExcerpt,
        parentId: _node.parentId,
        position: _node.position,
        readRestricted: _node.readRestricted,
        memberCount: _node.memberCount + (joined == _node.isJoined ? 0 : (joined ? 1 : -1)),
        isJoined: joined,
        description: _node.description,
      );

  @override
  Widget build(BuildContext context) {
    final n = _node;
    final desc = (n.description?.isNotEmpty == true) ? n.description! : n.descriptionExcerpt;
    return Scaffold(
      appBar: AppBar(title: Text(n.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(n.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text('${n.topicCount} 话题 · ${n.memberCount} 成员',
              style: const TextStyle(fontSize: 12)),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(desc),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: n.isJoined
                  ? OutlinedButton(
                      onPressed: _busy ? null : _toggleJoin,
                      child: const Text('退出节点'),
                    )
                  : FilledButton(
                      onPressed: _busy ? null : _toggleJoin,
                      child: const Text('加入节点'),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryTopicsScreen(
                      categoryId: n.id,
                      categoryName: n.name,
                    ),
                  ),
                ),
                child: const Text('查看话题'),
              ),
            ),
          ]),
          if (_children.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('子节点', style: Theme.of(context).textTheme.titleSmall),
            for (final c in _children)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(c.name),
                subtitle: Text('${c.topicCount} 话题', style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => NodeDetailScreen(node: c)),
                ),
              ),
            if (_childrenHasMore)
              OutlinedButton(
                onPressed: () => _loadChildren(page: (_children.length ~/ 30)),
                child: const Text('加载更多子节点'),
              ),
          ],
        ],
      ),
    );
  }
}
