import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/plugin_drafts.dart';

void main() {
  test('红包：积分与个数的约束', () {
    expect(const RedEnvelopeDraft().error, isNull);
    expect(const RedEnvelopeDraft(totalPoints: 0).error, isNotNull);
    expect(const RedEnvelopeDraft(totalCount: 0).error, isNotNull);
    expect(const RedEnvelopeDraft(totalPoints: 5, totalCount: 6).error, isNotNull);
  });

  test('抽奖：校验与参考客户端一致', () {
    const ok = LotteryDraft(title: '中元节', prize: '100 能量');
    expect(ok.error, isNull);
    expect(const LotteryDraft(prize: 'x').error, '请填写抽奖标题');
    expect(const LotteryDraft(title: 't').error, '请填写奖品');
    expect(const LotteryDraft(title: 't', prize: 'x', minParticipants: 0).error, isNotNull);
    expect(
      const LotteryDraft(title: 't', prize: 'x', minParticipants: 5, maxParticipants: 5).error,
      isNotNull,
    );
    expect(const LotteryDraft(title: 't', prize: 'x', drawDays: 31).error, isNotNull);
  });

  test('抽奖载荷：不限人数用哨兵值，开奖时间为绝对时间', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    final payload = const LotteryDraft(title: '  中元节 ', prize: '100 能量', drawDays: 2)
        .toPayload(postId: 9, now: now);
    expect(payload['max_participants'], 1000000);
    expect(payload['title'], '中元节');
    expect(payload['draw_at'], '2026-01-03T12:00:00.000Z');
    expect(payload['levels'], [
      {'name': '奖品', 'prize': '100 能量', 'quantity': 1},
    ]);
  });
}
