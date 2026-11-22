import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../account_models.dart';
import '../api/friendly_error.dart';
import '../app_state.dart';

/// 应用目录（站点的小应用列表）。
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  List<DirectoryApp>? _apps;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final apps = await context.read<AppState>().api.appsDirectory();
      if (mounted) setState(() => _apps = apps);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_error != null) {
      body = Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _load, child: const Text('重试')),
      ]));
    } else if (_apps == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_apps!.isEmpty) {
      body = const Center(child: Text('应用目录暂时为空'));
    } else {
      final apps = _apps!;
      body = ListView.separated(
        itemCount: apps.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final app = apps[i];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.apps_outlined)),
            title: Text(app.name),
            subtitle: Text(app.description ?? '',
                maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Text('${app.installsCount} 安装'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AppDetailScreen(slug: app.slug, initial: app)),
            ),
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('应用目录')),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}

/// 应用详情：说明文档（README）与站点上的打开方式。
/// 只有 surface 为 webview 的应用支持在应用内运行，其余只能在网页打开。
class AppDetailScreen extends StatefulWidget {
  final String slug;
  final DirectoryApp? initial;

  const AppDetailScreen({super.key, required this.slug, this.initial});

  @override
  State<AppDetailScreen> createState() => _AppDetailScreenState();
}

class _AppDetailScreenState extends State<AppDetailScreen> {
  DirectoryApp? _app;
  String? _error;

  @override
  void initState() {
    super.initState();
    _app = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      final app = await context.read<AppState>().api.app(widget.slug);
      if (mounted) setState(() => _app = app);
    } catch (e) {
      if (mounted && _app == null) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    return Scaffold(
      appBar: AppBar(title: Text(app?.name ?? '应用')),
      body: app == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(app.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '${app.installsCount} 次安装'
                  '${app.versionNumber == null ? '' : ' · 版本 ${app.versionNumber}'}',
                  style: const TextStyle(fontSize: 12),
                ),
                if (app.description != null && app.description!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(app.description!),
                ],
                const SizedBox(height: 12),
                Text(
                  app.runsInApp
                      ? '该应用支持在应用内运行（当前版本仍需在网页打开）'
                      : '该应用需要在网页版中使用',
                  style: const TextStyle(fontSize: 12),
                ),
                if (app.homeUrl != null && app.homeUrl!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(app.homeUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('在网页打开'),
                  ),
                ],
                if (app.readmeCooked != null && app.readmeCooked!.isNotEmpty) ...[
                  const Divider(height: 32),
                  HtmlWidget(app.readmeCooked!),
                ],
              ],
            ),
    );
  }
}
