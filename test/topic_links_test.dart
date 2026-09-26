import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/util.dart';

void main() {
  final site = Uri.parse('https://www.nodeloc.com');

  test('plain topic links are routed in-app', () {
    expect(inAppTopicId(site.resolve('/t/topic-slug/123'), site), 123);
    expect(inAppTopicId(site.resolve('/t/123'), site), 123);
  });

  test('both floor URL forms retain browser navigation', () {
    expect(inAppTopicId(site.resolve('/t/topic-slug/123/4'), site), isNull);
    expect(inAppTopicId(site.resolve('/t/123/4'), site), isNull);
    expect(inAppTopicId(site.resolve('/t/topic-slug/123#post_4'), site), isNull);
  });

  test('external links are never routed as in-app topics', () {
    expect(inAppTopicId(Uri.parse('https://other.example/t/topic/123'), site), isNull);
  });
}
