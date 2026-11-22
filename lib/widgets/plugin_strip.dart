import 'package:flutter/material.dart';

import '../models.dart';
import '../plugins.dart';

/// 楼层下方的插件徽章：打赏总额、本楼领取的红包、进行中的抽奖。
/// 没有任何插件数据时不占位。
class PostPluginStrip extends StatelessWidget {
  final Post post;

  const PostPluginStrip({super.key, required this.post});

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
      chips.add(_chip(Icons.casino_outlined, '抽奖「${lottery.title}」· $state · $people'));
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }

  Widget _chip(IconData icon, String text) => Chip(
        avatar: Icon(icon, size: 16),
        label: Text(text, style: const TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
}
