import 'package:flutter/material.dart';

/// Web 平台不支持内置浏览器授权
Future<String?> openAuthorizeWindow(BuildContext context, String authUrl,
    {String callbackScheme = 'nodeloc://'}) async {
  return null;
}
