import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/api/discourse_api.dart';

/// 记录到的一次请求。
typedef Hit = ({String method, String path, Map<String, String> query, Map<String, String> headers, String body});

/// 本地假服务器：按 “方法 路径” 返回固定响应，未登记的路径返回 404 错误信封。
Future<(DiscourseApi, List<Hit>)> fakeServer(
  Map<String, (int, Object)> routes, {
  String? token,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final hits = <Hit>[];
  server.listen((request) async {
    final body = await utf8.decoder.bind(request).join();
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name.toLowerCase()] = values.join(','));
    hits.add((
      method: request.method,
      path: request.uri.path,
      query: request.uri.queryParameters,
      headers: headers,
      body: body,
    ));
    final route = routes['${request.method} ${request.uri.path}'];
    final (status, payload) = route ??
        (404, {'error': {'code': 'not_found', 'message': '不存在'}});
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(payload));
    await request.response.close();
  });
  return (DiscourseApi(base: 'http://127.0.0.1:${server.port}', token: token), hits);
}

void main() {
  test('请求带 Bearer token 与新版 User-Agent，路径在 /api/v1 下', () async {
    final (api, hits) = await fakeServer({
      'GET /api/v1/me': (200, {'user': {'id': 3, 'username': 'alice'}}),
      'GET /api/v1/notifications': (200, {'notifications': [], 'unread': 4}),
    }, token: 't0ken');
    final me = await api.currentUser();
    expect(me.username, 'alice');
    expect(me.unreadNotifications, 4);
    expect(hits.first.path, '/api/v1/me');
    expect(hits.first.headers['authorization'], 'Bearer t0ken');
    expect(hits.first.headers['user-agent'], startsWith('Nekoloc/2.'));
    // 登录响应只在请求不像浏览器时才带 token。
    expect(hits.first.headers.keys.where((k) => k.startsWith('sec-fetch')), isEmpty);
  });

  test('错误信封里的站点文案原样展示，错误代码保留', () async {
    final (api, _) = await fakeServer({
      'POST /api/v1/topics/9/posts': (422, {
        'error': {'code': 'invalid', 'message': '内容太短', 'fields': {'raw': '至少 5 个字'}},
      }),
    }, token: 't');
    try {
      await api.createReply(topicId: 9, raw: 'hi');
      fail('应当抛出异常');
    } on ApiException catch (e) {
      expect(e.message, '内容太短\n至少 5 个字');
      expect(e.code, 'invalid');
      expect(e.statusCode, 422);
    }
  });

  test('带 token 的请求被 401 拒绝时通知会话失效', () async {
    final (api, _) = await fakeServer({
      'GET /api/v1/me': (401, {'error': {'code': 'unauthorized', 'message': '请先登录'}}),
    }, token: 'stale');
    var rejected = false;
    api.onSessionRejected = () => rejected = true;
    await expectLater(api.currentUser(), throwsA(isA<UnauthorizedException>()));
    expect(rejected, isTrue);
  });

  test('没有参数的写请求也发送 {}（服务端拒绝空请求体）', () async {
    final (api, hits) = await fakeServer({
      'PUT /api/v1/posts/5/bookmark': (200, {'ok': true}),
    }, token: 't');
    expect(await api.addBookmark(5), 5);
    expect(hits.single.method, 'PUT');
    expect(hits.single.body, '{}');
    expect(hits.single.headers['content-type'], contains('application/json'));
  });

  test('定位到首页之外的楼层：再取该楼层往后的一页并合并', () async {
    final (api, hits) = await fakeServer({
      'GET /api/v1/nodes': (200, {'nodes': [{'id': 7, 'slug': 'vps', 'name': 'VPS'}]}),
      'GET /api/v1/topics/3': (200, {
        'topic': {'id': 3, 'title': '话题', 'node_slug': 'vps', 'reply_count': 60},
        'posts': [
          {'id': 1, 'post_number': 1, 'author': 'alice', 'html': '<p>一楼</p>', 'upvotes': 2},
        ],
        'next_after': 1,
        'permissions': {'reply': true, 'moderate': false},
      }),
    });
    final detail = await api.topic(3, postNumber: 42);
    expect(detail.categoryId, 7);
    expect(detail.likeCount, 2);
    expect(detail.canReply, isTrue);
    final topicCalls = hits.where((h) => h.path == '/api/v1/topics/3').toList();
    expect(topicCalls, hasLength(2));
    expect(topicCalls.last.query['after'], '41');
    // 红包、抽奖不存在时（404）静默忽略。
    expect(hits.any((h) => h.path == '/api/v1/topics/3/red-envelope'), isTrue);
    await expectLater(api.topic(3, postNumber: 0), throwsArgumentError);
  });

  test('投票：先取楼层的投票 id，再按选项 id 提交', () async {
    final poll = {
      'id': 11, 'post_id': 42, 'name': 'poll', 'type': 'multiple', 'closed': false,
      'options': [
        {'id': 1, 'text': '甲', 'votes': 3, 'chosen': true},
        {'id': 2, 'text': '乙', 'votes': 1, 'chosen': true},
      ],
    };
    final (api, hits) = await fakeServer({
      'GET /api/v1/posts/42/polls': (200, {'polls': [poll]}),
      'PUT /api/v1/polls/11/votes': (200, {'poll': poll}),
    }, token: 't');
    final result = await api.votePoll(42, 'poll', ['1', '2']);
    expect(result.vote, ['1', '2']);
    expect(result.poll!.options.map((o) => o.votes), [3, 1]);
    final put = hits.last;
    expect(put.method, 'PUT');
    expect(jsonDecode(put.body), {'option_ids': [1, 2]});
  });

  test('需要两步验证时抛出 SecondFactorRequiredException', () async {
    final (api, hits) = await fakeServer({
      'GET /api/v1/auth/captcha': (200, {'enabled': false}),
      'POST /api/v1/auth/login': (401, {'error': {'code': 'second_factor_required', 'message': '请输入动态码'}}),
    });
    await expectLater(
      api.login(login: 'alice', password: 'pw'),
      throwsA(isA<SecondFactorRequiredException>()),
    );
    final body = jsonDecode(hits.last.body) as Map;
    expect(body['login'], 'alice');
    expect(body['trust_device'], false);
  });

  test('登录成功后保存 token 与受信任设备标记', () async {
    final (api, hits) = await fakeServer({
      'GET /api/v1/auth/captcha': (200, {'enabled': false}),
      'POST /api/v1/auth/login': (200, {
        'token': 'new-token',
        'trust_token': 'trust-1',
        'user': {'id': 3, 'username': 'alice'},
      }),
    });
    final user = await api.login(login: 'alice', password: 'pw', totp: '123456');
    expect(user['username'], 'alice');
    expect(api.token, 'new-token');
    expect(api.trustToken, 'trust-1');
    expect(jsonDecode(hits.last.body)['code'], '123456');
  });

  test('站点要求人机验证而当前平台无法显示时，给出改用浏览器登录的提示', () async {
    final (api, _) = await fakeServer({
      'GET /api/v1/auth/captcha': (200, {
        'enabled': true,
        'provider': 'hcaptcha',
        'site_key': 'key',
        'actions': {'login': true},
        'login_mode': 'always',
      }),
    });
    await expectLater(
      api.login(login: 'alice', password: 'pw'),
      throwsA(isA<CaptchaUnavailableException>()),
    );
  });

  test('发新话题必须选节点，按节点别名提交', () async {
    final (api, hits) = await fakeServer({
      'GET /api/v1/nodes': (200, {'nodes': [{'id': 7, 'slug': 'vps', 'name': 'VPS'}]}),
      'POST /api/v1/topics': (201, {'topic': {'id': 99}, 'post': {'id': 500}}),
    }, token: 't');
    await expectLater(api.createTopic(title: 't', raw: 'r'), throwsA(isA<ApiException>()));
    final created = await api.createTopic(title: '标题', raw: '正文', categoryId: 7);
    expect(created['topic_id'], 99);
    expect(created['id'], 500);
    final body = jsonDecode(hits.last.body) as Map;
    expect(body['node'], 'vps');
    expect(body['title'], '标题');
  });

  test('列表用游标分页：第二页带上第一页给出的游标', () async {
    final (api, hits) = await fakeServer({
      'GET /api/v1/nodes': (200, {'nodes': []}),
      'GET /api/v1/topics': (200, {
        'topics': [
          {'id': 1, 'title': 'a', 'author': 'bob', 'reply_count': 2},
        ],
        'next_cursor': 'CUR',
      }),
    });
    final first = await api.topicList('latest');
    expect(first.hasMore, isTrue);
    expect(first.topics.single.postsCount, 3);
    await api.topicList('latest', page: 1);
    expect(hits.last.query['cursor'], 'CUR');
    // 热门按偏移分页。
    await api.topicList('top', page: 2);
    expect(hits.last.query['sort'], 'hot');
    expect(hits.last.query['offset'], '60');
  });
}
