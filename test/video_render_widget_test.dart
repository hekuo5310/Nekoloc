import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:nodeloc_app/api/v1_mapping.dart';

const _sha = '0123456789abcdef0123456789abcdef01234567';

String _html() => rewriteUploadVideos(
      '<p>视频如下</p><div class="video-embed" data-provider="upload" data-video-id="$_sha"></div>',
      {
        _sha: {'status': 'ready', 'hls_url': 'https://cdn.example/v.m3u8', 'width': 1280, 'height': 720},
      },
      fallbackUrl: 'https://www.nodeloc.com/t/9/1',
    );

Finder _player() => find.byWidgetPredicate((w) => w.runtimeType.toString() == 'VideoPlayer');

void main() {
  testWidgets('安卓上，转码好的站内视频渲染成播放器', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: HtmlWidget(_html()))));
      await tester.pump();
      expect(_player(), findsOneWidget);
      expect(find.textContaining('网页版观看', findRichText: true), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('不支持播放的平台（如 Linux）显示去网页版观看的链接', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: HtmlWidget(_html()))));
      await tester.pump();
      expect(_player(), findsNothing);
      expect(find.textContaining('视频（点击在网页版观看）', findRichText: true), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
