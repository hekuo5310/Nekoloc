/// 发帖时附加的插件内容草稿：红包与抽奖。
///
/// 校验口径对齐参考客户端 LotteryDraft / RedEnvelopeDraft：
/// - 抽奖的 maxParticipants 为 0 表示不限人数，提交时以 1000000 哨兵值发送；
/// - 抽奖的开奖时间不是相对天数，而是提交时刻算出的绝对时间（服务端只接受绝对时间）；
/// - 红包和抽奖都是在话题或楼层创建之后，再发第二个请求挂上去的。
library;

const int lotteryMaxDrawDays = 30;
const int lotteryMinTickets = 1;
const int lotteryMaxTickets = 10;
const int lotteryNoCapSentinel = 1000000;

class RedEnvelopeDraft {
  final int totalPoints;
  final int totalCount;

  const RedEnvelopeDraft({this.totalPoints = 100, this.totalCount = 10});

  String? get error {
    if (totalPoints <= 0) return '红包积分需大于 0';
    if (totalCount < 1) return '红包个数至少为 1';
    if (totalCount > totalPoints) return '每个红包至少 1 积分，个数不能超过积分';
    return null;
  }
}

class LotteryDraft {
  final String title;
  final String prize;
  final int minParticipants;

  /// 0 表示不限人数。
  final int maxParticipants;
  final int minTicketsPerUser;
  final int maxTicketsPerUser;
  final int drawDays;

  const LotteryDraft({
    this.title = '',
    this.prize = '',
    this.minParticipants = 5,
    this.maxParticipants = 0,
    this.minTicketsPerUser = lotteryMinTickets,
    this.maxTicketsPerUser = lotteryMaxTickets,
    this.drawDays = 3,
  });

  String? get error {
    if (title.trim().isEmpty) return '请填写抽奖标题';
    if (prize.trim().isEmpty) return '请填写奖品';
    if (minParticipants < 1) return '最少参与人数不能小于 1';
    if (maxParticipants > 0 && maxParticipants <= minParticipants) {
      return '最多参与人数要大于最少参与人数';
    }
    if (minTicketsPerUser > maxTicketsPerUser) return '每人最少票数不能大于最多票数';
    if (drawDays < 1 || drawDays > lotteryMaxDrawDays) {
      return '开奖时间需在 1–$lotteryMaxDrawDays 天之间';
    }
    return null;
  }

  /// 提交给 `POST /lottery` 的载荷。[now] 注入是为了测试；开奖时间按提交时刻计算。
  Map<String, dynamic> toPayload({required int postId, required DateTime now}) => {
        'post_id': postId,
        'title': title.trim(),
        'min_participants': minParticipants,
        'max_participants': maxParticipants <= 0 ? lotteryNoCapSentinel : maxParticipants,
        'min_tickets_per_user': minTicketsPerUser,
        'max_tickets_per_user': maxTicketsPerUser,
        'min_trust_level': 1,
        'draw_at': now.toUtc().add(Duration(days: drawDays)).toIso8601String(),
        'levels': [
          {'name': '奖品', 'prize': prize.trim(), 'quantity': 1},
        ],
      };
}
