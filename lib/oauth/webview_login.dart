import 'package:flutter/material.dart';

import 'webview_login_stub.dart'
    if (dart.library.io) 'webview_login_io.dart' as impl;

/// 在内置浏览器窗口中打开站点登录页。
/// 用户以任意方式登录后（密码、动态码、第三方账号、人机验证都在站点页面里完成），
/// 站点会跳转到以 [callbackScheme] 开头的地址（如 nodeloc://auth?code=…），
/// 本函数拦截该跳转并返回完整回调地址；用户关闭窗口则返回 null。
Future<String?> openAuthorizeWindow(BuildContext context, String authUrl,
        {String callbackScheme = 'nodeloc://'}) =>
    impl.openAuthorizeWindow(context, authUrl, callbackScheme: callbackScheme);
