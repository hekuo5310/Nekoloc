import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/blocked_users.dart';
import 'package:nodeloc_app/models.dart';

Post _post(int number, String username) => Post(
      id: number,
      postNumber: number,
      username: username,
      cooked: '',
      likeCount: 0,
    );

void main() {
  test('被屏蔽用户的回复被隐藏，但主楼保留', () {
    final posts = [_post(1, 'bob'), _post(2, 'bob'), _post(3, 'ada')];
    final visible = visiblePosts(posts, {'bob'});
    expect(visible.map((p) => p.postNumber), [1, 3]);
  });

  test('空名单不过滤', () {
    final posts = [_post(1, 'bob'), _post(2, 'ada')];
    expect(visiblePosts(posts, {}), same(posts));
  });

  test('以原作者（posters 第一位）判断话题是否隐藏', () {
    final users = {
      5: UserBrief(id: 5, username: 'bob'),
      6: UserBrief(id: 6, username: 'ada'),
    };
    final byBob = Topic(
      id: 1, title: 't', postsCount: 1, replyCount: 0, likeCount: 0, views: 0,
      posters: [TopicPoster(userId: 5, description: 'Original Poster')],
    );
    final byAdaReplied = Topic(
      id: 2, title: 't', postsCount: 2, replyCount: 1, likeCount: 0, views: 0,
      posters: [
        TopicPoster(userId: 6, description: 'Original Poster'),
        TopicPoster(userId: 5, description: 'Most Recent Poster'),
      ],
    );
    expect(isTopicHidden(byBob, users, {'bob'}), isTrue);
    // 只是回复过的话题不因此隐藏。
    expect(isTopicHidden(byAdaReplied, users, {'bob'}), isFalse);
  });

  test('话题列表过滤后保留分页信息', () {
    final users = {5: UserBrief(id: 5, username: 'bob')};
    final result = TopicListResult(
      topics: [
        Topic(
          id: 1, title: 't', postsCount: 1, replyCount: 0, likeCount: 0, views: 0,
          posters: [TopicPoster(userId: 5, description: '')],
        ),
      ],
      users: users,
      hasMore: true,
    );
    final filtered = result.withoutBlocked({'bob'});
    expect(filtered.topics, isEmpty);
    expect(filtered.hasMore, isTrue);
  });
}
