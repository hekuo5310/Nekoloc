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
import 'push_watch.dart';
import 'update_checker.dart';

/// åºç¨åæéçæ¿è½½èï¼åå°è½®è¯¢å°çæ°éç¥ä»¥æ¨ªå¹å±ç¤ºï¼ã
final GlobalKey<ScaffoldMessengerState> appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// 全局应用状态：会话 + 外观
class AppState extends ChangeNotifier {
  final SharedPreferences prefs;
  AppState(this.prefs) {
    _init();
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

  /// å½åè´¦å·å±è½ï¼å¿½ç¥ï¼çç¨æ·åãç»å½åä»ç«ç¹è¯»åï¼éåºæ¶æ¸ç©ºã
  final Set<String> _blocked = {};
  Set<String> get blockedUsernames => Set.unmodifiable(_blocked);
  bool isBlocked(String? username) => username != null && _blocked.contains(username);

  /// æ¶æ¯æéè®¾ç½®ä¸æ°´ä½çº¿ï¼åªå¨æ¬æºä¿å­ï¼æ°´ä½çº¿éè´¦å·åæ¢æ¸ç©ºï¼ã
  PushSettings pushSettings = const PushSettings();
  PushWatchState _pushState = const PushWatchState();
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
    pushSettings = PushSettings(
      replies: prefs.getBool('push_replies') ?? true,
      likes: prefs.getBool('push_likes') ?? true,
      messages: prefs.getBool('push_messages') ?? true,
      system: prefs.getBool('push_system') ?? true,
    );
    _pushState = PushWatchState(
      watermark: prefs.getInt('push_watermark') ?? 0,
      baselineDone: prefs.getBool('push_baseline') ?? false,
    );
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

  /// åå°æ¶æ¯æéï¼ç»å½åæ¯ 15 åéæåä¸æ¬¡æªè¯»éç¥ã
  /// ç¬¬ä¸æ¬¡æåæååªè®¾åºçº¿ï¼è§ push_watch.dartï¼ï¼ä¸ä¼æç§¯åçæªè¯»å¨é¨å¼¹åºã
  void _restartPushPolling() {
    _pushTimer?.cancel();
    _pushTimer = null;
    if (!isLoggedIn) return;
    _pushTimer = Timer.periodic(_pushInterval, (_) => pollPush());
    unawaited(pollPush());
  }

  Future<void> pollPush() async {
    if (!isLoggedIn) return;
    try {
      final items = await api.notifications();
      final plan = planPushAlerts(items, _pushState, pushSettings);
      _pushState = plan.next;
      await prefs.setInt('push_watermark', plan.next.watermark);
      await prefs.setBool('push_baseline', plan.next.baselineDone);
      for (final n in plan.toAlert) {
        appMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(pushAlertText(n))),
        );
      }
    } catch (_) {
      // å¤±è´¥å°±ç­ä¸ä¸æ¬¡è½®è¯¢ï¼ä¸ææ°ç¨æ·ã
    }
  }

  void setPushSettings(PushSettings s) {
    pushSettings = s;
    prefs.setBool('push_replies', s.replies);
    prefs.setBool('push_likes', s.likes);
    prefs.setBool('push_messages', s.messages);
    prefs.setBool('push_system', s.system);
    notifyListeners();
  }

  /// ä»èªå·±çèµæè¯»åå¿½ç¥ååï¼æå¡ç«¯åªå¨æ¬äººèµæéè¿å ignored_usernamesï¼ã
  /// å¤±è´¥æ¶ä¿çåååï¼é¿åä¸æ¬¡ç½ç»æå¨å°±æå·²å±è½çç¨æ·éæ°æ¾ç¤ºåºæ¥ã
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

  /// ä¹è§æ´æ°ï¼è°ç¨æ¹åæ¹æ¬å°ååï¼å¤±è´¥æ¶åç¨åä¸æ¹æ³åæ»ã
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
    _pushState = const PushWatchState();
    await prefs.remove('push_watermark');
    await prefs.remove('push_baseline');
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
