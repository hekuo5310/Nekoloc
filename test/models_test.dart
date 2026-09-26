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
      'details': {'notification_level': 3},
      'post_stream': {'posts': [
        {'id': 22, 'post_number': 1, 'username': 'example', 'can_edit': true},
      ], 'stream': [22]},
    });
    expect(topic.notificationLevel, 3);
    expect(topic.posts.single.canEdit, isTrue);
  });

  test('exact post bookmark takes precedence over another floor', () {
    final bookmarks = [
      BookmarkItem(id: 1, topicId: 10, postId: 23, title: '', excerpt: ''),
      BookmarkItem(id: 2, topicId: 10, postId: 22, title: '', excerpt: ''),
    ];
    expect(bookmarkIdForPost(bookmarks, 22, 10), 2);
    expect(bookmarkIdForPost(bookmarks, 24, 10), isNull);
  });

  test('topic bookmark is used only if no exact post bookmark exists', () {
    final bookmarks = [
      BookmarkItem(id: 1, topicId: 10, postId: null, title: '', excerpt: ''),
      BookmarkItem(id: 2, topicId: 10, postId: 22, title: '', excerpt: ''),
    ];
    expect(bookmarkIdForPost(bookmarks, 22, 10), 2);
    expect(bookmarkIdForPost(bookmarks, 24, 10), 1);
  });
}
