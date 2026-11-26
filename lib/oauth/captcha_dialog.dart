import '../api/captcha.dart';
import 'captcha_dialog_stub.dart' if (dart.library.io) 'captcha_dialog_io.dart' as impl;

/// 弹出人机验证，返回 token；用户关闭或当前平台无法显示时返回 null。
/// 只有 Android / iOS 能在应用内完成验证；桌面端请使用浏览器登录（验证在站点页面里完成）。
Future<String?> solveCaptcha(CaptchaConfig config, String action) => impl.solveCaptcha(config, action);
