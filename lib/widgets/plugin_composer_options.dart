import 'package:flutter/material.dart';

import '../plugin_drafts.dart';

/// 编辑器里附加的插件内容：红包、抽奖。开关关闭时对应草稿为 null。
class PluginDrafts {
  final RedEnvelopeDraft? envelope;
  final LotteryDraft? lottery;

  const PluginDrafts({this.envelope, this.lottery});

  /// 第一个校验失败的说明，全部通过则为 null。
  String? get error => envelope?.error ?? lottery?.error;
}

/// 发帖选项：红包与抽奖。每次输入变化都会回传最新的草稿。
class PluginComposerOptions extends StatefulWidget {
  final ValueChanged<PluginDrafts> onChanged;

  const PluginComposerOptions({super.key, required this.onChanged});

  @override
  State<PluginComposerOptions> createState() => _PluginComposerOptionsState();
}

class _PluginComposerOptionsState extends State<PluginComposerOptions> {
  bool _envelopeOn = false;
  bool _lotteryOn = false;

  final _points = TextEditingController(text: '100');
  final _count = TextEditingController(text: '10');
  final _lotTitle = TextEditingController();
  final _lotPrize = TextEditingController();
  final _lotMin = TextEditingController(text: '5');
  final _lotMax = TextEditingController(text: '0');
  final _lotDays = TextEditingController(text: '3');

  @override
  void dispose() {
    for (final c in [_points, _count, _lotTitle, _lotPrize, _lotMin, _lotMax, _lotDays]) {
      c.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c, int fallback) => int.tryParse(c.text.trim()) ?? fallback;

  void _emit() {
    widget.onChanged(PluginDrafts(
      envelope: _envelopeOn
          ? RedEnvelopeDraft(
              totalPoints: _int(_points, 0),
              totalCount: _int(_count, 0),
            )
          : null,
      lottery: _lotteryOn
          ? LotteryDraft(
              title: _lotTitle.text,
              prize: _lotPrize.text,
              minParticipants: _int(_lotMin, 0),
              maxParticipants: _int(_lotMax, 0),
              drawDays: _int(_lotDays, 0),
            )
          : null,
    ));
  }

  Widget _num(String label, TextEditingController c) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            onChanged: (_) => _emit(),
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('附加红包'),
          subtitle: const Text('发布后由站点发放给回复本话题的用户'),
          value: _envelopeOn,
          onChanged: (v) => setState(() {
            _envelopeOn = v;
            _emit();
          }),
        ),
        if (_envelopeOn)
          Row(children: [
            _num('积分', _points),
            _num('个数', _count),
          ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('附加抽奖'),
          subtitle: const Text('发布后用户可以购票参与'),
          value: _lotteryOn,
          onChanged: (v) => setState(() {
            _lotteryOn = v;
            _emit();
          }),
        ),
        if (_lotteryOn) ...[
          TextField(
            controller: _lotTitle,
            onChanged: (_) => _emit(),
            decoration: const InputDecoration(labelText: '抽奖标题', isDense: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _lotPrize,
            onChanged: (_) => _emit(),
            decoration: const InputDecoration(labelText: '奖品', isDense: true),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _num('最少人数', _lotMin),
            _num('最多人数（0=不限）', _lotMax),
            _num('开奖（天）', _lotDays),
          ]),
        ],
      ],
    );
  }
}
