import 'models.dart';

/// 屏蔽（忽略）用户的客户端过滤。
///
/// Discourse 的“忽略”只隐藏该用户在话题内的回复，不会从话题列表、搜索结果中移除
/// 其话题，所以名单必须在客户端生效。规则对齐参考客户端 NodeLoc Android：
/// - 话题：原作者（posters 第一位）被屏蔽时整条话题隐藏；
/// - 楼层：隐藏被屏蔽用户的回复，但保留一楼（主楼），与服务端的保留规则一致；
/// - 搜索：隐藏被屏蔽用户发出的帖子。
///
/// 名单只存在内存里（由 AppState 登录后从站点拉取），服务端才是真正的记录。

bool isTopicHidden(Topic topic, Map<int, UserBrief> users, Set<String> blocked) {
  if (blocked.isEmpty || topic.posters.isEmpty) return false;
  final name = users[topic.posters.first.userId]?.username;
  return name != null && blocked.contains(name);
}

extension BlockedTopicList on TopicListResult {
  TopicListResult withoutBlocked(Set<String> blocked) {
    if (blocked.isEmpty) return this;
    return TopicListResult(
      topics: topics.where((t) => !isTopicHidden(t, users, blocked)).toList(),
      users: users,
      hasMore: hasMore,
    );
  }
}

extension BlockedSearchResult on SearchResult {
  SearchResult withoutBlocked(Set<String> blocked) {
    if (blocked.isEmpty) return this;
    return SearchResult(
      items: items.where((p) => !blocked.contains(p.username)).toList(),
      hasMore: hasMore,
    );
  }
}

/// 楼层过滤：主楼永远保留，避免话题本身消失。
List<Post> visiblePosts(List<Post> posts, Set<String> blocked) {
  if (blocked.isEmpty) return posts;
  return posts.where((p) => p.postNumber == 1 || !blocked.contains(p.username)).toList();
}
