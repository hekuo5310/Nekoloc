/// 账号与站点目录的只读模型：徽章、积分明细、应用目录。
/// 字段口径对齐参考客户端的解码测试（站点的 JSON 使用下划线命名，部分布尔值会以 0/1 出现）。

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// 站点的布尔字段可能是 true/false，也可能是 1/0 或 "true"/"1"。
bool flexBool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

class UserBadge {
  final int id;
  final String name;
  final String? description;
  final String? imageUrl;
  final bool allowTitle;

  const UserBadge({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
    this.allowTitle = false,
  });

  factory UserBadge.fromJson(Map json) => UserBadge(
        id: _int(json['id']),
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString(),
        imageUrl: (json['image_url'] ?? json['icon'])?.toString(),
        allowTitle: flexBool(json['allow_title']),
      );
}

class PointsEntry {
  final int points;
  final String description;
  final bool isPositive;
  final DateTime? createdAt;

  const PointsEntry({
    required this.points,
    required this.description,
    required this.isPositive,
    this.createdAt,
  });

  factory PointsEntry.fromJson(Map json) {
    final points = _int(json['points']);
    return PointsEntry(
      points: points,
      description: json['description']?.toString() ?? '',
      // 服务端给出 is_positive 时以它为准；否则按金额正负判断。
      isPositive: json.containsKey('is_positive') ? flexBool(json['is_positive']) : points >= 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

class PointsPage {
  final List<PointsEntry> entries;
  final bool hasMore;

  const PointsPage({required this.entries, required this.hasMore});
}

/// 应用目录中的一项。`surface` 为 "webview" 的应用可在应用内运行，"blocks" 的不能。
class DirectoryApp {
  final int id;
  final String slug;
  final String name;
  final String? description;
  final int installsCount;
  final String? surface;
  final int? versionNumber;
  final String? readmeCooked;
  final String? logoUrl;
  final String? homeUrl;

  const DirectoryApp({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    this.installsCount = 0,
    this.surface,
    this.versionNumber,
    this.readmeCooked,
    this.logoUrl,
    this.homeUrl,
  });

  bool get runsInApp => surface == 'webview';

  factory DirectoryApp.fromJson(Map json) => DirectoryApp(
        id: _int(json['id']),
        slug: json['slug']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString(),
        installsCount: _int(json['installs_count']),
        surface: json['surface']?.toString(),
        versionNumber: json['version_number'] == null ? null : _int(json['version_number']),
        readmeCooked: json['readme_cooked']?.toString(),
        logoUrl: json['logo_url']?.toString(),
        homeUrl: json['home_url']?.toString(),
      );
}
