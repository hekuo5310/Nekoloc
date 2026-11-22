import 'package:dio/dio.dart';

import 'api/discourse_api.dart';

/// GIF 搜索（Klipy）。密钥由用户在设置里填写并只保存在本机，不随应用分发。

class GifItem {
  /// 缩略图地址，用于网格展示。
  final String previewUrl;

  /// 插入正文的完整 GIF 地址。
  final String url;
  final String title;

  const GifItem({required this.previewUrl, required this.url, required this.title});
}

/// 把 Klipy 的 media_formats 解析成列表。没有可用地址的条目会被跳过。
List<GifItem> parseKlipyResults(Map json) {
  final results = (json['results'] as List?) ?? const [];
  final items = <GifItem>[];
  for (final r in results.whereType<Map>()) {
    final formats = r['media_formats'];
    if (formats is! Map) continue;
    String? urlOf(String key) {
      final f = formats[key];
      final u = f is Map ? f['url']?.toString() : null;
      return (u == null || u.isEmpty) ? null : u;
    }

    final full = urlOf('gif') ?? urlOf('tinygif') ?? urlOf('nanogif');
    if (full == null) continue;
    final preview = urlOf('tinygif') ?? urlOf('nanogif') ?? full;
    items.add(GifItem(
      previewUrl: preview,
      url: full,
      title: r['title']?.toString() ?? '',
    ));
  }
  return items;
}

class GifKeyMissingException implements Exception {
  @override
  String toString() => '请先在设置中填写 GIF 搜索密钥';
}

class GifSearchClient {
  final Dio _dio;

  GifSearchClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: {'Accept': 'application/json'},
            ));

  Future<List<GifItem>> search(String apiKey, String query, {int limit = 24}) async {
    if (apiKey.trim().isEmpty) throw GifKeyMissingException();
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        'https://api.klipy.com/v2/search',
        queryParameters: {
          'key': apiKey.trim(),
          'q': query,
          'media_filter': 'gif',
          'limit': limit,
        },
      );
      final data = resp.data;
      if (data == null) return const [];
      return parseKlipyResults(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw ApiException('GIF 搜索密钥无效，请在设置中检查');
      }
      throw ApiException('GIF 搜索暂时不可用，请稍后重试');
    }
  }
}
