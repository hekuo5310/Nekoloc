import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'push_poller.dart';
import 'desktop_window.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme.dart';
import 'widgets/nekoloc_loading.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDesktopWindow();
  final prefs = await SharedPreferences.getInstance();
  await initBackgroundPush();
  runApp(NekolocApp(prefs: prefs));
}

class NekolocApp extends StatelessWidget {
  final SharedPreferences prefs;
  const NekolocApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(prefs),
      child: Consumer<AppState>(
        builder: (context, app, _) {
          return MaterialApp(
            title: 'Nekoloc',
            scaffoldMessengerKey: appMessengerKey,
            debugShowCheckedModeBanner: false,
            themeMode: app.themeMode,
            theme: NL.light(),
            darkTheme: NL.dark(),
            builder: (context, child) {
              final bar = desktopTitleBar();
              if (bar == null || child == null) {
                return child ?? const SizedBox.shrink();
              }
              return Column(
                children: [
                  bar,
                  Expanded(child: child),
                ],
              );
            },
            home: const _Gate(),
          );
        },
      ),
    );
  }
}

class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  /// 开屏动画首轮完整时长：猫耳立起(0.32s) + 字标写完(~2.1s)
  /// + 甩尾(2.32s) + 悬停余韵 —— 第一次加载必须播完整轮再进入 App。
  /// 若初始化网络请求慢于动画，则以初始化为准（动画无缝循环）。
  bool _minSplashDone = false;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _minSplashDone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ready = app.initialized && _minSplashDone;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: ready
          ? (app.isLoggedIn
              ? const HomeShell(key: ValueKey('home'))
              : const LoginScreen(key: ValueKey('login')))
          : const _Splash(),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 猫耳立起 -> "nekoloc" 逐笔写出 -> 甩尾 的品牌加载动画
            const NekolocLoading(width: 260),
            const SizedBox(height: 18),
            Text(
              '第三方社区客户端 · 与 NodeLoc 官方无关',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
