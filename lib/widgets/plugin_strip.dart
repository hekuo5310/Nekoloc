import 'package:flutter/material.dart';

import '../models.dart';
import '../plugins.dart';

/// 楼层下方的插件信息与操作：打赏总额、本楼领取的红包、抽奖状态，以及打赏 / 参与抽奖入口。
/// 没有任何插件数据、也没有可用操作时不占位。
class PostPluginStrip extends StatelessWidget {
  final Post post;

  /// 非 null 时显示“打赏”入口（自己的帖子、未登录时传 null）。
  final VoidCallback? onReward;

  /// 非 null 时抽奖卡可点击参与（抽奖已结束或未登录时传 null）。
  final VoidCallback? onLottery;

  const PostPluginStrip({
    super.key,
    required this.post,
    this.onReward,
    this.onLottery,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    final reward = rewardTotal(post.rewards);
    if (reward > 0) {
      chips.add(_chip(Icons.volunteer_activism_outlined, '打赏 $reward'));
    }

    final claimed = claimedPointsForPost(post.redEnvelopeClaim, post.id);
    if (claimed != null) {
      chips.add(_chip(Icons.redeem_outlined, '领取红包 +$claimed'));
    }

    final lottery = post.lottery;
    if (lottery != null) {
      final state = lottery.isOpen ? '进行中' : '已结束';
      final cap = lottery.participantCap;
      final people = cap == null
          ? '${lottery.participantsCount} 人参与'
          : '${lottery.participantsCount}/$cap 人参与';
      final mine = lottery.isParticipating ? ' · 我已参与' : '';
      chips.add(_chip(
        Icons.casino_outlined,
        '抽奖「${lottery.title}」· $state · $people$mine',
        onTap: lottery.isOpen ? onLottery : null,
      ));
    }

    if (onReward != null) {
      chips.add(ActionChip(
        avatar: const Icon(Icons.card_giftcard_outlined, size: 16),
        label: const Text('打赏', style: TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onPressed: onReward,
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }

  Widget _chip(IconData icon, String text, {VoidCallback? onTap}) => ActionChip(
        avatar: Icon(icon, size: 16),
        label: Text(text, style: const TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onPressed: onTap,
      );
}

/// 话题顶部的红包横幅：总积分、个数，以及剩余可领数量或“已领完”。
class TopicRedEnvelopeBanner extends StatelessWidget {
  final TopicRedEnvelope envelope;

  const TopicRedEnvelopeBanner({super.key, required this.envelope});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.redeem, color: scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '红包 ${envelope.totalPoints} 积分 · ${envelope.totalCount} 个',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  envelope.exhausted ? '已领完' : '剩余 ${envelope.availableCount} 个可领',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
