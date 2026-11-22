import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/friendly_error.dart';
import '../app_state.dart';
import '../user_preferences.dart';

enum PreferenceKind { notifications, email, privacy }

/// 账号偏好页：通知、邮件、隐私三组设置共用一个页面。
/// 修改时先更新界面，写入失败则回滚并提示。
class PreferenceScreen extends StatefulWidget {
  final PreferenceKind kind;

  const PreferenceScreen({super.key, required this.kind});

  @override
  State<PreferenceScreen> createState() => _PreferenceScreenState();
}

class _PreferenceScreenState extends State<PreferenceScreen> {
  UserPreferences? _prefs;
  String? _error;

  String get _title => switch (widget.kind) {
        PreferenceKind.notifications => '通知偏好',
        PreferenceKind.email => '邮件通知',
        PreferenceKind.privacy => '隐私',
      };

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
    try {
      final option = await app.api.ownUserOption(me);
      if (mounted) setState(() => _prefs = UserPreferences.fromOption(option));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  /// 乐观更新：先应用到界面，写入失败回滚。
  Future<void> _save(
    Map<String, dynamic> wire,
    UserPreferences Function(UserPreferences) next,
  ) async {
    final app = context.read<AppState>();
    final me = app.user?.username;
    final before = _prefs;
    if (me == null || before == null) return;
    setState(() => _prefs = next(before));
    try {
      await app.api.updateUserOptions(me, wire);
    } catch (e) {
      if (mounted) {
        setState(() => _prefs = before);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：${friendlyError(e)}')),
        );
      }
    }
  }

  Widget _picker<T extends Enum>({
    required String title,
    required List<T> values,
    required T current,
    required String Function(T) labelOf,
    required void Function(T) onPick,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(labelOf(current)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await showModalBottomSheet<T>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final v in values)
                  ListTile(
                    title: Text(labelOf(v)),
                    trailing: v == current ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(ctx, v),
                  ),
              ],
            ),
          ),
        );
        if (picked != null && picked != current) onPick(picked);
      },
    );
  }

  Widget _toggle({
    required String title,
    required bool value,
    required void Function(bool) onChanged,
  }) =>
      SwitchListTile(title: Text(title), value: value, onChanged: onChanged);

  List<Widget> _rows(UserPreferences p) => switch (widget.kind) {
        PreferenceKind.notifications => [
            _picker<LikeNotificationFrequency>(
              title: '点赞通知频率',
              values: LikeNotificationFrequency.values,
              current: p.likeFrequency,
              labelOf: (v) => v.label,
              onPick: (v) => _save({'like_notification_frequency': v.value},
                  (x) => _copy(x, likeFrequency: v)),
            ),
            _picker<NewTopicDuration>(
              title: '新话题的判断范围',
              values: NewTopicDuration.values,
              current: p.newTopicDuration,
              labelOf: (v) => v.label,
              onPick: (v) => _save({'new_topic_duration_minutes': v.minutes},
                  (x) => _copy(x, newTopicDuration: v)),
            ),
            _toggle(
              title: '回复话题时自动关注',
              value: p.trackOnReply,
              onChanged: (v) => _save({'notification_level_when_replying': v ? 2 : 1},
                  (x) => _copy(x, trackOnReply: v)),
            ),
          ],
        PreferenceKind.email => [
            _picker<EmailLevel>(
              title: '回复的邮件通知',
              values: EmailLevel.values,
              current: p.emailLevel,
              labelOf: (v) => v.label,
              onPick: (v) => _save({'email_level': v.value}, (x) => _copy(x, emailLevel: v)),
            ),
            _picker<EmailLevel>(
              title: '私信的邮件通知',
              values: EmailLevel.values,
              current: p.emailMessagesLevel,
              labelOf: (v) => v.label,
              onPick: (v) => _save({'email_messages_level': v.value},
                  (x) => _copy(x, emailMessagesLevel: v)),
            ),
            _picker<PreviousRepliesLevel>(
              title: '之前参与过的话题的回复',
              values: PreviousRepliesLevel.values,
              current: p.emailPreviousReplies,
              labelOf: (v) => v.label,
              onPick: (v) => _save({'email_previous_replies': v.value},
                  (x) => _copy(x, emailPreviousReplies: v)),
            ),
            _toggle(
              title: '邮件摘要',
              value: p.emailDigests,
              onChanged: (v) => _save({'email_digests': v}, (x) => _copy(x, emailDigests: v)),
            ),
          ],
        PreferenceKind.privacy => [
            _toggle(
              title: '隐藏个人资料',
              value: p.hideProfile,
              onChanged: (v) => _save({'hide_profile': v}, (x) => _copy(x, hideProfile: v)),
            ),
            _toggle(
              title: '隐藏在线状态',
              value: p.hidePresence,
              onChanged: (v) => _save({'hide_presence': v}, (x) => _copy(x, hidePresence: v)),
            ),
          ],
      };

  UserPreferences _copy(
    UserPreferences x, {
    LikeNotificationFrequency? likeFrequency,
    NewTopicDuration? newTopicDuration,
    bool? trackOnReply,
    EmailLevel? emailLevel,
    EmailLevel? emailMessagesLevel,
    PreviousRepliesLevel? emailPreviousReplies,
    bool? emailDigests,
    bool? hideProfile,
    bool? hidePresence,
  }) =>
      UserPreferences(
        likeFrequency: likeFrequency ?? x.likeFrequency,
        newTopicDuration: newTopicDuration ?? x.newTopicDuration,
        trackOnReply: trackOnReply ?? x.trackOnReply,
        emailLevel: emailLevel ?? x.emailLevel,
        emailMessagesLevel: emailMessagesLevel ?? x.emailMessagesLevel,
        emailPreviousReplies: emailPreviousReplies ?? x.emailPreviousReplies,
        emailDigests: emailDigests ?? x.emailDigests,
        hideProfile: hideProfile ?? x.hideProfile,
        hidePresence: hidePresence ?? x.hidePresence,
      );

  @override
  Widget build(BuildContext context) {
    final p = _prefs;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _error != null
          ? Center(child: Text(_error!))
          : p == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(children: [
                  for (final w in _rows(p)) ...[w, const Divider(height: 1)],
                ]),
    );
  }
}
