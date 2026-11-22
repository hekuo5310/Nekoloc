import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../account_models.dart';
import '../api/friendly_error.dart';
import '../app_state.dart';
import '../models.dart';
import 'activation_screen.dart';

/// 注册（分步流程的合并版）：账号信息 → 站点要求的字段（如性别）→ 兴趣节点。
///
/// 站点要求的字段来自站点设置（show_on_signup），不写死。兴趣节点从子节点中随机挑选 8 个；
/// 账号若需要邮件激活，无法立即加入，界面会说明。
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _username = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  List<SignupField> _fields = const [];
  final Map<int, String> _fieldValues = {};
  List<Category> _interestCandidates = const [];
  final Set<int> _interests = {};
  bool _loadingExtras = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  @override
  void dispose() {
    _username.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadExtras() async {
    final api = context.read<AppState>().api;
    try {
      final fields = await api.signupUserFields();
      final nodes = await api.nodes();
      // 只推荐子节点；随机挑 8 个，避免每次都是同一批。
      final subs = nodes.where((n) => n.parentId != null).toList()..shuffle(Random());
      if (!mounted) return;
      setState(() {
        _fields = fields;
        _interestCandidates = subs.take(8).toList();
      });
    } catch (_) {
      // 字段或节点加载失败时仍可注册，只是少了这两步。
    } finally {
      if (mounted) setState(() => _loadingExtras = false);
    }
  }

  String? _validate() {
    if (_username.text.trim().isEmpty || _email.text.trim().isEmpty || _password.text.isEmpty) {
      return '请填写用户名、邮箱和密码';
    }
    for (final f in _fields) {
      if (f.required && (_fieldValues[f.id] ?? '').isEmpty) {
        return '请选择「${f.name}」';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await app.api.signup(
        username: _username.text.trim(),
        name: _name.text,
        email: _email.text.trim(),
        password: _password.text,
        userFields: _fieldValues,
      );
      if (!mounted) return;
      if (r.active) {
        // 账号已激活，站点已为这台设备登录：加入所选节点，再刷新账号。
        for (final id in _interests) {
          try {
            await app.api.setNodeJoined(id, true);
          } catch (_) {
            // 个别节点加入失败不影响注册结果。
          }
        }
        await app.refreshUser();
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }
      // 需要激活：进入激活页（站点发的邮件含激活链接，应用内不提供重发）。
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActivationScreen(
            email: _email.text.trim(),
            message: r.message,
          ),
        ),
      );
      if (mounted) Navigator.pop(context, false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Widget _fieldWidget(SignupField f) {
    if (f.fieldType == 'dropdown' && f.options.isNotEmpty) {
      return DropdownButtonFormField<String>(
        value: _fieldValues[f.id]?.isEmpty == true ? null : _fieldValues[f.id],
        decoration: InputDecoration(labelText: f.name + (f.required ? ' *' : '')),
        items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text(o))],
        onChanged: (v) => setState(() => _fieldValues[f.id] = v ?? ''),
      );
    }
    return TextField(
      decoration: InputDecoration(labelText: f.name + (f.required ? ' *' : '')),
      onChanged: (v) => _fieldValues[f.id] = v,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('注册')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _username,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '昵称（可选）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: '邮箱'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码'),
          ),
          for (final f in _fields) ...[
            const SizedBox(height: 12),
            _fieldWidget(f),
          ],
          if (_interestCandidates.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('选择你感兴趣的节点（可选）', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in _interestCandidates)
                  FilterChip(
                    label: Text(n.name),
                    selected: _interests.contains(n.id),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _interests.add(n.id);
                      } else {
                        _interests.remove(n.id);
                      }
                    }),
                  ),
              ],
            ),
          ] else if (_loadingExtras) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('注册'),
          ),
        ],
      ),
    );
  }
}
