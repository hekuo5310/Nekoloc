import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_state.dart';

/// 应用内运行站点小程序（surface 为 webview 的应用）。
///
/// 登录状态通过 Cookie 交给 WebView，所以页面里看到的是已登录的账号。
/// 站内链接留在壳里；mailto、tel 等非网页链接交给系统处理。
/// 目前只支持 Android 与 iOS；桌面端请在浏览器中打开。
class MiniAppScreen extends StatefulWidget {
  final String name;
  final String url;

  const MiniAppScreen({super.key, required this.name, required this.url});

  /// 当前平台是否可以在应用内运行小程序。
  static bool get supported => Platform.isAndroid || Platform.isIOS;

  @override
  State<MiniAppScreen> createState() => _MiniAppScreenState();
}

class _MiniAppScreenState extends State<MiniAppScreen> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final app = context.read<AppState>();
      final host = Uri.parse(AppState.baseUrl).host;
      final cookies = await app.sessionCookies();
      final manager = WebViewCookieManager();
      for (final c in cookies) {
        await manager.setCookie(WebViewCookie(
          name: c.name,
          value: c.value,
          domain: host,
        ));
      }
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return NavigationDecision.navigate;
            }
            // mailto:、tel: 等交给系统处理，不在壳里加载。
            launchUrl(uri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _error = '页面加载失败，请稍后重试';
                });
              }
            }
          },
        ))
        ..loadRequest(Uri.parse(widget.url));
      if (mounted) setState(() => _controller = controller);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '无法启动应用，请稍后重试';
        });
      }
    }
  }

  Future<bool> _onBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _onBack() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.name),
          actions: [
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: () => _controller?.reload(),
            ),
          ],
        ),
        body: _error != null
            ? Center(child: Text(_error!))
            : _controller == null
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      WebViewWidget(controller: _controller!),
                      if (_loading) const LinearProgressIndicator(minHeight: 2),
                    ],
                  ),
      ),
    );
  }
}
