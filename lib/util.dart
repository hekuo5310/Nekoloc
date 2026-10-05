import 'dart:ui' show Color;

/// Only plain topic URLs can be opened here without losing a post target.
/// Both /t/slug/123/4 and /t/123/4 point at a specific floor.
int? inAppTopicId(Uri url, Uri site) {
  if (url.host != site.host || url.scheme != site.scheme ||
      url.query.isNotEmpty || url.fragment.isNotEmpty) return null;
  final parts = url.pathSegments;
  if (parts.isEmpty || parts.first != 't') return null;
  if (parts.length == 2) return int.tryParse(parts[1]);
  if (parts.length == 3 && int.tryParse(parts[1]) == null) {
    return int.tryParse(parts[2]);
  }
  return null;
}

String twoDigits(int n) => n.toString().padLeft(2, '0');

/// 中文相对时间
String timeAgo(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time.toLocal());
  if (diff.inSeconds < 0) return '刚刚';
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  final t = time.toLocal();
  final y = t.year == DateTime.now().year ? '' : '${t.year}-';
  return '$y${twoDigits(t.month)}-${twoDigits(t.day)}';
}

String fullDate(DateTime? time) {
  if (time == null) return '';
  final t = time.toLocal();
  return '${t.year}-${twoDigits(t.month)}-${twoDigits(t.day)}';
}

/// Color -> CSS hex（用于 HTML 富文本内联样式）
String cssHex(Color c) {
  final argb = c.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${argb.substring(2)}';
}

String compactNumber(int n) {
  if (n >= 10000) {
    final v = (n / 10000).toStringAsFixed(n % 10000 >= 1000 ? 1 : 0);
    return '$v 万';
  }
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

