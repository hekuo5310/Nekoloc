/// 账号偏好（user_option）。字段与取值对齐参考客户端 UserPreferencesRepository。

enum LikeNotificationFrequency {
  always(0, '总是'),
  firstTimeAndDaily(1, '首次及每天一次'),
  firstTime(2, '仅首次'),
  never(3, '从不');

  final int value;
  final String label;
  const LikeNotificationFrequency(this.value, this.label);

  static LikeNotificationFrequency from(int? v) =>
      values.firstWhere((e) => e.value == v, orElse: () => always);
}

enum NewTopicDuration {
  lastVisit(-1, '上次访问以来'),
  oneDay(1440, '一天内'),
  twoDays(2880, '两天内'),
  oneWeek(10080, '一周内'),
  twoWeeks(20160, '两周内');

  final int minutes;
  final String label;
  const NewTopicDuration(this.minutes, this.label);

  static NewTopicDuration from(int? v) =>
      values.firstWhere((e) => e.minutes == v, orElse: () => lastVisit);
}

enum EmailLevel {
  always(0, '总是'),
  onlyWhenAway(1, '仅不在线时'),
  never(2, '从不');

  final int value;
  final String label;
  const EmailLevel(this.value, this.label);

  static EmailLevel from(int? v) => values.firstWhere((e) => e.value == v, orElse: () => onlyWhenAway);
}

enum PreviousRepliesLevel {
  always(0, '总是'),
  unlessEmailed(1, '未通过邮件通知时'),
  never(2, '从不');

  final int value;
  final String label;
  const PreviousRepliesLevel(this.value, this.label);

  static PreviousRepliesLevel from(int? v) =>
      values.firstWhere((e) => e.value == v, orElse: () => always);
}

/// 从 user_option 中读取的偏好快照。缺失的字段使用站点默认值。
class UserPreferences {
  final LikeNotificationFrequency likeFrequency;
  final NewTopicDuration newTopicDuration;
  final bool trackOnReply;
  final EmailLevel emailLevel;
  final EmailLevel emailMessagesLevel;
  final PreviousRepliesLevel emailPreviousReplies;
  final bool emailDigests;
  final bool hideProfile;
  final bool hidePresence;

  const UserPreferences({
    this.likeFrequency = LikeNotificationFrequency.always,
    this.newTopicDuration = NewTopicDuration.lastVisit,
    this.trackOnReply = false,
    this.emailLevel = EmailLevel.onlyWhenAway,
    this.emailMessagesLevel = EmailLevel.always,
    this.emailPreviousReplies = PreviousRepliesLevel.always,
    this.emailDigests = false,
    this.hideProfile = false,
    this.hidePresence = false,
  });

  factory UserPreferences.fromOption(Map option) => UserPreferences(
        likeFrequency: LikeNotificationFrequency.from(_i(option['like_notification_frequency'])),
        newTopicDuration: NewTopicDuration.from(_i(option['new_topic_duration_minutes'])),
        // 站点用 2 表示“回复时自动关注”，1 表示不关注。
        trackOnReply: _i(option['notification_level_when_replying']) == 2,
        emailLevel: EmailLevel.from(_i(option['email_level'])),
        emailMessagesLevel: EmailLevel.from(_i(option['email_messages_level'])),
        emailPreviousReplies: PreviousRepliesLevel.from(_i(option['email_previous_replies'])),
        emailDigests: option['email_digests'] == true,
        hideProfile: option['hide_profile'] == true,
        hidePresence: option['hide_presence'] == true,
      );

  static int? _i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v');
}
