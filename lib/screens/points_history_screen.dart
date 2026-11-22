import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../account_models.dart';
import '../api/friendly_error.dart';
import '../app_state.dart';

/// 积分明细：顶部为累计积分，下方按时间倒序列出每一笔变动，支持继续加载。
class PointsHistoryScreen extends StatefulWidget {
  const PointsHistoryScreen({super.key});

  @override
  State<PointsHistoryScreen> createState() => _PointsHistoryScreenState();
}

class _PointsHistoryScreenState extends State<PointsHistoryScreen> {
  final List<PointsEntry> _entries = [];
  int? _total;
  int _page = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _moreError;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  String? get _me => context.read<AppState>().user?.username;

  Future<void> _load({required bool reset}) async {
    final me = _me;
    if (me == null) {
      setState(() {
        _loading = false;
        _error = '请先登录';
      });
      return;
    }
    final app = context.read<AppState>();
    final page = reset ? 0 : _page + 1;
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
        _moreError = null;
      }
    });
    try {
      final result = await app.api.pointsHistory(me, page: page);
      final total = reset ? await app.api.pointsTotal(me) : _total;
      if (!mounted) return;
      setState(() {
        if (reset) _entries.clear();
        _entries.addAll(result.entries);
        _page = page;
        _hasMore = result.hasMore;
        _total = total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (reset) {
          _error = friendlyError(e);
        } else {
          _moreError = friendlyError(e);
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: () => _load(reset: true), child: const Text('重试')),
      ]));
    } else {
      body = ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.stars_outlined),
            title: const Text('累计积分'),
            trailing: Text('${_total ?? '-'}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          const Divider(height: 1),
          if (_entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('暂无积分记录')),
            ),
          for (final e in _entries) ...[
            ListTile(
              title: Text(e.description.isEmpty ? '积分变动' : e.description),
              subtitle: e.createdAt == null
                  ? null
                  : Text('${e.createdAt!.toLocal()}'.split('.').first,
                      style: const TextStyle(fontSize: 12)),
              trailing: Text(
                '${e.isPositive && e.points > 0 ? '+' : ''}${e.points}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: e.isPositive ? Colors.green : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
            const Divider(height: 1),
          ],
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                if (_moreError != null) Text(_moreError!),
                OutlinedButton(
                  onPressed: _loadingMore ? null : () => _load(reset: false),
                  child: Text(_loadingMore ? '加载中…' : '加载更多'),
                ),
              ]),
            ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('积分记录')),
      body: RefreshIndicator(onRefresh: () => _load(reset: true), child: body),
    );
  }
}
