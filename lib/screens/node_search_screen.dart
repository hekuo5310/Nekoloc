import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/friendly_error.dart';
import '../app_state.dart';
import '../models.dart';
import 'node_detail_screen.dart';

/// 搜索节点名称。
class NodeSearchScreen extends StatefulWidget {
  const NodeSearchScreen({super.key});

  @override
  State<NodeSearchScreen> createState() => _NodeSearchScreenState();
}

class _NodeSearchScreenState extends State<NodeSearchScreen> {
  final _ctl = TextEditingController();
  List<Category>? _results;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final term = _ctl.text.trim();
    if (term.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await context.read<AppState>().api.searchNodes(term);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: const InputDecoration(hintText: '搜索节点', border: InputBorder.none),
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: _busy ? null : _search,
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : _busy
              ? const Center(child: CircularProgressIndicator())
              : results == null
                  ? const Center(child: Text('输入节点名称进行搜索'))
                  : results.isEmpty
                      ? const Center(child: Text('没有找到相关节点'))
                      : ListView.separated(
                          itemCount: results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final n = results[i];
                            return ListTile(
                              title: Text(n.name),
                              subtitle: n.descriptionExcerpt.isEmpty
                                  ? null
                                  : Text(n.descriptionExcerpt,
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => NodeDetailScreen(node: n)),
                              ),
                            );
                          },
                        ),
    );
  }
}
