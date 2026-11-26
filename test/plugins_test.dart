import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/models.dart';
import 'package:nodeloc_app/plugins.dart';

void main() {
  topicEnvelopeTests();
  test('打赏总额不计系统扣减', () {
    final rewards = [
      const PostReward(amount: 10),
      const PostReward(amount: 5),
      const PostReward(amount: -20, isSystem: true),
    ];
    expect(rewardTotal(rewards), 15);
  });

  test('红包领取只在它指向的那一楼生效', () {
    final claim = RedEnvelopeClaim.fromJson({
      'id': 1, 'post_id': 943851, 'points_received': 16,
    });
    expect(claimedPointsForPost(claim, 943851), 16);
    // 同一用户的其他回复也会带上这条记录，但它们并没有领取。
    expect(claimedPointsForPost(claim, 943852), isNull);
    expect(claimedPointsForPost(null, 943851), isNull);
  });

  test('抽奖的 1000000 哨兵值还原为不限人数', () {
    final lottery = PostLottery.fromJson({
      'id': 9,
      'title': '中元节',
      'status': 'open',
      'max_participants': 1000000,
      'participants_count': 4,
      'levels': [
        {'id': 1, 'name': '一等奖', 'prize': '100 能量', 'quantity': 2},
      ],
    });
    expect(lottery.isOpen, isTrue);
    expect(lottery.participantCap, isNull);
    expect(lottery.prizes, ['100 能量']);
  });

  test('有限的人数上限保留', () {
    final lottery = PostLottery.fromJson({
      'id': 9, 'status': 'closed', 'max_participants': 50, 'participants_count': 3,
    });
    expect(lottery.isOpen, isFalse);
    expect(lottery.participantCap, 50);
  });

  test('Post 能解析插件字段，缺失时为空', () {
    final post = Post.fromJson({
      'id': 7,
      'post_number': 3,
      'username': 'ada',
      'cooked': '',
      'like_count': 0,
      'rewards': [
        {'amount': 8, 'username': 'bob'},
      ],
      'red_envelope_claim': {'post_id': 7, 'points_received': 3},
    });
    expect(rewardTotal(post.rewards), 8);
    expect(claimedPointsForPost(post.redEnvelopeClaim, post.id), 3);
    expect(post.lottery, isNull);

    final plain = Post.fromJson({
      'id': 8, 'username': 'ada', 'cooked': '', 'like_count': 0,
    });
    expect(plain.rewards, isEmpty);
    expect(plain.redEnvelopeClaim, isNull);
  });
}

void topicEnvelopeTests() {
  test('话题红包：已领完与剩余数量', () {
    final e = TopicRedEnvelope.fromJson({
      'total_points': 100, 'total_count': 10, 'available_count': 3, 'exhausted': false,
    });
    expect(e.totalPoints, 100);
    expect(e.availableCount, 3);
    expect(e.exhausted, isFalse);
    expect(TopicRedEnvelope.fromJson({'exhausted': true}).exhausted, isTrue);
  });
}
