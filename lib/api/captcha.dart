/// 站点的人机验证（`GET /api/v1/auth/captcha`）。
///
/// 登录、注册、注册验证码、找回密码这四个未登录的写操作可能需要验证码 token。
/// token 只能由验证码提供方自己的网页组件生成，所以网络层通过 [CaptchaSolver]
/// 把“请用户完成验证”交给界面层（见 lib/oauth/captcha_dialog.dart），自己只负责发送。
library;

class CaptchaConfig {
  final bool enabled;

  /// `hcaptcha`、`turnstile` 或 `recaptcha`。
  final String provider;
  final String siteKey;

  /// 提供方脚本地址；hCaptcha 的地址已带 `render=explicit` 和 onload 回调名。
  final String script;
  final Map<String, bool> actions;

  /// `always` 每次登录都要；`after_failures` 失败几次后服务端才要求。
  final String loginMode;

  const CaptchaConfig({
    this.enabled = false,
    this.provider = '',
    this.siteKey = '',
    this.script = '',
    this.actions = const {},
    this.loginMode = 'always',
  });

  factory CaptchaConfig.fromJson(Map json) => CaptchaConfig(
        enabled: json['enabled'] == true,
        provider: json['provider']?.toString() ?? '',
        siteKey: json['site_key']?.toString() ?? '',
        script: json['script']?.toString() ?? '',
        actions: {
          for (final e in ((json['actions'] as Map?) ?? const {}).entries)
            e.key.toString(): e.value == true,
        },
        loginMode: json['login_mode']?.toString() ?? 'always',
      );

  /// 这个操作当前是否需要验证码。
  bool guards(String action) => enabled && siteKey.isNotEmpty && actions[action] == true;

  /// 登录是否要在第一次尝试前就先完成验证。
  bool get loginUpfront => loginMode != 'after_failures';
}

/// 让用户完成一次验证，返回 token。用户关闭验证窗口时返回空字符串；
/// 当前平台无法显示验证组件时返回 null（调用方应改走浏览器登录）。
typedef CaptchaSolver = Future<String?> Function(CaptchaConfig config, String action);

/// 验证码相关的操作名，与服务端 `actions` 的键一致。
abstract final class CaptchaAction {
  static const login = 'login';
  static const register = 'register';
  static const registerCode = 'register_code';
  static const passwordReset = 'password_reset';
}

/// 生成验证组件页面。三家提供方都支持 `render(container, options)` 的显式渲染。
/// [channel] 是页面回传 token 用的 JavaScript 通道名。
String captchaPage(CaptchaConfig config, {String channel = 'NekolocCaptcha', String lang = 'zh-CN'}) {
  final global = switch (config.provider) {
    'turnstile' => 'turnstile',
    'recaptcha' => 'grecaptcha',
    _ => 'hcaptcha',
  };
  var src = config.script.isNotEmpty
      ? config.script
      : switch (config.provider) {
          'turnstile' => 'https://challenges.cloudflare.com/turnstile/v0/api.js',
          'recaptcha' => 'https://www.google.com/recaptcha/api.js',
          _ => 'https://js.hcaptcha.com/1/api.js',
        };
  // 服务端给的 hCaptcha 地址已带 onload=nlCaptchaLoaded；其他提供方要补上显式渲染参数。
  if (!src.contains('onload=')) src += '${src.contains('?') ? '&' : '?'}onload=nlCaptchaLoaded';
  if (!src.contains('render=')) src += '&render=explicit';
  if (config.provider != 'turnstile') src += '&hl=$lang';
  final key = config.siteKey.replaceAll('"', '');
  return '''
<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;background:transparent}#c{display:flex;justify-content:center;padding-top:8px}</style>
</head><body><div id="c"></div>
<script>
function send(kind, value){ try { $channel.postMessage(kind + ':' + value); } catch (e) {} }
function nlCaptchaLoaded(){
  try {
    window.$global.render('c', {
      sitekey: "$key",
      callback: function(t){ send('token', t); },
      'error-callback': function(e){ send('error', String(e || 'error')); },
      'expired-callback': function(){ send('error', 'expired'); }
    });
    send('ready', '1');
  } catch (e) { send('error', String(e)); }
}
</script>
<script src="${src.replaceAll('"', '')}" async defer></script>
</body></html>''';
}
