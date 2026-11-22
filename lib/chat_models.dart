/// 站点聊天（discourse-chat）的只读模型。
/// 站点的消息 JSON 字段较多，这里只保留展示所需字段，未知字段一律忽略。
library;

int _cint(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

class ChatUser {
  final int id;
  final String username;

  const ChatUser({required this.id, required this.username});

  factory ChatUser.fromJson(Map json) => ChatUser(
        id: _cint(json['id']),
        username: json['username']?.toString() ?? '',
      );
}

class ChatChannel {
  final int id;
  final String title;
  final bool isDirect;
  final String? lastExcerpt;

  const ChatChannel({
    required this.id,
    required this.title,
    required this.isDirect,
    this.lastExcerpt,
  });

  factory ChatChannel.fromJson(Map json) {
    final chatable = json['chatable'] is Map ? json['chatable'] as Map : const {};
    final users = (chatable['users'] as List?) ?? const [];
    final direct = json['chatable_type']?.toString() == 'DirectMessage' || users.isNotEmpty;
    final title = (json['unicode_title'] ?? json['title'])?.toString();
    final last = json['last_message'];
    return ChatChannel(
      id: _cint(json['id']),
      title: (title == null || title.isEmpty)
          ? users.whereType<Map>().map((u) => u['username']?.toString() ?? '').join('、')
          : title,
      isDirect: direct,
      lastExcerpt: last is Map ? last['excerpt']?.toString() : null,
    );
  }
}

class ChatMessage {
  final int id;
  final String text;
  final ChatUser? user;
  final DateTime? createdAt;
  final bool deleted;

  const ChatMessage({
    required this.id,
    required this.text,
    this.user,
    this.createdAt,
    this.deleted = false,
  });

  factory ChatMessage.fromJson(Map json) {
    final u = json['user'];
    return ChatMessage(
      id: _cint(json['id']),
      text: json['message']?.toString() ?? '',
      user: u is Map ? ChatUser.fromJson(u) : null,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      deleted: json['deleted_at'] != null,
    );
  }
}

/// 把消息按 id 升序排列，并去掉重复的 id（轮询与发送可能拿到同一条）。
List<ChatMessage> mergeChatMessages(List<ChatMessage> a, List<ChatMessage> b) {
  final byId = <int, ChatMessage>{};
  for (final m in [...a, ...b]) {
    byId[m.id] = m;
  }
  final list = byId.values.toList()..sort((x, y) => x.id.compareTo(y.id));
  return list;
}
