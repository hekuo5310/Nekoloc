import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/chat_models.dart';

ChatMessage _m(int id, String text) => ChatMessage.fromJson({'id': id, 'message': text});

void main() {
  test('私聊频道按参与者显示标题', () {
    final c = ChatChannel.fromJson({
      'id': 4,
      'title': null,
      'chatable_type': 'DirectMessage',
      'chatable': {
        'users': [
          {'id': 1, 'username': 'ada'},
          {'id': 2, 'username': 'bob'},
        ],
      },
      'last_message': {'excerpt': '你好'},
    });
    expect(c.isDirect, isTrue);
    expect(c.title, 'ada、bob');
    expect(c.lastExcerpt, '你好');
  });

  test('公开频道优先使用 unicode_title', () {
    final c = ChatChannel.fromJson({'id': 5, 'title': 'general', 'unicode_title': '综合'});
    expect(c.isDirect, isFalse);
    expect(c.title, '综合');
  });

  test('合并消息：按 id 升序并去重，轮询与发送返回同一条时只保留一份', () {
    final merged = mergeChatMessages(
      [_m(3, 'c'), _m(1, 'a')],
      [_m(2, 'b'), _m(3, 'c')],
    );
    expect(merged.map((m) => m.id), [1, 2, 3]);
  });

  test('已删除的消息带标记', () {
    final m = ChatMessage.fromJson({'id': 9, 'message': 'x', 'deleted_at': '2026-01-01'});
    expect(m.deleted, isTrue);
  });
}
