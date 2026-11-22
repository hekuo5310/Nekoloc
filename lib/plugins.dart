/// 站点插件在帖子 JSON 中的只读表示：打赏（discourse-reward）、
/// 抽奖（discourse-lottery）、红包领取（discourse-red-envelope）。
///
/// 字段口径对齐参考客户端 NodeLoc Android 的解码测试：
/// - 打赏总额只统计正数，系统扣减（负数，is_system_reward）不计入；
/// - 抽奖的 max_participants 为 1000000 时表示“不限人数”，不是真实上限；
/// - 红包领取信息会挂在领取者的每一条回复上，只有 post_id 指向的那一楼才真正领取过。
library;


int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// 打赏记录。
class PostReward {
  final int amount;
  final String? username;
  final String? note;
  final bool isSystem;

  const PostReward({
    required this.amount,
    this.username,
    this.note,
    this.isSystem = false,
  });

  factory PostReward.fromJson(Map json) => PostReward(
        amount: _int(json['amount']),
        username: json['username']?.toString(),
        note: json['note']?.toString(),
        isSystem: json['is_system_reward'] == true,
      );
}

/// 本帖收到的打赏总额（不含系统扣减）。
int rewardTotal(List<PostReward> rewards) =>
    rewards.where((r) => r.amount > 0).fold(0, (sum, r) => sum + r.amount);

/// 抽奖活动。
class PostLottery {
  final int id;
  final String title;
  final String status;
  final int participantsCount;
  final int? maxParticipants;
  final DateTime? drawAt;
  final List<String> prizes;
  final int minTicketsPerUser;
  final int maxTicketsPerUser;
  final int userTickets;
  final bool isParticipating;

  const PostLottery({
    required this.id,
    required this.title,
    required this.status,
    required this.participantsCount,
    this.maxParticipants,
    this.drawAt,
    this.prizes = const [],
    this.minTicketsPerUser = 1,
    this.maxTicketsPerUser = 1,
    this.userTickets = 0,
    this.isParticipating = false,
  });

  bool get isOpen => status == 'open';

  /// 服务端用 1000000 表示“不限”，这里还原成 null。
  int? get participantCap {
    final max = maxParticipants;
    if (max == null || max <= 0 || max >= 1000000) return null;
    return max;
  }

  factory PostLottery.fromJson(Map json) {
    final levels = (json['levels'] as List?) ?? const [];
    return PostLottery(
      id: _int(json['id']),
      title: json['title']?.toString() ?? '抽奖',
      status: json['status']?.toString() ?? '',
      participantsCount: _int(json['participants_count']),
      maxParticipants: json['max_participants'] == null
          ? null
          : _int(json['max_participants']),
      drawAt: DateTime.tryParse(json['draw_at']?.toString() ?? ''),
      prizes: [
        for (final level in levels.whereType<Map>())
          if (level['prize'] != null) level['prize'].toString(),
      ],
      minTicketsPerUser: _int(json['min_tickets_per_user'] ?? 1),
      maxTicketsPerUser: _int(json['max_tickets_per_user'] ?? 1),
      userTickets: _int(json['user_tickets']),
      isParticipating: json['is_participating'] == true,
    );
  }
}

/// 当前用户在某楼获得的红包积分。只有指向本楼的领取记录才算数。
class RedEnvelopeClaim {
  final int? postId;
  final int pointsReceived;

  const RedEnvelopeClaim({this.postId, required this.pointsReceived});

  factory RedEnvelopeClaim.fromJson(Map json) => RedEnvelopeClaim(
        postId: json['post_id'] == null ? null : _int(json['post_id']),
        pointsReceived: _int(json['points_received']),
      );
}

/// 指定楼层领到的红包积分；该楼没有领取则返回 null。
int? claimedPointsForPost(RedEnvelopeClaim? claim, int postId) {
  if (claim == null || claim.postId != postId || claim.pointsReceived <= 0) {
    return null;
  }
  return claim.pointsReceived;
}

/// 每日签到状态。日期与“是否已签”都以服务端口径为准。
class CheckinStatus {
  final bool checkedInToday;
  final String? today;
  final int? pointsToday;
  final int? nextPoints;
  final int streak;
  final int totalDays;

  const CheckinStatus({
    this.checkedInToday = false,
    this.today,
    this.pointsToday,
    this.nextPoints,
    this.streak = 0,
    this.totalDays = 0,
  });

  /// 今天还能签到（尚未签到，且服务端给出了可领取的积分）。
  bool get canCheckIn => !checkedInToday && nextPoints != null;

  factory CheckinStatus.fromJson(Map json) => CheckinStatus(
        checkedInToday: json['checked_in_today'] == true,
        today: json['today']?.toString(),
        pointsToday: json['points_today'] == null ? null : _int(json['points_today']),
        nextPoints: json['next_points'] == null ? null : _int(json['next_points']),
        streak: _int(json['streak']),
        totalDays: _int(json['total_days']),
      );
}

/// 签到结果。`success` 在站点上可能是 true、也可能是字符串 "OK"，两种都要认。
class CheckinResult {
  final bool success;
  final int? points;
  final String? message;

  const CheckinResult({required this.success, this.points, this.message});

  factory CheckinResult.fromJson(Map json) {
    final s = json['success'];
    return CheckinResult(
      success: s == true || s == 'OK' || s == 'ok',
      points: json['points'] == null ? null : _int(json['points']),
      message: json['message']?.toString(),
    );
  }
}

/// 话题级红包的概况（发包人在话题上设置的红包）。
class TopicRedEnvelope {
  final int totalPoints;
  final int totalCount;
  final int availableCount;
  final bool exhausted;

  const TopicRedEnvelope({
    required this.totalPoints,
    required this.totalCount,
    required this.availableCount,
    required this.exhausted,
  });

  factory TopicRedEnvelope.fromJson(Map json) => TopicRedEnvelope(
        totalPoints: _int(json['total_points']),
        totalCount: _int(json['total_count']),
        availableCount: _int(json['available_count']),
        exhausted: json['exhausted'] == true,
      );
}
