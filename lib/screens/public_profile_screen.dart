import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'composer_screen.dart';
import 'user_topics_screen.dart';

/// 公开用户资料，关注与忽略状态均以站点账号为准。
class PublicProfileScreen extends StatefulWidget {
  final String username;
  const PublicProfileScreen({super.key, required this.username});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  UserProfile? _profile;
  bool _ignored = false;
  bool _canIgnore = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final app = context.read<AppState>();
      final p = await app.api.userProfile(widget.username);
      UserProfile? own;
      if (app.isLoggedIn && app.user!.username != widget.username) {
        try {
          own = await app.api.userProfile(app.user!.username);
        } catch (_) {
          // The public profile remains readable if private settings fail.
        }
      }
      if (!mounted) return;
      setState(() {
        _profile = p;
        _ignored = own?.ignoredUsernames.contains(widget.username) ?? false;
        _canIgnore = own?.canIgnoreUsers ?? false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _toggleFollow() async {
    final p = _profile;
    if (p == null || _busy) return;
    setState(() => _busy = true);
    try {
      final api = context.read<AppState>().api;
      if (p.isFollowed) {
        await api.unfollowUser(widget.username);
      } else {
        await api.followUser(widget.username);
      }
      await _load();
    } catch (e) {
      _hint('关注操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleIgnore() async {
    if (_busy) return;
    if (!_ignored) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('忽略用户'),
          content: Text('忽略 @${widget.username} 后，站点会屏蔽此用户的帖子及消息，直到你取消忽略。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('忽略')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.setUserIgnored(widget.username, !_ignored);
      if (!mounted) return;
      setState(() => _ignored = !_ignored);
      _hint(_ignored ? '已忽略用户' : '已取消忽略');
    } catch (e) {
      _hint('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _hint(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = _profile;
    final isOther = app.user?.username != widget.username;
    return Scaffold(
      appBar: AppBar(title: Text('@${widget.username}')),
      body: p == null
          ? _error == null ? const LoadingView()
              : ErrorView(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Row(children: [
                    UserAvatar(avatarTemplate: p.avatarTemplate,
                        username: p.username, size: 64),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name?.isNotEmpty == true ? p.name! : p.username,
                            style: Theme.of(context).textTheme.titleLarge),
                        Text('@${p.username}'),
                      ],
                    )),
                  ]),
                  const SizedBox(height: 12),
                  Text('${p.postCount} 帖 · ${p.badgeCount} 徽章'
                      '${p.totalFollowers == null ? '' : ' · ${p.totalFollowers} 关注者'}'),
                  if (p.bioCooked.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    HtmlWidget(p.bioCooked),
                  ],
                  const SizedBox(height: 16),
                  if (app.isLoggedIn && isOther) ...[
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (p.canFollow || p.isFollowed)
                        FilledButton.icon(
                          onPressed: _busy ? null : _toggleFollow,
                          icon: Icon(p.isFollowed ? Icons.person_remove_outlined : Icons.person_add_alt_1),
                          label: Text(p.isFollowed ? '取消关注' : '关注'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ComposerScreen(
                            isPrivateMessage: true, initialRecipients: widget.username,
                          ),
                        )),
                        icon: const Icon(Icons.mail_outline),
                        label: const Text('发私信'),
                      ),
                      if (_canIgnore || _ignored)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _toggleIgnore,
                          icon: Icon(_ignored ? Icons.visibility_outlined : Icons.block_outlined),
                          label: Text(_ignored ? '取消忽略' : '忽略用户'),
                        ),
                    ]),
                    const SizedBox(height: 12),
                  ],
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: const Text('发布的话题'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => UserTopicsScreen(username: widget.username),
                    )),
                  ),
                ],
              ),
            ),
    );
  }
}
