import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../account_models.dart';
import '../api/friendly_error.dart';
import '../app_state.dart';

/// 升级进度：当前等级、下一等级，以及按分区列出的各项要求。
class UpgradeProgressScreen extends StatefulWidget {
  const UpgradeProgressScreen({super.key});

  @override
  State<UpgradeProgressScreen> createState() => _UpgradeProgressScreenState();
}

class _UpgradeProgressScreenState extends State<UpgradeProgressScreen> {
  UpgradeProgress? _progress;
  String? _error;

  static const _groupTitles = {
    'standing': '当前状态',
    'activity': '活跃度',
    'recent': '近期表现',
    'all_time': '累计',
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
    setState(() => _error = null);
    try {
      final p = await app.api.upgradeProgress(me);
      if (mounted) setState(() => _progress = p);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    Widget body;
    if (_error != null) {
      body = Center(child: Text(_error!));
    } else if (p == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final groups = <String, List<UpgradeCondition>>{};
      for (final c in p.conditions) {
        groups.putIfAbsent(c.group, () => []).add(c);
      }
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            p.maxLevelReached
                ? '已达到最高等级：${p.currentLevelName ?? p.currentLevel}'
                : '当前：${p.currentLevelName ?? p.currentLevel}'
                    '${p.nextLevelName == null ? '' : ' → 下一级：${p.nextLevelName}'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: p.fraction),
          const SizedBox(height: 4),
          Text('已满足 ${p.metCount}/${p.totalConditions} 项',
              style: const TextStyle(fontSize: 12)),
          if (p.message != null && p.message!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(p.message!, style: const TextStyle(fontSize: 12)),
          ],
          for (final key in ['standing', 'activity', 'recent', 'all_time'])
            if (groups[key] != null) ...[
              const SizedBox(height: 16),
              Text(_groupTitles[key] ?? key,
                  style: Theme.of(context).textTheme.titleSmall),
              for (final c in groups[key]!)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    c.met ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: c.met ? Colors.green : null,
                  ),
                  title: Text(c.label.isEmpty ? c.text : c.label),
                  subtitle: Text(
                    '${c.scope.isEmpty ? '' : '${c.scope} · '}'
                    '${c.comparison == 'max' ? '不超过' : '至少'} ${c.target}'
                    '（当前 ${c.value}）',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('升级进度')),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}
