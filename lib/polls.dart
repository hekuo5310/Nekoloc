import 'models.dart';

class PollOption {
  final String id;
  final String html;
  // Missing counts mean the server has withheld the results.
  final int? votes;
  const PollOption({required this.id, required this.html, this.votes});
  factory PollOption.fromJson(Map json) => PollOption(
    id: json['id']?.toString() ?? '',
    html: json['html']?.toString() ?? '', votes: toInt(json['votes']),
  );
}

class PostPoll {
  final String name;
  final String type;
  final String status;
  final String title;
  final int? min;
  final int? max;
  final int? voters;
  final List<PollOption> options;
  const PostPoll({required this.name, required this.type, required this.status,
    required this.title, this.min, this.max, this.voters, required this.options});
  factory PostPoll.fromJson(Map json) => PostPoll(
    name: json['name']?.toString() ?? 'poll',
    type: json['type']?.toString() ?? 'regular',
    status: json['status']?.toString() ?? 'open',
    title: json['title']?.toString() ?? '投票',
    min: toInt(json['min']), max: toInt(json['max']), voters: toInt(json['voters']),
    options: ((json['options'] as List?) ?? []).whereType<Map>()
        .map(PollOption.fromJson).where((o) => o.id.isNotEmpty).toList(),
  );
  bool get isMultiple => type == 'multiple';
  bool get isClosed => status == 'closed';
  bool get canVote => !isClosed && (type == 'regular' || isMultiple);
  int get minimum => isMultiple ? (min ?? 1) : 1;
  int get maximum => isMultiple ? (max ?? options.length) : 1;
  bool validSelection(Set<String> ids) => ids.length >= minimum &&
      ids.length <= maximum && ids.every((id) => options.any((o) => o.id == id));
}

class PollVoteResult {
  final PostPoll? poll;
  final List<String>? vote;
  const PollVoteResult({this.poll, this.vote});
  factory PollVoteResult.fromJson(Map json) => PollVoteResult(
    poll: json['poll'] is Map ? PostPoll.fromJson(json['poll'] as Map) : null,
    vote: json['vote'] is List ? (json['vote'] as List).whereType<String>().toList() : null,
  );
}
