import 'dart:convert';
import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/api/discourse_api.dart';

void main() {
  test('poll transport repeats options[] and uses authenticated PUT/DELETE', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final calls = <({String method, String path, String? key, Map<String, List<String>> form})>[];
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      calls.add((method: request.method, path: request.uri.path,
        key: request.headers.value('User-Api-Key'), form: Uri(query: body).queryParametersAll));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'poll': {'name': 'named', 'type': 'multiple'},
        'vote': request.method == 'PUT' ? ['a', 'b'] : []}));
      await request.response.close();
    });
    final api = DiscourseApi(base: 'http://127.0.0.1:${server.port}', jar: CookieJar(), userApiKey: 'test-key');
    final result = await api.votePoll(42, 'named', ['a', 'b']);
    expect(result.vote, ['a', 'b']);
    await api.removePollVote(42, 'named');
    expect(calls, hasLength(2));
    expect(calls.first.method, 'PUT');
    expect(calls.first.path, '/polls/vote');
    expect(calls.first.key, 'test-key');
    expect(calls.first.form['options[]'], ['a', 'b']);
    expect(calls.first.form['post_id'], ['42']);
    expect(calls.last.method, 'DELETE');
    expect(calls.last.form['poll_name'], ['named']);
    expect(calls.last.form.containsKey('options[]'), isFalse);
  });

  test('paged search and bookmarks encode query parameters', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final urls = <Uri>[];
    server.listen((request) async {
      urls.add(request.uri);
      request.response.headers.contentType = ContentType.json;
      request.response.write('{}');
      await request.response.close();
    });
    final api = DiscourseApi(base: 'http://127.0.0.1:${server.port}', jar: CookieJar(), userApiKey: 'test');
    await api.search('中文 in:title', page: 2);
    await api.bookmarks('alice', page: 3);
    expect(urls.first.queryParameters, {'q': '中文 in:title', 'page': '2'});
    expect(urls.last.path, '/u/alice/bookmarks.json');
    expect(urls.last.queryParameters['page'], '3');
  });
}
