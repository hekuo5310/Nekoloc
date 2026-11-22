import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 图片编辑的纯函数：旋转、翻转、按比例居中裁剪、限制最长边。
/// 与界面分离，便于用小图片做单元测试。

img.Image rotateClockwise(img.Image src) => img.copyRotate(src, angle: 90);

img.Image rotateCounterClockwise(img.Image src) => img.copyRotate(src, angle: -90);

img.Image flipHorizontal(img.Image src) => img.flipHorizontal(src);

/// 按宽高比居中裁剪。[ratio] 为 null 表示保持原样。
img.Image cropToRatio(img.Image src, double? ratio) {
  if (ratio == null) return src;
  final srcRatio = src.width / src.height;
  int w;
  int h;
  if (srcRatio > ratio) {
    h = src.height;
    w = (h * ratio).round();
  } else {
    w = src.width;
    h = (w / ratio).round();
  }
  w = w.clamp(1, src.width);
  h = h.clamp(1, src.height);
  final x = (src.width - w) ~/ 2;
  final y = (src.height - h) ~/ 2;
  return img.copyCrop(src, x: x, y: y, width: w, height: h);
}

/// 最长边超过 [maxSide] 时等比缩小，避免上传超大原图。
img.Image limitLongSide(img.Image src, int maxSide) {
  final longest = src.width > src.height ? src.width : src.height;
  if (longest <= maxSide) return src;
  final scale = maxSide / longest;
  return img.copyResize(
    src,
    width: (src.width * scale).round().clamp(1, maxSide),
    height: (src.height * scale).round().clamp(1, maxSide),
  );
}

/// 编码为 JPEG（发帖图片统一用 JPEG，体积较小）。
Uint8List encodeForUpload(img.Image src) => img.encodeJpg(src, quality: 90);
