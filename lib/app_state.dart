import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';

import 'api/discourse_api.dart';
import 'mobile_source.dart';
import 'models.dart';
import 'oauth/rsa.dart';
import 'oauth/webview_login.dart';
import 'push_poller.dart';
import 'push_watch.dart';
import 'system_notifier.dart';
import 'update_checker.dart';

/// 应用内提醒的承载者（前台轮询到的新通知以横幅展示）。
final GlobalKey<ScaffoldMessengerState> appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// 全局应用状态：会话 + 外观
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final SharedPreferences prefs;
  AppState(this.prefs) {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  /// 应用是否在前台。前台用应用内横幅提醒，后台用系统通知。
  bool _foreground = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  /// 站点固定为 NodeLoc 官方
  static const String baseUrl = 'https://www.nodeloc.com';

  ThemeMode themeMode = ThemeMode.dark;
  DiscourseApi? _api;
  PersistCookieJar? _jar;
  CurrentUser? user;
  SiteInfo? siteInfo;
  bool initialized = false;
  String? _userApiKey;

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
    _userApiKey = prefs.getString('user_api_key');
    postSourceLevel = prefs.getInt('post_source_level') ?? 4;
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
    final dir = await getApplicationSupportDirectory();
    final cookieDir = Directory('${dir.path}/cookies');
    if (!cookieDir.existsSync()) {
      cookieDir.createSync(recursive: true);
    }
    _jar = PersistCookieJar(
      ignoreExpires: true,
      storage: FileStorage(cookieDir.path),
    );
    _api = DiscourseApi(
      base: baseUrl,
      jar: _jar!,
      userApiKey: _userApiKey,
    );
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

  /// 当前会话的站点 Cookie（用于把登录状态交给应用内的 WebView，例如小程序外壳）。
  Future<List<Cookie>> sessionCookies() async {
    final jar = _jar;
    if (jar == null) return const [];
    return jar.loadForRequest(Uri.parse(baseUrl));
  }

  void setPushSettings(PushSettings s) {
    pushSettings = s;
    unawaited(savePushSettings(prefs, s));
    notifyListeners();
  }

  /// 从自己的资料读取忽略名单（服务端只在本人资料里返回 ignored_usernames）。
  /// 失败时保留原名单，避免一次网络抖动就把已屏蔽的用户重新显示出来。
  Future<void> reloadBlocked() async {
    final me = user?.username;
    if (me == null) {
      _blocked.clear();
      return;
    }
    try {
      final profile = await api.userProfile(me);
      _blocked
        ..clear()
        ..addAll(profile.ignoredUsernames);
      notifyListeners();
    } catch (_) {}
  }

  /// 乐观更新：调用方先改本地名单，失败时再用同一方法回滚。
  void setBlocked(String username, bool blocked) {
    final changed = blocked ? _blocked.add(username) : _blocked.remove(username);
    if (changed) notifyListeners();
  }

  Future<void> login(String login, String password, String? totp) async {
    // 若存在旧的 API Key 会话，先清理，避免混合
    if (_userApiKey != null) {
      _userApiKey = null;
      await prefs.remove('user_api_key');
      await _createApi();
    }
    await api.login(login: login, password: password, totp: totp);
    await refreshUser();
  }

  /// 浏览器授权登录（支持第三方 OAuth / 邮箱登录链接 / 2FA 等全部登录方式）。
  /// 流程：生成一次性 RSA 密钥对 -> 内置浏览器打开 Discourse 授权页 ->
  /// 用户以任意方式登录并授权 -> 拦截 discourse:// 回调 -> 解密得到 User-Api-Key。
  Future<void> loginViaBrowser(BuildContext context) async {
    if (_userApiKey != null) {
      _userApiKey = null;
      await prefs.remove('user_api_key');
      await _createApi();
    }

    final bundle = generateRsaKeyPair();
    final nonce = randomHex(32);
    final clientId = randomHex(24);
    final authUrl = Uri.parse('$baseUrl/user-api-key/new').replace(queryParameters: {
      'application_name': 'Nekoloc',
      'client_id': clientId,
      'scopes': 'read,write,session_info,notifications',
      'auth_redirect': 'discourse://auth_redirect',
      'nonce': nonce,
      'public_key': bundle.publicKeyPem,
    }).toString();

    // ignore: use_build_context_synchronously
    final callbackUrl = await openAuthorizeWindow(context, authUrl);
    if (callbackUrl == null) {
      throw ApiException('已取消授权');
    }

    final uri = Uri.parse(callbackUrl);
    if (uri.queryParameters['denied'] == 'true') {
      throw ApiException('你拒绝了授权');
    }
    final payload = uri.queryParameters['payload'];
    if (payload == null || payload.isEmpty) {
      throw ApiException('授权回调缺少凭据');
    }

    final data = decryptUserApiKeyPayload(
      bundle: bundle,
      payloadB64: payload,
      expectedNonce: nonce,
    );
    final key = data?['key']?.toString();
    if (data == null || key == null || key.isEmpty) {
      throw ApiException('授权凭据解密失败，请重试');
    }

    _userApiKey = key;
    await prefs.setString('user_api_key', key);
    await _createApi();
    await refreshUser();
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {}
    _userApiKey = null;
    await prefs.remove('user_api_key');
    await _jar?.deleteAll();
    user = null;
    _blocked.clear();
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
