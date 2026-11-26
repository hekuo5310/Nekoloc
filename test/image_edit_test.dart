import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nodeloc_app/image_edit.dart';

void main() {
  test('顺时针旋转交换宽高', () {
    final src = img.Image(width: 40, height: 20);
    final out = rotateClockwise(src);
    expect(out.width, 20);
    expect(out.height, 40);
  });

  test('居中裁剪到目标比例', () {
    final src = img.Image(width: 400, height: 200);
    final out = cropToRatio(src, 1);
    expect(out.width, out.height);
    expect(out.height, 200);
    final wide = cropToRatio(src, 16 / 9);
    expect(wide.width / wide.height, closeTo(16 / 9, 0.02));
  });

  test('不指定比例则保持原样', () {
    final src = img.Image(width: 30, height: 10);
    expect(identical(cropToRatio(src, null), src), isTrue);
  });

  test('最长边限制只缩小，不放大', () {
    final big = limitLongSide(img.Image(width: 4000, height: 2000), 1000);
    expect(big.width, 1000);
    expect(big.height, 500);
    final small = img.Image(width: 300, height: 200);
    expect(identical(limitLongSide(small, 1000), small), isTrue);
  });

  test('编码结果是可解码的 JPEG', () {
    final bytes = encodeForUpload(img.Image(width: 8, height: 8));
    final decoded = img.decodeJpg(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 8);
  });
}
