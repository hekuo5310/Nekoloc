import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';

import 'api/discourse_api.dart';
import 'mobile_source.dart';
import 'models.dart';
import 'oauth/captcha_dialog.dart';
import 'oauth/pkce.dart';
import 'oauth/webview_login.dart';
import 'push_poller.dart';
import 'message_bus.dart';
import 'push_watch.dart';
import 'system_notifier.dart';
import 'update_checker.dart';

/// 应用内提醒的承载者（前台轮询到的新通知以横幅展示）。
final GlobalKey<ScaffoldMessengerState> appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// 根导航器（人机验证弹窗等需要在任意页面上弹出时使用）。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 本机保存会话的键。token 与站点会话等价，只保存在本机。
const String kAuthTokenKey = 'auth_token';
const String kAuthTrustKey = 'auth_trust';

/// 全局应用状态：会话 + 外观
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final SharedPreferences prefs;
  AppState(this.prefs) {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  /// 测试用：直接使用给定的接口，不做初始化里的联网步骤。
  @visibleForTesting
  AppState.withApi(this.prefs, DiscourseApi api) {
    _api = api;
    initialized = true;
  }

  /// 应用是否在前台。前台用应用内横幅提醒，后台用系统通知。
  bool _foreground = true;

  /// 实时推送（MessageBus）：聊天消息与新通知。只在登录且位于前台时运行。
  final MessageBusClient bus = MessageBusClient();
  void Function()? _notificationCancel;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _startBus();
    } else {
      bus.stop();
    }
  }

  void _startBus() {
    final me = user;
    if (me == null || !_foreground) {
      bus.stop();
      _notificationCancel?.call();
      _notificationCancel = null;
      return;
    }
    // 新通知到达时立即拉取一次，不必等 15 分钟的定时轮询。
    _notificationCancel ??= bus.subscribe('/notification/${me.id}', () => pollPush());
    bus.start(api);
  }

  /// 站点固定为 NodeLoc 官方
  static const String baseUrl = 'https://www.nodeloc.com';

  ThemeMode themeMode = ThemeMode.dark;
  DiscourseApi? _api;
  CurrentUser? user;
  SiteInfo? siteInfo;
  bool initialized = false;

  /// 发帖设备信息等级（对齐官方 APP 的 post_source_level）：
  /// 0 = 关闭；1 = 仅平台；3 = 平台 + 品牌；4 = 完整型号。默认完整显示。
  int postSourceLevel = 4;

  bool get isLoggedIn => user != null;
  DiscourseApi get api => _api ?? (throw StateError('API 未初始化'));

  /// 当前账号屏蔽（忽略）的用户名。登录后从站点读取，退出时清空。
  final Set<String> _blocked = {};
  Set<String> get blockedUsernames => Set.unmodifiable(_blocked);
  bool isBlocked(String? username) => username != null && _blocked.contains(username);

  /// 消息提醒设置与水位线（只在本机保存，水位线随账号切换清空）。
  PushSettings pushSettings = const PushSettings();
  Timer? _pushTimer;

  static const Duration _pushInterval = Duration(minutes: 15);

  UpdateInfo? updateInfo;
  bool _updateChecked = false;

  Future<void> _init() async {
    final tm = prefs.getString('theme_mode') ?? 'dark';
    themeMode = switch (tm) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    // 1.x 的 Discourse 凭据在新版站点上已经无效，直接清掉，提示重新登录。
    unawaited(prefs.remove('user_api_key'));
    postSourceLevel = prefs.getInt('post_source_level') ?? 4;
    klipyApiKey = prefs.getString('klipy_api_key') ?? '';
    pushSettings = pushSettingsFromPrefs(prefs);
    await _createApi();
    try {
      siteInfo = await api.siteBasicInfo();
    } catch (_) {}
    await refreshUser();
    initialized = true;
    notifyListeners();
    // 后台检查更新（不阻塞初始化）
    checkForUpdate();
  }

  Future<void> _createApi() async {
    _api = DiscourseApi(
      base: baseUrl,
      token: prefs.getString(kAuthTokenKey),
      trustToken: prefs.getString(kAuthTrustKey),
    )
      ..captchaSolver = solveCaptcha
      ..onSessionRejected = _onSessionRejected;
  }

  /// 会话在别处被注销（服务端对带 token 的请求回答 401）：按退出处理，但不再请求服务端。
  void _onSessionRejected() {
    if (_api?.token == null) return;
    _api?.token = null;
    unawaited(prefs.remove(kAuthTokenKey));
    if (user != null) {
      user = null;
      _blocked.clear();
      _restartPushPolling();
      notifyListeners();
    }
  }

  Future<void> _saveSession() async {
    final t = api.token;
    if (t != null) await prefs.setString(kAuthTokenKey, t);
    final trust = api.trustToken;
    if (trust != null) await prefs.setString(kAuthTrustKey, trust);
  }

  /// 接口已拿到新会话（例如注册后自动登录）：保存 token，再刷新账号。
  Future<void> adoptSession() async {
    await _saveSession();
    await refreshUser();
  }

  /// 静默刷新当前用户（不触发 UI loading）
  Future<void> refreshUser() async {
    try {
      user = await api.currentUser();
    } catch (_) {
      user = null;
    }
    await reloadBlocked();
    _restartPushPolling();
    notifyListeners();
  }

  /// 前台消息提醒：登录后每 15 分钟拉取一次未读通知。
  /// 第一次成功拉取只设基线（见 push_watch.dart），不会把积压的未读全部弹出。
  void _restartPushPolling() {
    _pushTimer?.cancel();
    _pushTimer = null;
    _startBus();
    if (!isLoggedIn) {
      unawaited(scheduleBackgroundPush(false));
      return;
    }
    unawaited(scheduleBackgroundPush(true));
    _pushTimer = Timer.periodic(_pushInterval, (_) => pollPush());
    unawaited(pollPush());
  }

  /// 拉取一次未读通知并提醒：前台显示应用内横幅，后台（或不可见时）发系统通知。
  Future<void> pollPush() async {
    if (!isLoggedIn) return;
    try {
      final alerts = await runPushPoll(prefs, api);
      for (final n in alerts) {
        final text = pushAlertText(n);
        if (_foreground) {
          appMessengerKey.currentState?.showSnackBar(SnackBar(content: Text(text)));
        } else {
          await SystemNotifier.show(n.id, text);
        }
      }
    } catch (_) {
      // 失败就等下一次轮询，不打扰用户。
    }
  }

  /// GIF 搜索密钥（Klipy），由用户在设置中填写，只保存在本机。
  String klipyApiKey = '';

  void setKlipyApiKey(String key) {
    klipyApiKey = key.trim();
    prefs.setString('klipy_api_key', klipyApiKey);
    notifyListeners();
  }

  /// 交给应用内 WebView（例如小程序外壳）的站点会话 Cookie。
  /// 新版站点的会话 Cookie `nl_session` 的值就是登录 token。
  Future<List<Cookie>> sessionCookies() async {
    final t = _api?.token;
    if (t == null) return const [];
    return [Cookie('nl_session', t)];
  }

  void setPushSettings(PushSettings s) {
    pushSettings = s;
    unawaited(savePushSettings(prefs, s));
    notifyListeners();
  }

  /// 读取屏蔽名单（`/me/blocks`）。
  /// 失败时保留原名单，避免一次网络抖动就把已屏蔽的用户重新显示出来。
  Future<void> reloadBlocked() async {
    if (user == null) {
      _blocked.clear();
      return;
    }
    try {
      final names = await api.blockedUsernames();
      _blocked
        ..clear()
        ..addAll(names);
      notifyListeners();
    } catch (_) {}
  }

  /// 乐观更新：调用方先改本地名单，失败时再用同一方法回滚。
  void setBlocked(String username, bool blocked) {
    final changed = blocked ? _blocked.add(username) : _blocked.remove(username);
    if (changed) notifyListeners();
  }

  /// 账号密码登录。站点开启人机验证时，移动端会先弹出验证；桌面端请用浏览器登录。
  Future<void> login(String login, String password, String? totp) async {
    await api.login(login: login, password: password, totp: totp);
    await _saveSession();
    await refreshUser();
  }

  /// 浏览器登录（站点登录页：密码、动态码、第三方账号、人机验证都在页面里完成）。
  /// 流程：生成 PKCE verifier → 内置浏览器打开站点登录页 → 登录后站点跳转
  /// nodeloc://auth?code=… → 拦截跳转 → 用 code + verifier 换取会话 token。
  /// [providerUrl] 为某个第三方登录入口（为空时打开站点登录页）。
  Future<void> loginViaBrowser(BuildContext context, {String? providerUrl}) async {
    final verifier = Pkce.verifier();
    final authUrl = browserLoginUrl(
      base: baseUrl,
      challenge: Pkce.challenge(verifier),
      providerUrl: providerUrl,
    );
    final callbackUrl = await openAuthorizeWindow(context, authUrl, callbackScheme: 'nodeloc://');
    if (callbackUrl == null) throw ApiException('已取消授权');
    final uri = Uri.parse(callbackUrl);
    if (uri.queryParameters['error'] != null) throw ApiException('已取消授权');
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) throw ApiException('授权回调缺少凭据，请重试');
    await api.exchangeAuthCode(code, verifier: verifier);
    await _saveSession();
    await refreshUser();
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {}
    api.token = null;
    await prefs.remove(kAuthTokenKey);
    user = null;
    _blocked.clear();
    bus.stop();
    _notificationCancel?.call();
    _notificationCancel = null;
    _pushTimer?.cancel();
    _pushTimer = null;
    await resetPushState(prefs);
    unawaited(scheduleBackgroundPush(false));
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    prefs.setString(
      'theme_mode',
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.system => 'system',
        _ => 'dark',
      },
    );
    notifyListeners();
  }

  String? avatarUrl(String? template, {int size = 96}) =>
      _api?.resolveAvatarUrl(template, size: size);

  /// 发帖时携带的 mobile_source 设备信息字段（关闭 / 桌面端返回 null）
  Future<Map<String, String>?> mobileSourceFields() =>
      MobileSource.fieldsForLevel(postSourceLevel);

  void setPostSourceLevel(int level) {
    postSourceLevel = level;
    prefs.setInt('post_source_level', level);
    notifyListeners();
  }

  /// 检查 GitHub 最新 Release 是否有新版本；有则置 updateInfo 并通知
  Future<void> checkForUpdate({bool force = false}) async {
    if (_updateChecked && !force) return;
    _updateChecked = true;
    final info = await UpdateChecker.fetchLatest();
    if (info != null && info.isNewer && updateInfo == null) {
      updateInfo = info;
      notifyListeners();
    } else if (info != null && !info.isNewer) {
      updateInfo = null;
      notifyListeners();
    }
  }

  /// 打开下载页（用户点击更新横幅/对话框时调用）
  Future<void> openUpdateDownload() async {
    final info = updateInfo;
    if (info == null) return;
    await UpdateChecker.openDownload(info);
  }

  /// 清除更新提示（用户选择“以后再说”）
  void dismissUpdate() {
    updateInfo = null;
    notifyListeners();
  }
}
