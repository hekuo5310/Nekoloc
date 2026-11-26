import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/friendly_error.dart';
import '../app_state.dart';

enum PreferenceKind { notifications, email, privacy }

/// 通知类别（`settings.notify` 的键）及显示名，顺序与站点设置页一致。
const notifyRows = <(String, String)>[
  ('reply', '有人回复我的帖子'),
  ('reply_comment', '有人回复我的评论'),
  ('mention', '有人 @ 我'),
  ('vote', '我的内容被赞同'),
  ('repost', '我的帖子被转发'),
  ('follow', '新的关注者'),
  ('message', '新的私信'),
  ('watching', '我关注的主题有新回帖'),
  ('followed_topic', '我关注的人发了新主题'),
  ('bookmark', '收藏的提醒到了'),
  ('node_announce', '已加入节点的公告'),
  ('node_topic', '已加入节点的新帖'),
  ('node_hot_topic', '已加入节点的热门帖'),
  ('mod', '我管理的节点有待处理事项'),
  ('energy', '能量与红包到账'),
  ('level', '升级和解锁成就'),
  ('safe', '安全提醒'),
];

/// 某类通知在某个渠道上是否开启：用户改过就用用户的，否则用站点默认值。
/// 渠道键：站内为 `reply`，邮件为 `reply.mail`。
bool notifyEnabled(Map settings, Map defaults, String key, {bool mail = false}) {
  final notify = settings['notify'] is Map ? settings['notify'] as Map : const {};
  final wire = mail ? '$key.mail' : key;
  if (notify[wire] is bool) return notify[wire] as bool;
  final d = defaults[key] is Map ? defaults[key] as Map : const {};
  return mail ? d['mail'] == true : d['site'] != false;
}

/// 账号设置（`/api/v1/me/settings`）：通知、邮件、隐私三组共用一个页面。
/// 修改时先更新界面，写入失败则回滚并提示。
class PreferenceScreen extends StatefulWidget {
  final PreferenceKind kind;

  const PreferenceScreen({super.key, required this.kind});

  @override
  State<PreferenceScreen> createState() => _PreferenceScreenState();
}

class _PreferenceScreenState extends State<PreferenceScreen> {
  Map<String, dynamic>? _settings;
  Map<String, dynamic> _delivery = {};
  Map<String, dynamic> _defaults = {};
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

