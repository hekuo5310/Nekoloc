import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/friendly_error.dart';
import '../app_state.dart';
import '../models.dart';
import '../node_slug.dart';

/// 创建节点。别名未被手动修改时，随名称自动生成；提交前检查别名是否可用。
class CreateNodeScreen extends StatefulWidget {
  /// 可选的父节点（只能是顶层节点）。
  final List<Category> parents;

  const CreateNodeScreen({super.key, required this.parents});

  @override
  State<CreateNodeScreen> createState() => _CreateNodeScreenState();
}

class _CreateNodeScreenState extends State<CreateNodeScreen> {
  final _name = TextEditingController();
  final _slug = TextEditingController();
  final _desc = TextEditingController();
  int? _parentId;
  bool _slugTouched = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    // 只有别名仍然跟随名称时才更新它，用户手改过的别名保持不变。
    if (!_slugTouched) _slug.text = slugifyNodeName(value);
    setState(() {});
  }

  Future<void> _submit() async {
    final api = context.read<AppState>().api;
    final name = _name.text.trim();
    final slug = _slug.text.trim();
    if (name.isEmpty) return setState(() => _error = '请填写节点名称');
    if (slug.isEmpty) return setState(() => _error = '请填写节点别名');
    if (_parentId == null) return setState(() => _error = '请选择所属的上级节点');

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final check = await api.checkNodeSlug(slug);
      if (!check.available) {
        setState(() {
          _busy = false;
          _error = check.message ?? '该别名已被使用，请换一个';
        });
        return;
      }
      await api.createNode(
        name: name,
        slug: slug,
        description: _desc.text.trim(),
        parentCategoryId: _parentId!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('节点已创建')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建节点'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('创建'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<int>(
            value: _parentId,
            decoration: const InputDecoration(labelText: '上级节点'),
            items: [
              for (final p in widget.parents)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => setState(() => _parentId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: 50,
            onChanged: _onNameChanged,
            decoration: const InputDecoration(labelText: '节点名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _slug,
            onChanged: (_) {
              _slugTouched = true;
              setState(() {});
            },
            decoration: const InputDecoration(
              labelText: '别名（网址中使用）',
              helperText: '仅含字母、数字与连字符；名称改动时会自动生成',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '节点介绍（可选）'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
