import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/captcha.dart';
import '../app_state.dart';

Future<String?> solveCaptcha(CaptchaConfig config, String action) async {
  if (!(Platform.isAndroid || Platform.isIOS)) return null;
  final context = appNavigatorKey.currentContext;
  if (context == null || !context.mounted) return null;
  final token = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CaptchaDialog(config: config),
  );
  // 关掉窗口（含系统返回键）算作用户取消，与“显示不了”区分开。
  return token ?? '';
}

class _CaptchaDialog extends StatefulWidget {
  final CaptchaConfig config;
  const _CaptchaDialog({required this.config});

  @override
  State<_CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<_CaptchaDialog> {
  late final WebViewController _controller;
  bool _ready = false;
  String? _error;
  bool _done = false;
  Timer? _slow;

  @override
  void initState() {
    super.initState();
    // 验证组件来自第三方脚本，网络不通时会一直空白：给出可以继续的提示。
    _slow = Timer(const Duration(seconds: 15), () {
      if (mounted && !_ready && _error == null) {
        setState(() => _error = '验证组件加载超时。可以取消后改用“浏览器登录”，在站点页面里完成验证。');
      }
    });
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('NekolocCaptcha', onMessageReceived: (message) {
        final text = message.message;
        final split = text.indexOf(':');
        final kind = split < 0 ? text : text.substring(0, split);
        final value = split < 0 ? '' : text.substring(split + 1);
        if (!mounted) return;
        switch (kind) {
          case 'ready':
            _slow?.cancel();
            setState(() => _ready = true);
          case 'token':
            if (_done || value.isEmpty) return;
            _done = true;
            Navigator.of(context).pop(value);
          case 'error':
            setState(() => _error = value == 'expired' ? '验证已过期，请重新完成' : '验证组件加载失败（$value）');
        }
      })
      // hCaptcha 按页面域名校验站点密钥，所以页面必须以站点地址为基础加载。
      ..loadHtmlString(captchaPage(widget.config), baseUrl: '${AppState.baseUrl}/');
  }

  @override
  void dispose() {
    _slow?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('人机验证'),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      content: SizedBox(
        width: 320,
        height: 460,
        child: Column(
          children: [
            if (!_ready && _error == null) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(''), child: const Text('取消')),
      ],
    );
  }
}
