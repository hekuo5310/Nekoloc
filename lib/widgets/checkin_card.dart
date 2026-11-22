import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/friendly_error.dart';
import '../app_state.dart';
import '../plugins.dart';

/// 每日签到卡片：显示今日状态、连续天数与累计积分，并提供签到按钮。
/// 签到以服务端的日期为准，重复签到时直接展示服务端给出的说明。
class CheckinCard extends StatefulWidget {
  const CheckinCard({super.key});

  @override
  State<CheckinCard> createState() => _CheckinCardState();
}

class _CheckinCardState extends State<CheckinCard> {
  CheckinStatus? _status;
  int? _total;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final me = app.user?.username;
    if (me == null) return;
    try {
      final status = await app.api.checkinStatus();
      final total = await app.api.pointsTotal(me);
      if (!mounted) return;
      setState(() {
        _status = status;
        _total = total;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _checkin() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await context.read<AppState>().api.checkin();
      await _load();
      if (!mounted) return;
      final text = result.success
          ? (result.points != null ? '签到成功，获得 ${result.points} 积分' : '签到成功')
          : (result.message ?? '今天已经签到过了');
      messenger.showSnackBar(SnackBar(content: Text(text)));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('签到失败：${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final subtitle = _error ??
        (status == null
            ? '加载中…'
            : '累计积分 ${_total ?? '-'} · 连续签到 ${status.streak} 天'
                '${status.checkedInToday ? ' · 今日已签到' : ''}');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        leading: const Icon(Icons.event_available_outlined),
        title: const Text('每日签到'),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: status == null
            ? null
            : FilledButton.tonal(
                onPressed: (_busy || !status.canCheckIn) ? null : _checkin,
                child: Text(status.checkedInToday ? '已签到' : '签到'),
              ),
      ),
    );
  }
}
