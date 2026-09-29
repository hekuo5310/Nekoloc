import 'dart:io';

import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

/// 应用当前版本（与 pubspec version 保持一致；发版时同步修改）
const String kAppVersion = '1.3.4';

class UpdateInfo {
  final String version;
  final String releaseNotes;
  final String releaseUrl;
  final Map<String, String> assetUrls; // 资产文件名 -> 下载 URL

  UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.releaseUrl,
    required this.assetUrls,
  });

  bool get isNewer => _compareVersions(version, kAppVersion) > 0;

  /// 当前平台对应的安装包文件名（null 表示无对应资产，回退到 Release 页）
  static String? platformAssetName() {
    if (Platform.isAndroid) return 'Nekoloc-Android-universal.apk';
    if (Platform.isWindows) return 'nodeloc-windows.zip';
    if (Platform.isMacOS) return 'nodeloc-macos.zip';
    if (Platform.isLinux) return 'nodeloc-linux.tar.gz';
    // iOS 未签名 IPA 无法自动安装，回退到 Release 页
    return null;
  }

  /// 当前平台对应的下载 URL（无则返回 Release 页 URL）
  String get platformDownloadUrl {
    final name = platformAssetName();
    if (name == null) return releaseUrl;
    return assetUrls[name] ?? releaseUrl;
  }
}

class UpdateChecker {
  static const _repo = 'hekuo5310/Nekoloc';

  /// 拉取 GitHub 最新 Release 信息
  static Future<UpdateInfo?> fetchLatest() async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Nekoloc/$kAppVersion',
        },
        validateStatus: (s) => s != null && s < 400,
      ));
      final resp = await dio.get(
          'https://api.github.com/repos/$_repo/releases/latest');
      final data = resp.data is Map
          ? Map<String, dynamic>.from(resp.data as Map)
          : <String, dynamic>{};
      final tag = data['tag_name']?.toString() ?? '';
      final version = tag.replaceFirst(RegExp(r'^v'), '');
      if (version.isEmpty) return null;
      final assetUrls = <String, String>{};
      for (final a in (data['assets'] as List? ?? [])) {
        if (a is Map) {
          final name = a['name']?.toString() ?? '';
          final url = a['browser_download_url']?.toString() ?? '';
          if (name.isNotEmpty && url.isNotEmpty) {
            assetUrls[name] = url;
          }
        }
      }
      return UpdateInfo(
        version: version,
        releaseNotes: data['body']?.toString() ?? '',
        releaseUrl: data['html_url']?.toString() ??
            'https://github.com/$_repo/releases/latest',
        assetUrls: assetUrls,
      );
    } catch (_) {
      return null;
    }
  }

  /// 在外部浏览器打开下载链接
  static Future<void> openDownload(UpdateInfo info) async {
    await launchUrl(Uri.parse(info.platformDownloadUrl),
        mode: LaunchMode.externalApplication);
  }
}

/// 版本号比较：返回 -1 / 0 / 1
int _compareVersions(String a, String b) {
  final pa = a.split(RegExp(r'[.+_-]')).map((e) => int.tryParse(e) ?? 0).toList();
  final pb = b.split(RegExp(r'[.+_-]')).map((e) => int.tryParse(e) ?? 0).toList();
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x > y ? 1 : -1;
  }
  return 0;
}
