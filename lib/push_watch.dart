import 'models.dart';

/// 消息提醒的纯逻辑（对齐参考客户端 PushRepository 的规则）。
///
/// - 第一次成功拉取只设定基线（水位线），不提醒——否则开启提醒时会把积压的未读全部弹出；
/// - 水位线推进到拉到的最新通知 id，即使该类别被静音也推进，否则重新打开会补发积压；
/// - 每次最多提醒最近的 5 条，避免长时间离线后一次弹出一墙通知。

enum PushCategory { replies, likes, messages, system }

/// 通知类型编号 -> 提醒类别。编号与 Discourse 的 notification_types 一致。
PushCategory pushCategoryFor(int type) {
  switch (type) {
    case 5: // liked
    case 19: // liked_consolidated
    case 25: // reaction
    case 5000: // reward_received
      return PushCategory.likes;
    case 6: // private_message
    case 7: // invited_to_private_message
    case 13: // invited_to_topic
    case 28: // event_invitation
    case 29: // chat_mention
    case 30: // chat_message
    case 31: // chat_invitation
    case 32: // chat_group_mention
    case 33: // chat_quoted
    case 40: // chat_watched_thread
      return PushCategory.messages;
    case 1: // mentioned
    case 2: // replied
    case 3: // quoted
    case 4: // edited
    case 9: // posted
    case 11: // linked
    case 15: // group_mentioned
    case 17: // watching_first_post
    case 36: // watching_category_or_tag
    case 39: // linked_consolidated
    case 800: // following
    case 801: // following_created_topic
    case 802: // following_replied
      return PushCategory.replies;
    default:
      return PushCategory.system;
  }
}

class PushSettings {
  final bool replies;
  final bool likes;
  final bool messages;
  final bool system;

  const PushSettings({
    this.replies = true,
    this.likes = true,
    this.messages = true,
    this.system = true,
  });

  bool allows(PushCategory category) => switch (category) {
        PushCategory.replies => replies,
        PushCategory.likes => likes,
        PushCategory.messages => messages,
        PushCategory.system => system,
      };

  PushSettings copyWith({bool? replies, bool? likes, bool? messages, bool? system}) =>
      PushSettings(
        replies: replies ?? this.replies,
        likes: likes ?? this.likes,
        messages: messages ?? this.messages,
        system: system ?? this.system,
      );
}

class PushWatchState {
  /// 已经处理过的最大通知 id。
  final int watermark;

  /// 是否已经完成基线（第一次成功拉取之后为 true）。
  final bool baselineDone;

  const PushWatchState({this.watermark = 0, this.baselineDone = false});
}

class PushWatchPlan {
  final List<NotificationItem> toAlert;
  final PushWatchState next;

  const PushWatchPlan({required this.toAlert, required this.next});
}

/// 根据这次拉取到的通知，决定提醒哪些、以及水位线推进到哪里。
PushWatchPlan planPushAlerts(
  List<NotificationItem> items,
  PushWatchState state,
  PushSettings settings,
) {
  var newest = 0;
  for (final n in items) {
    if (n.id > newest) newest = n.id;
  }

  if (!state.baselineDone) {
    return PushWatchPlan(
      toAlert: const [],
      next: PushWatchState(watermark: newest, baselineDone: true),
    );
  }

  final fresh = items
      .where((n) =>
          !n.read &&
          n.id > state.watermark &&
          settings.allows(pushCategoryFor(n.type)))
      .toList()
    ..sort((a, b) => a.id.compareTo(b.id));

  final capped = fresh.length > 5 ? fresh.sublist(fresh.length - 5) : fresh;
  final watermark = newest > state.watermark ? newest : state.watermark;
  return PushWatchPlan(
    toAlert: capped,
    next: PushWatchState(watermark: watermark, baselineDone: true),
  );
}

/// 提醒文案：类别前缀 + 发起人 + 话题标题。
String pushAlertText(NotificationItem n) {
  final prefix = switch (pushCategoryFor(n.type)) {
    PushCategory.replies => '新回复',
    PushCategory.likes => '新点赞',
    PushCategory.messages => '新私信',
    PushCategory.system => '新通知',
  };
  final who = n.displayUsername.isEmpty ? '' : '@${n.displayUsername} ';
  final title = n.topicTitle.isEmpty ? '' : '「${n.topicTitle}」';
  return '$prefix：$who$title'.trim();
}
