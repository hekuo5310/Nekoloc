import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/account_models.dart';

void main() {
  test('站点布尔字段可能是 0/1 或字符串', () {
    expect(flexBool(true), isTrue);
    expect(flexBool(1), isTrue);
    expect(flexBool('1'), isTrue);
    expect(flexBool('true'), isTrue);
    expect(flexBool(0), isFalse);
    expect(flexBool(null), isFalse);
  });

  test('积分明细按 is_positive 或金额判断正负', () {
    final spent = PointsEntry.fromJson({'points': -20, 'description': '打赏'});
    expect(spent.isPositive, isFalse);
    final earned = PointsEntry.fromJson({'points': 5, 'is_positive': 1});
    expect(earned.isPositive, isTrue);
  });

  test('应用只有 webview 类型才标记为可在应用内运行', () {
    final webview = DirectoryApp.fromJson({'id': 1, 'slug': 'a', 'name': 'A', 'surface': 'webview'});
    final blocks = DirectoryApp.fromJson({'id': 2, 'slug': 'b', 'name': 'B', 'surface': 'blocks'});
    expect(webview.runsInApp, isTrue);
    expect(blocks.runsInApp, isFalse);
  });

  test('徽章允许作为头衔的标记按 allow_title 解析', () {
    final b = UserBadge.fromJson({'id': 3, 'name': '老兵', 'allow_title': true, 'image_url': '/x.png'});
    expect(b.allowTitle, isTrue);
    expect(b.imageUrl, '/x.png');
  });
}
