import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

/// RFC 7636 PKCE（S256）：浏览器登录回来的一次性 code 只能由发起登录的这个安装兑换。
abstract final class Pkce {
  /// 43 位 base64url 随机串（32 字节熵）。
  static String verifier([Random? random]) {
    final rng = random ?? Random.secure();
    final bytes = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
    return _base64Url(bytes);
  }

  static String challenge(String verifier) =>
      _base64Url(SHA256Digest().process(Uint8List.fromList(ascii.encode(verifier))));

  static String _base64Url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
}

/// 浏览器登录的起始地址：站点登录页，带上回调地址和 PKCE challenge。
/// [providerUrl] 为某个第三方登录的入口（来自 /api/v1/auth/providers），为空时打开站点登录页。
String browserLoginUrl({
  required String base,
  required String challenge,
  String redirectUri = 'nodeloc://auth',
  String? providerUrl,
}) {
  final start = (providerUrl == null || providerUrl.isEmpty)
      ? '$base/login'
      : (providerUrl.startsWith('http') ? providerUrl : '$base${providerUrl.startsWith('/') ? '' : '/'}$providerUrl');
  final uri = Uri.parse(start);
  return uri.replace(queryParameters: {
    ...uri.queryParameters,
    // 站点按 app 参数走客户端登录流程；目前它只认 android 这一个值。
    'app': 'android',
    'redirect_uri': redirectUri,
    'code_challenge': challenge,
  }).toString();
}
