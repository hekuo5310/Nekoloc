import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/api/discourse_api.dart';
import 'package:nodeloc_app/app_state.dart';
import 'package:nodeloc_app/screens/topic_detail_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 话题 3 共 12 楼，每页 4 楼；按 `after` 返回之后的楼层。
class _FakeTopic implements HttpClientAdapter {
  final List<String> requests = [];

  Map<String, dynamic> _post(int n) => {
        'id': 100 + n,
        'post_number': n,
        'author': 'user$n',
        'author_id': n,
        'html': '<p>第 $n 楼</p>',
      };

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final uri = options.uri;
    requests.add('${uri.path}?${uri.query}');
    Object body;
    var status = 200;
    if (uri.path == '/api/v1/topics/3') {
      final after = int.tryParse(uri.queryParameters['after'] ?? '') ?? 0;
      // 首页只给两楼，制造“定位到 #10 时中间缺 3–9 楼”的情形。
      final last = after == 0 ? 2 : (after + 4).clamp(0, 12);
      body = {
        'topic': {'id': 3, 'title': '缺口话题', 'reply_count': 11},
        'posts': [for (var n = after + 1; n <= last; n++) _post(n)],
        'next_after': last < 12 ? last : null,
        'permissions': {'reply': true},
      };
    } else if (uri.path == '/api/v1/nodes') {
      body = {'nodes': []};
    } else {
      status = 404;
      body = {'error': {'code': 'not_found', 'message': '不存在'}};
    }
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json; charset=utf-8'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('定位到远处楼层后，「加载中间楼层」逐页补齐直到接上目标楼层', (tester) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fake = _FakeTopic();
    final dio = Dio(BaseOptions(
      baseUrl: 'https://example.test',
      validateStatus: (s) => s != null,
      responseType: ResponseType.plain,
    ))..httpClientAdapter = fake;
    final app = AppState.withApi(prefs, DiscourseApi(base: 'https://example.test', dio: dio));

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: const MaterialApp(home: TopicDetailScreen(topicId: 3, initialPostNumber: 10)),
    ));
    await tester.pumpAndSettle();

    // 先只显示定位到的楼层。
    expect(find.text('已定位到 #10'), findsOneWidget);
    await tester.tap(find.text('查看完整话题'));
    await tester.pumpAndSettle();

    expect(find.text('加载中间楼层（#3 – #9）'), findsOneWidget);
    expect(find.textContaining('第 2 楼', findRichText: true), findsOneWidget);
    expect(find.textContaining('第 3 楼', findRichText: true), findsNothing);
    expect(find.textContaining('第 10 楼', findRichText: true), findsOneWidget);

    await tester.tap(find.text('加载中间楼层（#3 – #9）'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 6 楼', findRichText: true), findsOneWidget);
    expect(find.text('加载中间楼层（#7 – #9）'), findsOneWidget);

    await tester.tap(find.text('加载中间楼层（#7 – #9）'));
    await tester.pumpAndSettle();
    for (final n in [7, 8, 9]) {
      expect(find.textContaining('第 $n 楼', findRichText: true), findsOneWidget);
    }
    expect(find.textContaining('加载中间楼层'), findsNothing);
    // 每楼只出现一次，没有重复。
    expect(find.textContaining('第 10 楼', findRichText: true), findsOneWidget);
    expect(fake.requests.where((r) => r.contains('after=2')), hasLength(1));
    expect(fake.requests.where((r) => r.contains('after=6')), hasLength(1));
  });
}
