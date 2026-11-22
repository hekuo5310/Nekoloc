import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/models.dart';
import 'package:nodeloc_app/push_watch.dart';

NotificationItem _n(int id, int type, {bool read = false}) => NotificationItem.fromJson({
      'id': id,
      'notification_type': type,
      'read': read,
      'data': {'display_username': 'bob', 'topic_title': 't$id'},
    });

void main() {
  test('第一次拉取只设基线，不提醒', () {
    final plan = planPushAlerts(
      [_n(10, 2), _n(11, 5)],
      const PushWatchState(),
      const PushSettings(),
    );
    expect(plan.toAlert, isEmpty);
    expect(plan.next.baselineDone, isTrue);
    expect(plan.next.watermark, 11);
  });

  test('基线之后只提醒水位线之上、未读、类别开启的通知', () {
    final plan = planPushAlerts(
      [_n(9, 2), _n(10, 2), _n(11, 2, read: true), _n(12, 5), _n(13, 6)],
      const PushWatchState(watermark: 10, baselineDone: true),
      const PushSettings(likes: false),
    );
    expect(plan.toAlert.map((n) => n.id), [13]);
    expect(plan.next.watermark, 13);
  });

  test('被静音的类别也推进水位线，重新打开不会补发', () {
    final muted = planPushAlerts(
      [_n(20, 5)],
      const PushWatchState(watermark: 10, baselineDone: true),
      const PushSettings(likes: false),
    );
    expect(muted.toAlert, isEmpty);
    expect(muted.next.watermark, 20);

    final reopened = planPushAlerts(
      [_n(20, 5)],
      muted.next,
      const PushSettings(),
    );
    expect(reopened.toAlert, isEmpty);
  });

  test('一次最多提醒最近的 5 条', () {
    final items = [for (var i = 1; i <= 8; i++) _n(100 + i, 2)];
    final plan = planPushAlerts(
      items,
      const PushWatchState(watermark: 100, baselineDone: true),
      const PushSettings(),
    );
    expect(plan.toAlert.length, 5);
    expect(plan.toAlert.first.id, 104);
    expect(plan.toAlert.last.id, 108);
  });

  test('类型编号映射到类别', () {
    expect(pushCategoryFor(2), PushCategory.replies);
    expect(pushCategoryFor(5), PushCategory.likes);
    expect(pushCategoryFor(6), PushCategory.messages);
    expect(pushCategoryFor(12), PushCategory.system);
  });
}
