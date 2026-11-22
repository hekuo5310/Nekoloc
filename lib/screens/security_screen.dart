import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../account_models.dart';
import '../api/friendly_error.dart';
import '../app_state.dart';

/// 账号安全：两步验证（TOTP 验证器）的添加、关闭，以及备用码。
/// 所有操作都针对当前登录账号，失败时只展示站点给出的说明。
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  List<TotpDevice>? _devices;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final devices = await context.read<AppState>().api.totpDevices();
      if (mounted) setState(() => _devices = devices);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  void _hint(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _hint(success);
      await _load();
    } catch (e) {
      _hint(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addAuthenticator() async {
    final api = context.read<AppState>().api;
    setState(() => _busy = true);
    late final ({String key, String? qr}) created;
    try {
      created = await api.createTotp();
    } catch (e) {
      _hint(friendlyError(e));
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;

    final codeCtl = TextEditingController();
    String? error;
    var verifying = false;
    final enabled = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('添加验证器'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('在验证器应用中手动添加以下密钥，然后输入应用显示的 6 位动态码：'),
              const SizedBox(height: 8),
              SelectableText(created.key, style: const TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 12),
              TextField(
                controller: codeCtl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: '动态码'),
              ),
              if (error != null)
                Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: verifying ? null : () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: verifying
                  ? null
                  : () async {
                      final code = codeCtl.text.trim();
                      if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                        setLocal(() => error = '请输入 6 位数字');
                        return;
                      }
                      setLocal(() {
                        verifying = true;
                        error = null;
                      });
                      try {
                        await api.enableTotp(code, '验证器');
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setLocal(() {
                          verifying = false;
                          error = friendlyError(e);
                        });
                      }
                    },
              child: const Text('启用'),
            ),
          ],
        ),
      ),
    );
    if (enabled == true) {
      _hint('两步验证已开启');
      await _load();
    }
  }

  Future<void> _disable() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关闭两步验证'),
        content: const Text('关闭后，登录将不再需要动态码。确定要关闭吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('关闭')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => context.read<AppState>().api.disableSecondFactor(), '已关闭两步验证');
  }

  Future<void> _backupCodes() async {
    final api = context.read<AppState>().api;
    try {
      final codes = await api.generateBackupCodes();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('备用码'),
          content: SelectableText(codes.join('\n'),
              style: const TextStyle(fontFamily: 'monospace')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('我已保存')),
          ],
        ),
      );
    } catch (e) {
      _hint(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices;
    final enabled = devices != null && devices.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('账号安全')),
      body: _error != null
          ? Center(child: Text(_error!))
          : devices == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: ListTile(
                        leading: Icon(enabled ? Icons.verified_user_outlined : Icons.shield_outlined),
                        title: const Text('两步验证'),
                        subtitle: Text(enabled
                            ? '已开启，共 ${devices.length} 个验证器'
                            : '未开启。开启后登录时需要输入验证器上的动态码'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!enabled)
                      FilledButton(
                        onPressed: _busy ? null : _addAuthenticator,
                        child: const Text('添加验证器'),
                      ),
                    if (enabled) ...[
                      OutlinedButton(
                        onPressed: _busy ? null : _backupCodes,
                        child: const Text('生成备用码'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _busy ? null : _disable,
                        child: const Text('关闭两步验证'),
                      ),
                    ],
                  ],
                ),
    );
  }
}
