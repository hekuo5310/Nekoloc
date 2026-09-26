import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../mobile_source.dart';
import '../theme.dart';
import '../update_checker.dart';
import '../widgets/common.dart';

/// 设置页
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checking = false;
  int _pawTaps = 0; // 猫咪彩蛋计数器
  String? _deviceBadge; // 当前设备徽章预览（null = 桌面端/不可用）

  @override
  void initState() {
    super.initState();
    _loadDevicePreview();
  }

  Future<void> _loadDevicePreview() async {
    final badge = await MobileSource.previewBadge(4);
    if (mounted) setState(() => _deviceBadge = badge);
  }

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    final app = context.read<AppState>();
    await app.checkForUpdate(force: true);
    if (!mounted) return;
    setState(() => _checking = false);
    final info = app.updateInfo;
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前已是最新版本 v$kAppVersion')),
      );
    } else {
      _showUpdateDialog(app, info);
    }
  }

  void _showUpdateDialog(AppState app, UpdateInfo info) {
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v${info.version}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('当前版本：v$kAppVersion',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    info.releaseNotes.isEmpty ? '（暂无更新说明）' : info.releaseNotes,
                    style: const TextStyle(fontSize: 12.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              app.openUpdateDownload();
            },
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('立即下载'),
          ),
        ],
      ),
    );
  }

  /// 彩蛋：关于标题连点 5 次 -> 猫咪打招呼
  void _onPawTap() {
    _pawTaps++;
    if (_pawTaps >= 5) {
      _pawTaps = 0;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1.0),
                duration: const Duration(milliseconds: 380),
                curve: Curves.elasticOut,
                builder: (_, s, child) =>
                    Transform.scale(scale: s, child: child),
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: NL.greenDark.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.pets,
                      size: 46, color: NL.greenDark),
                ),
              ),
              const SizedBox(height: 14),
              const Text('喵~ 你找到我啦！',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Nekoloc = neko（猫）+ loc（NodeLoc）\n'
                '一只爱逛 NodeLoc 的第三方猫咪客户端 v$kAppVersion',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('喵！'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              children: [
                ListTile(
                  leading: _checking
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update_outlined),
                  title: const Text('检查更新'),
                  subtitle: Text(
                    app.updateInfo != null
                        ? '新版本 v${app.updateInfo!.version} 可用'
                        : '当前版本 v$kAppVersion',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: app.updateInfo != null
                      ? FilledButton(
                          onPressed: () => _showUpdateDialog(app, app.updateInfo!),
                          child: const Text('更新'),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _checking ? null : _checkUpdate,
                ),
              ],
            ),
          ),
          // ---------------- 发帖设备信息（对齐官方 APP mobile_source）
          Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.smartphone_outlined, size: 18),
                      SizedBox(width: 6),
                      Text('发帖设备信息',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                          value: 0,
                          icon: Icon(Icons.block, size: 16),
                          label: Text('关闭')),
                      ButtonSegment(
                          value: 1,
                          icon: Icon(Icons.android, size: 16),
                          label: Text('平台')),
                      ButtonSegment(
                          value: 3,
                          icon: Icon(Icons.business, size: 16),
                          label: Text('品牌')),
                      ButtonSegment(
                          value: 4,
                          icon: Icon(Icons.smartphone, size: 16),
                          label: Text('型号')),
                    ],
                    selected: {app.postSourceLevel},
                    onSelectionChanged: (v) =>
                        app.setPostSourceLevel(v.first),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _deviceBadge == null
                        ? '移动端发帖时在帖子下方显示设备徽章；当前为桌面端，不会发送设备信息'
                        : '移动端发帖时显示设备徽章，当前将显示：$_deviceBadge',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('外观',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                          value: 0,
                          icon: Icon(Icons.dark_mode_outlined, size: 18),
                          label: Text('深色')),
                      ButtonSegment(
                          value: 1,
                          icon: Icon(Icons.light_mode_outlined, size: 18),
                          label: Text('浅色')),
                      ButtonSegment(
                          value: 2,
                          icon: Icon(Icons.brightness_auto_outlined, size: 18),
                          label: Text('跟随系统')),
                    ],
                    selected: {
                      switch (app.themeMode) {
                        ThemeMode.dark => 0,
                        ThemeMode.light => 1,
                        _ => 2,
                      }
                    },
                    onSelectionChanged: (v) {
                      app.setThemeMode(switch (v.first) {
                        0 => ThemeMode.dark,
                        1 => ThemeMode.light,
                        _ => ThemeMode.system,
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '默认深色主题遵循 NodeLoc 官方配色（暖黑 + 松石绿 + 橘橙）',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('源代码（GitHub）'),
                  subtitle: const Text('hekuo5310/Nekoloc',
                      style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => launchUrl(
                    Uri.parse('https://github.com/hekuo5310/Nekoloc'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('NodeLoc 网站'),
                  subtitle: const Text(AppState.baseUrl,
                      style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => launchUrl(
                    Uri.parse(AppState.baseUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _onPawTap,
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: NL.greenDark,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: NL.orangeDark,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('关于',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Center(child: NekolocLoading(width: 170)),
                  const SizedBox(height: 10),
                  Text(
                    'Nekoloc v$kAppVersion —— NodeLoc 社区第三方开源猫咪客户端\n'
                    '基于 Flutter 构建，覆盖 Android / iOS / Windows / macOS / Linux\n'
                    '支持账号密码 + 2FA 登录与浏览器授权登录（第三方账号 / 邮箱登录链接），\n'
                    '凭据仅保存在本机；浏览、发帖、回复、表情反应、私信、收藏、图片上传等\n'
                    '功能均通过官方用户级接口完成。本客户端与 NodeLoc 官方无关',
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.7,
                        color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
