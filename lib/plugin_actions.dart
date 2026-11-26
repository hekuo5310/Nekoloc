import 'package:flutter/material.dart';

import 'api/discourse_api.dart';
import 'api/friendly_error.dart';
import 'models.dart';
import 'plugins.dart';

/// 打赏对话框：输入积分与可选备注，确认后提交。成功返回 true。
Future<bool> showRewardDialog(BuildContext context, DiscourseApi api, Post post) async {
  final amountCtl = TextEditingController(text: '10');
  final noteCtl = TextEditingController();
  String? error;
  var busy = false;

  final sent = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text('打赏 @${post.username}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '积分'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtl,
              maxLength: 60,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final amount = int.tryParse(amountCtl.text.trim());
                    if (amount == null || amount <= 0) {
                      setLocal(() => error = '请输入大于 0 的整数');
                      return;
                    }
                    setLocal(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await api.giveReward(post.id, amount, note: noteCtl.text.trim());
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      setLocal(() {
                        busy = false;
                        error = friendlyError(e);
                      });
                    }
                  },
            child: const Text('打赏'),
          ),
        ],
      ),
    ),
  );
  return sent == true;
}

/// 参与抽奖对话框。成功返回服务端最新的抽奖状态，取消返回 null。
Future<PostLottery?> showLotteryDialog(
  BuildContext context,
  DiscourseApi api,
  PostLottery lottery, {
  int? postId,
}) async {
  final qtyCtl = TextEditingController(text: '${lottery.minTicketsPerUser}');
  var random = false;
  String? error;
  var busy = false;
  PostLottery? updated;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text('抽奖「${lottery.title}」'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('每人可购买 ${lottery.minTicketsPerUser}–${lottery.maxTicketsPerUser} 张票'),
            const SizedBox(height: 8),
            TextField(
              controller: qtyCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '票数'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('随机选择'),
              value: random,
              onChanged: busy ? null : (v) => setLocal(() => random = v),
            ),
            if (error != null)
              Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final qty = int.tryParse(qtyCtl.text.trim());
                    if (qty == null ||
                        qty < lottery.minTicketsPerUser ||
                        qty > lottery.maxTicketsPerUser) {
                      setLocal(() => error =
                          '票数需在 ${lottery.minTicketsPerUser}–${lottery.maxTicketsPerUser} 之间');
                      return;
                    }
                    setLocal(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      final next = await api.participateInLottery(lottery.id, qty, random: random, postId: postId);
                      updated = next;
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setLocal(() {
                        busy = false;
                        error = friendlyError(e);
                      });
                    }
                  },
            child: const Text('参与'),
          ),
        ],
      ),
    ),
  );
  return updated;
}
