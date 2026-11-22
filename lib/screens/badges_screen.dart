import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../account_models.dart';
import '../api/friendly_error.dart';
import '../app_state.dart';

/// 我的徽章。徽章图标若是相对路径，按站点地址补全。
class BadgesScreen extends StatefulWidget {
  const BadgesScreen({super.key});

  @override
  State<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends State<BadgesScreen> {
  List<UserBadge>? _badges;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final me = app.user?.username;
    if (me == null) {
      setState(() => _error = '请先登录');
      return;
    }
    setState(() => _error = null);
    try {
      final badges = await app.api.userBadges(me);
      if (mounted) setState(() => _badges = badges);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  String? _imageUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    return Uri.parse(AppState.baseUrl).resolve(raw).toString();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_error != null) {
      body = Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _load, child: const Text('重试')),
      ]));
    } else if (_badges == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_badges!.isEmpty) {
      body = const Center(child: Text('还没有获得徽章'));
    } else {
      final badges = _badges!;
      body = ListView.separated(
        itemCount: badges.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final b = badges[i];
          final img = _imageUrl(b.imageUrl);
          return ListTile(
            leading: img == null
                ? const CircleAvatar(child: Icon(Icons.military_tech_outlined))
                : CircleAvatar(
                    backgroundColor: Colors.transparent,
                    child: ClipOval(
                      child: CachedNetworkImage(imageUrl: img, width: 40, height: 40),
                    ),
                  ),
            title: Text(b.name),
            subtitle: (b.description == null || b.description!.isEmpty)
                ? null
                : Text(b.description!, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: b.allowTitle ? const Chip(label: Text('可作头衔')) : null,
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('我的徽章')),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}
