import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import '../polls.dart';

class PollCard extends StatefulWidget {
  final PostPoll poll;
  final List<String> myVotes;
  final bool busy;
  final bool loggedIn;
  final ValueChanged<List<String>> onVote;
  final VoidCallback onRemove;
  const PollCard({super.key, required this.poll, required this.myVotes,
    required this.busy, required this.loggedIn, required this.onVote,
    required this.onRemove});
  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  late Set<String> _selected;
  bool _edited = false;
  @override
  void initState() { super.initState(); _reset(); }
  void _reset() { _selected = widget.myVotes.toSet(); _edited = false; }
  @override
  void didUpdateWidget(covariant PollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.poll.name != widget.poll.name ||
        !listEquals(oldWidget.myVotes, widget.myVotes) ||
        (oldWidget.busy && !widget.busy)) _reset();
  }

  @override
  Widget build(BuildContext context) {
    final poll = widget.poll;
    final enabled = poll.canVote && widget.loggedIn && !widget.busy;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        HtmlWidget(poll.title),
        if (poll.isClosed) const Text('投票已结束'),
        if (poll.isMultiple) Text('可选 ${poll.minimum}–${poll.maximum} 项'),
        if (poll.type != 'regular' && !poll.isMultiple)
          const Text('此投票类型请在网页版参与'),
        for (final option in poll.options)
          InkWell(
            onTap: !enabled ? null : () {
              if (!poll.isMultiple) {
                widget.onVote([option.id]);
              } else {
                setState(() {
                  if (_selected.contains(option.id)) {
                    _selected.remove(option.id);
                  } else if (_selected.length < poll.maximum) {
                    _selected.add(option.id);
                  }
                  _edited = true;
                });
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Icon(_selected.contains(option.id)
                  ? (poll.isMultiple ? Icons.check_box : Icons.radio_button_checked)
                  : (poll.isMultiple ? Icons.check_box_outline_blank : Icons.radio_button_unchecked),
                  color: enabled ? Theme.of(context).colorScheme.primary : null),
                const SizedBox(width: 8),
                Expanded(child: HtmlWidget(option.html)),
                if (option.votes != null) Text('${option.votes} 票'),
              ]),
            ),
          ),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (poll.voters != null) Text('${poll.voters} 人参与'),
          if (!widget.loggedIn && poll.canVote) const Text('登录后可投票'),
          if (widget.busy) const SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
          if (poll.isMultiple && poll.canVote && widget.loggedIn)
            TextButton(onPressed: enabled && _edited && poll.validSelection(_selected)
              ? () => widget.onVote(_selected.toList()) : null,
              child: const Text('提交投票')),
          if (widget.myVotes.isNotEmpty && poll.canVote && widget.loggedIn)
            TextButton(onPressed: enabled ? widget.onRemove : null,
              child: const Text('取消投票')),
        ]),
      ]),
    );
  }
}
