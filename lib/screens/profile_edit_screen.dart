import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/friendly_error.dart';
import '../app_state.dart';

/// 编辑个人资料：昵称、个人简介（Markdown）、网站、地点、头衔。
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _website = TextEditingController();
  final _location = TextEditingController();
  final _title = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _website.dispose();
    _location.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final me = app.user?.username;
    if (me == null) {
      setState(() {
        _loading = false;
        _error = '请先登录';
      });
      return;
    }
    try {
      final f = await app.api.ownProfileFields(me);
      if (!mounted) return;
      _name.text = f['name'] ?? '';
      _bio.text = f['bio_raw'] ?? '';
      _website.text = f['website'] ?? '';
      _location.text = f['location'] ?? '';
      _title.text = f['title'] ?? '';
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    final me = app.user?.username;
    if (me == null || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await app.api.updateProfile(
        me,
        name: _name.text.trim(),
        bioRaw: _bio.text,
        website: _website.text.trim(),
        location: _location.text.trim(),
        title: _title.text.trim(),
      );
      await app.refreshUser();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('资料已保存')));
      Navigator.pop(context, true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存失败：${friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑资料'),
        actions: [
          TextButton(
            onPressed: (_loading || _saving || _error != null) ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: '昵称'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bio,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: '个人简介（支持 Markdown）',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _title,
                      decoration: const InputDecoration(
                        labelText: '头衔',
                        helperText: '只能使用已获得且允许作为头衔的徽章，站点会校验',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _website,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: '网站'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _location,
                      decoration: const InputDecoration(labelText: '地点'),
                    ),
                  ],
                ),
    );
  }
}
