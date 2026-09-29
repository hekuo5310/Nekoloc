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

  test('topic tags preserve their display names', () {
    final topic = TopicDetail.fromJson({
      'id': 10, 'title': 'tagged', 'tags': ['Flutter', '讨论'],
      'post_stream': {'posts': [], 'stream': []},
    });
    expect(topic.tags, ['Flutter', '讨论']);
  });

  test('flag reasons come from enabled post reasons and require a note when configured', () {
    final entries = [
      {'id': 2, 'name': 'like', 'is_flag': false, 'applies_to': ['Post']},
      {'id': 3, 'name': 'chat', 'is_flag': true, 'applies_to': ['ChatMessage']},
      {'id': 4, 'name': 'custom', 'is_flag': true, 'enabled': false, 'applies_to': ['Post']},
      {'id': 5, 'name': '联系 @%{username}', 'is_flag': true,
       'applies_to': ['Post'], 'require_message': true, 'position': 2},
    ];
    expect(entries.map(PostFlagReason.fromJson).whereType<PostFlagReason>(), isEmpty);
    final parsed = entries.map((entry) => PostFlagReason.fromJson(entry, username: 'alice'))
        .whereType<PostFlagReason>().toList();
    expect(parsed, hasLength(1));
    expect(parsed.single.name, '联系 @alice');
    expect(parsed.single.requireMessage, isTrue);
    expect(parsed.single.position, 2);
  });

  test('voting fields are optional and preserve server permission', () {
    final post = Post.fromJson({
      'id': 12, 'post_number': 2, 'username': 'alice',
      'vote_score': -3, 'vote_direction': 'down', 'can_vote_down': true,
    });
    expect(post.voteScore, -3);
    expect(post.voteDirection, 'down');
    expect(post.canVoteDown, isTrue);
    expect(post.copyWith(voteScore: -2, voteDirection: 'none').voteDirection, 'none');
    expect(Post.fromJson({'id': 13, 'post_number': 3}).voteScore, isNull);
  });

  test('public profile uses server follow and ignore capabilities', () {
    final profile = UserProfile.fromJson({
      'username': 'alice', 'can_follow': true, 'is_followed': true,
      'total_followers': 42, 'ignored_usernames': ['bob'],
      'can_ignore_users': true,
    });
    expect(profile.canFollow, isTrue);
    expect(profile.isFollowed, isTrue);
    expect(profile.totalFollowers, 42);
    expect(profile.ignoredUsernames, ['bob']);
    expect(profile.canIgnoreUsers, isTrue);
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
