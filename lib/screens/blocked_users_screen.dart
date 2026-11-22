import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/friendly_error.dart';
import '../app_state.dart';

/// 屏蔽用户管理：列出当前账号忽略的用户，可逐个取消。
///
/// 名单以站点为准（自己资料里的 ignored_usernames）；取消操作先更新全局名单，
/// 请求失败时回滚，保证信息流与这里的显示一致。
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<String>? _names;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final me = app.user?.username;
    if (me == null) {
      setState(() => _names = const []);
      return;
    }
    setState(() => _error = null);
    try {
      final profile = await app.api.userProfile(me);
      if (!mounted) return;
      setState(() => _names = [...profile.ignoredUsernames]);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _unblock(String name) async {
    final app = context.read<AppState>();
    setState(() => _busy.add(name));
    app.setBlocked(name, false);
    try {
      await app.api.setUserIgnored(name, false);
      if (!mounted) return;
      setState(() => _names?.remove(name));
    } catch (e) {
      app.setBlocked(name, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('取消屏蔽失败：${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(name));
    }
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final names = _names;
    if (names == null) return const Center(child: CircularProgressIndicator());
    if (names.isEmpty) {
      return const Center(child: Text('还没有屏蔽任何用户'));
    }
    return ListView.separated(
      itemCount: names.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final name = names[i];
        final busy = _busy.contains(name);
        return ListTile(
          leading: CircleAvatar(
            child: Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase()),
          ),
          title: Text('@$name'),
          trailing: TextButton(
            onPressed: busy ? null : () => _unblock(name),
            child: const Text('取消屏蔽'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('屏蔽用户')),
      body: _body(),
    );
  }
}
