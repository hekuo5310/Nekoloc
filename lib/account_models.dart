/// 账号与站点目录的只读模型：徽章、积分明细、应用目录。
/// 字段口径对齐参考客户端的解码测试（站点的 JSON 使用下划线命名，部分布尔值会以 0/1 出现）。
library;

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

/// 升级进度中的一条要求。`group` 决定它属于哪个分区（standing / activity / recent / all_time）。
class UpgradeCondition {
  final String label;
  final String text;
  final String scope;
  final String group;
  final String comparison;
  final int value;
  final int target;
  final bool met;

  const UpgradeCondition({
    required this.label,
    required this.text,
    required this.scope,
    required this.group,
    required this.comparison,
    required this.value,
    required this.target,
    required this.met,
  });

  factory UpgradeCondition.fromJson(Map json) => UpgradeCondition(
        label: json['label']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        scope: json['scope']?.toString() ?? '',
        group: json['group']?.toString() ?? '',
        comparison: json['comparison']?.toString() ?? 'min',
        value: _int(json['value']),
        target: _int(json['target']),
        met: flexBool(json['met']),
      );
}

class UpgradeProgress {
  final int currentLevel;
  final String? currentLevelName;
  final int? nextLevel;
  final String? nextLevelName;
  final List<UpgradeCondition> conditions;
  final int totalConditions;
  final int metCount;
  final bool maxLevelReached;
  final String? message;

  const UpgradeProgress({
    required this.currentLevel,
    this.currentLevelName,
    this.nextLevel,
    this.nextLevelName,
    this.conditions = const [],
    this.totalConditions = 0,
    this.metCount = 0,
    this.maxLevelReached = false,
    this.message,
  });

  double get fraction =>
      totalConditions <= 0 ? 0 : (metCount / totalConditions).clamp(0.0, 1.0);

  bool get allMet => totalConditions > 0 && metCount == totalConditions;

  factory UpgradeProgress.fromJson(Map json) => UpgradeProgress(
        currentLevel: _int(json['current_level']),
        currentLevelName: json['current_level_name']?.toString(),
        nextLevel: json['next_level'] == null ? null : _int(json['next_level']),
        nextLevelName: json['next_level_name']?.toString(),
        conditions: ((json['conditions'] as List?) ?? const [])
            .whereType<Map>()
            .map(UpgradeCondition.fromJson)
            .toList(),
        totalConditions: _int(json['total_conditions']),
        metCount: _int(json['met_count']),
        maxLevelReached: flexBool(json['max_level_reached']),
        message: json['message']?.toString(),
      );
}

/// 两步验证的 TOTP 设备。
class TotpDevice {
  final int id;
  final String name;
  final String? lastUsed;

  const TotpDevice({required this.id, required this.name, this.lastUsed});

  factory TotpDevice.fromJson(Map json) => TotpDevice(
        id: _int(json['id']),
        name: json['name']?.toString() ?? '验证器',
        lastUsed: json['last_used']?.toString(),
      );
}

/// 关联的第三方账号（如 GitHub、Google）。
class AssociatedAccount {
  final String name;
  final String? description;

  const AssociatedAccount({required this.name, this.description});

  factory AssociatedAccount.fromJson(Map json) => AssociatedAccount(
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString(),
      );
}

/// 一个登录设备（登录令牌）。
class AuthSession {
  final int id;
  final String deviceName;
  final String? osName;
  final String? clientName;
  final DateTime? seenAt;
  final bool isActive;

  const AuthSession({
    required this.id,
    required this.deviceName,
    this.osName,
    this.clientName,
    this.seenAt,
    this.isActive = false,
  });

  factory AuthSession.fromJson(Map json) => AuthSession(
        id: _int(json['id']),
        deviceName: (json['device_name'] ?? json['client_name'] ?? '未知设备').toString(),
        osName: json['os_name']?.toString(),
        clientName: json['client_name']?.toString(),
        seenAt: DateTime.tryParse(json['seen_at']?.toString() ?? ''),
        isActive: flexBool(json['is_active']),
      );
}