  void _adopt(Map<String, dynamic> bag) {
    _settings = Map<String, dynamic>.from(bag['settings'] is Map ? bag['settings'] as Map : const {});
    _delivery = Map<String, dynamic>.from(bag['delivery'] is Map ? bag['delivery'] as Map : const {});
    _defaults = Map<String, dynamic>.from(bag['notify_defaults'] is Map ? bag['notify_defaults'] as Map : const {});
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (!app.isLoggedIn) {
      setState(() => _error = '请先登录');
      return;
    }
    try {
      final bag = await app.api.accountSettings();
      if (mounted) setState(() => _adopt(bag));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  /// 乐观更新：[apply] 先改本地，写入失败恢复原值。
  Future<void> _write(Map<String, dynamic> patch, void Function() apply) async {
    final api = context.read<AppState>().api;
    final settingsBefore = Map<String, dynamic>.from(_settings ?? const {});
    final notifyBefore = settingsBefore['notify'] is Map ? Map.from(settingsBefore['notify'] as Map) : null;
    final deliveryBefore = Map<String, dynamic>.from(_delivery);
    setState(apply);
    try {
      final bag = await api.updateAccountSettings(patch);
      if (mounted && bag['settings'] is Map) setState(() => _adopt(bag));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _settings = settingsBefore;
        if (notifyBefore != null) _settings!['notify'] = notifyBefore;
        _delivery = deliveryBefore;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：${friendlyError(e)}')));
    }
  }

  void _setFlag(String key, bool value) => _write({key: value}, () => _settings![key] = value);

  void _setNotify(String wireKey, bool value) => _write({
        'notify': {wireKey: value},
      }, () {
        final notify = Map<String, dynamic>.from(_settings!['notify'] is Map ? _settings!['notify'] as Map : const {});
        notify[wireKey] = value;
        _settings!['notify'] = notify;
      });

  Future<void> _pick(String title, Map<String, String> options, String current, void Function(String) onPick) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in options.entries)
            ListTile(
              title: Text(e.value),
              trailing: e.key == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ]),
      ),
    );
    if (picked != null && picked != current) onPick(picked);
  }

  Widget _pickerTile(String title, Map<String, String> options, String current, void Function(String) onPick) =>
      ListTile(
        title: Text(title),
        subtitle: Text(options[current] ?? current),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _pick(title, options, current, onPick),
      );

  Widget _flag(String key, String title, {String? subtitle, bool fallback = true}) {
    final value = _settings![key] is bool ? _settings![key] as bool : fallback;
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: (v) => _setFlag(key, v),
    );
  }

  static const _policies = {'everyone': '所有人', 'following': '我关注的人', 'nobody': '不允许'};

  List<Widget> _rows() {
    final s = _settings!;
    switch (widget.kind) {
      case PreferenceKind.notifications:
        return [
          const ListTile(
            dense: true,
            title: Text('每类通知可以分别选择是否在站内和邮件中提醒', style: TextStyle(fontSize: 12)),
          ),
          for (final (key, label) in notifyRows)
            ListTile(
              title: Text(label),
              trailing: Wrap(spacing: 6, children: [
                FilterChip(
                  label: const Text('站内'),
                  selected: notifyEnabled(s, _defaults, key),
                  onSelected: (v) => _setNotify(key, v),
                ),
                FilterChip(
                  label: const Text('邮件'),
                  selected: notifyEnabled(s, _defaults, key, mail: true),
                  onSelected: (v) => _setNotify('$key.mail', v),
                ),
              ]),
            ),
        ];
      case PreferenceKind.email:
        final notify = s['notify'] is Map ? s['notify'] as Map : const {};
        return [
          SwitchListTile(
            title: const Text('接收邮件通知'),
            subtitle: const Text('关闭后所有类别都不再发送邮件', style: TextStyle(fontSize: 12)),
            value: notify['email'] is bool ? notify['email'] as bool : true,
            onChanged: (v) => _setNotify('email', v),
          ),
          _pickerTile(
            '邮件发送频率',
            const {'now': '实时', 'hour': '每小时汇总', 'day': '每天汇总'},
            _delivery['mail_freq']?.toString() ?? 'now',
            (v) => _write({
              'delivery': {'mail_freq': v},
            }, () => _delivery['mail_freq'] = v),
          ),
          _pickerTile(
            '邮件精选摘要',
            const {'off': '不发送', 'daily': '每天', 'weekly': '每周'},
            s['digest']?.toString() ?? 'off',
            (v) => _write({'digest': v}, () => s['digest'] = v),
          ),
        ];
      case PreferenceKind.privacy:
        return [
          _flag('show_online', '显示在线状态', subtitle: '关闭后你也看不到别人的在线状态'),
          _flag('allow_follow', '允许他人关注我'),
          _flag('show_joined_nodes', '显示我加入的节点', subtitle: '在主页上列出你加入的公开节点'),
          _flag('show_level', '显示等级与声望'),
          _flag('show_upvotes', '公开我赞同过的内容', fallback: false),
          _flag('search_index', '允许搜索引擎收录我的主页'),
          _pickerTile('谁可以给我发私信', _policies, s['message_policy']?.toString() ?? 'everyone',
              (v) => _write({'message_policy': v}, () => s['message_policy'] = v)),
          _pickerTile('谁可以 @ 我', _policies, s['mention_policy']?.toString() ?? 'everyone',
              (v) => _write({'mention_policy': v}, () => s['mention_policy'] = v)),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _error != null
          ? Center(child: Text(_error!))
          : _settings == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(children: [
                  for (final w in _rows()) ...[w, const Divider(height: 1)],
                ]),
    );
  }
}
