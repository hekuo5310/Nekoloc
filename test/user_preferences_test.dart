import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/user_preferences.dart';

void main() {
  test('缺失字段使用站点默认值', () {
    final p = UserPreferences.fromOption({});
    expect(p.likeFrequency, LikeNotificationFrequency.always);
    expect(p.newTopicDuration, NewTopicDuration.lastVisit);
    expect(p.emailLevel, EmailLevel.onlyWhenAway);
    expect(p.trackOnReply, isFalse);
  });

  test('枚举值与站点数值一一对应，未知值回到默认', () {
    expect(LikeNotificationFrequency.from(3), LikeNotificationFrequency.never);
    expect(LikeNotificationFrequency.from(99), LikeNotificationFrequency.always);
    expect(NewTopicDuration.from(10080), NewTopicDuration.oneWeek);
    expect(EmailLevel.from(2), EmailLevel.never);
    expect(PreviousRepliesLevel.from(1), PreviousRepliesLevel.unlessEmailed);
  });

  test('回复时关注：只有 2 表示开启', () {
    expect(UserPreferences.fromOption({'notification_level_when_replying': 2}).trackOnReply, isTrue);
    expect(UserPreferences.fromOption({'notification_level_when_replying': 1}).trackOnReply, isFalse);
  });

  test('布尔偏好按 true 判断', () {
    final p = UserPreferences.fromOption({'hide_profile': true, 'hide_presence': false});
    expect(p.hideProfile, isTrue);
    expect(p.hidePresence, isFalse);
  });
}
