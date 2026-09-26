import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/models.dart';

void main() {
  test('Discourse category colors are hexadecimal', () {
    final category = Category.fromJson({
      'id': 1,
      'name': '讨论',
      'color': '1A8B55',
      'text_color': 'fff',
    });
    expect(category.color.value, 0xFF1A8B55);
    expect(category.textColor.value, 0xFFFFFFFF);
  });

  test('topic notification level is preserved when parsing', () {
    final topic = TopicDetail.fromJson({
      'id': 10,
      'title': 'test',
      'notification_level': 3,
      'post_stream': {'posts': [], 'stream': []},
    });
    expect(topic.notificationLevel, 3);
    expect(topic.posts, isEmpty);
  });
}
