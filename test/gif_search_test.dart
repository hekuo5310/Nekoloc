import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/gif_search.dart';

void main() {
  test('优先使用完整 GIF，缩略图使用 tinygif', () {
    final items = parseKlipyResults({
      'results': [
        {
          'title': '猫',
          'media_formats': {
            'gif': {'url': 'https://x/full.gif'},
            'tinygif': {'url': 'https://x/tiny.gif'},
          },
        },
      ],
    });
    expect(items.length, 1);
    expect(items.first.url, 'https://x/full.gif');
    expect(items.first.previewUrl, 'https://x/tiny.gif');
    expect(items.first.title, '猫');
  });

  test('没有任何可用地址的条目被跳过', () {
    final items = parseKlipyResults({
      'results': [
        {'media_formats': {}},
        {'media_formats': {'gif': {'url': ''}}},
        {'media_formats': {'nanogif': {'url': 'https://x/n.gif'}}},
      ],
    });
    expect(items.length, 1);
    expect(items.first.url, 'https://x/n.gif');
    expect(items.first.previewUrl, 'https://x/n.gif');
  });

  test('没有密钥时直接报错，不发请求', () async {
    expect(
      () => GifSearchClient().search('  ', '猫'),
      throwsA(isA<GifKeyMissingException>()),
    );
  });
}
