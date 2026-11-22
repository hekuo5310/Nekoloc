import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../widgets/checkin_card.dart';
import '../models.dart';
import '../update_checker.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'bookmarks_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'user_topics_screen.dart';
import '../api/friendly_error.dart';

/// 我的（个人中心）
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with AutomaticKeepAliveClientMixin {
  UserProfile? _profile;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (!app.isLoggedIn) return;
    try {
      final p = await app.api.userProfile(app.user!.username);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _logout() async {
    final app = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await app.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    if (!app.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的')),
        body: const EmptyView(
          text: '当前处于游客模式（未登录）\n可在设置中切换站点',
          icon: Icons.person_off_outlined,
        ),
      );
    }

    final user = app.user!;
    final p = _profile;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(10),
          children: [
            Card(
              margin: const EdgeInsets.symmetric(vertical: 5),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        UserAvatar(
                          avatarTemplate: user.avatarTemplate,
                          username: user.username,
                          size: 64,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.username,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w800),
                              ),
                              if ((user.name ?? '').isNotEmpty)
                                Text(user.name!,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: scheme.onSurfaceVariant)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.verified_outlined,
                                      size: 14, color: scheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    user.admin ? '管理员' : '正式会员',
                                    style: TextStyle(
                                        fontSize: 12, color: scheme.primary),
                                  ),
                                  const SizedBox(width: 10),
                                  Icon(Icons.mark_email_unread_outlined,
                                      size: 14, color: scheme.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${user.totalUnread} 未读',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (p != null && p.bioCooked.isNotEmpty) ...[
                      const Divider(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: HtmlWidget(
                          p.bioCooked,
                          textStyle: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _stat('帖子', '${p?.postCount ?? '-'}'),
                        _stat('徽章', '${p?.badgeCount ?? '-'}'),
                        _stat('主题', '${p?.topicCount ?? '-'}'),
                        _stat('注册于', p?.createdAt != null ? fullDate(p!.createdAt) : '-'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('资料加载失败：$_error',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 6),
            const CheckinCard(),
            Card(
              margin: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: const Text('我的主题'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            UserTopicsScreen(username: user.username),
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.bookmark_border),
                    title: const Text('我的收藏'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const BookmarksScreen()),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.search),
                    title: const Text('搜索'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SearchScreen()),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.open_in_browser),
                    title: const Text('在浏览器中打开主页'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => launchUrl(
                      Uri.parse('${AppState.baseUrl}/u/${user.username}'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('设置'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: Icon(Icons.logout,
                        color: Theme.of(context).colorScheme.error),
                    title: Text('退出登录',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    onTap: _logout,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nekoloc v$kAppVersion · 第三方社区客户端',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(label,
            style: TextStyle(
                fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
