import 'dart:ui' show Color;
import 'polls.dart';
export 'polls.dart';

/// 通用安全取值
int? toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

DateTime? toDate(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s);
}

bool toBool(dynamic v) => v == true;

Color _hexColor(dynamic v, Color fallback) {
  var s = v?.toString();
  if (s == null || s.isEmpty) return fallback;
  s = s.replaceFirst('#', '');
  if (s.length == 3) {
    s = s.split('').map((c) => c + c).join();
  }
  if (s.length == 6) s = 'FF$s';
  final v2 = int.tryParse(s, radix: 16);
  if (v2 == null) return fallback;
  return Color(v2);
}

class SiteInfo {
  final String title;
  final String description;
  final String? logoUrl;
  SiteInfo({required this.title, required this.description, this.logoUrl});

  factory SiteInfo.fromJson(dynamic json) => SiteInfo(
        title: json['title']?.toString() ?? 'NodeLoc',
        description: json['description']?.toString() ?? '',
        logoUrl: (json['logo_small_url'] ?? json['logo_url'])?.toString(),
      );
}

class UserBrief {
  final int id;
  final String username;
  final String? name;
  final String? avatarTemplate;
  UserBrief({
    required this.id,
    required this.username,
    this.name,
    this.avatarTemplate,
  });

  factory UserBrief.fromJson(dynamic json) => UserBrief(
        id: toInt(json['id']) ?? 0,
        username: json['username']?.toString() ?? '',
        name: json['name']?.toString(),
        avatarTemplate: json['avatar_template']?.toString(),
      );
}

class TopicPoster {
  final int userId;
  final String description;
  final bool isLatest;
  TopicPoster({required this.userId, required this.description, this.isLatest = false});

  factory TopicPoster.fromJson(dynamic json) => TopicPoster(
        userId: toInt(json['user_id']) ?? 0,
        description: json['description']?.toString() ?? '',
        isLatest: json['extras']?.toString().contains('latest') ?? false,
      );
}

class Topic {
  final int id;
  final String title;
  final String? slug;
  final String? excerpt;
  final int postsCount;
  final int replyCount;
  final int likeCount;
  final int views;
  final int? categoryId;
  final DateTime? createdAt;
  final DateTime? lastPostedAt;
  final DateTime? bumpedAt;
  final bool pinned;
  final bool closed;
  final bool archived;
  final bool unseen;
  final List<TopicPoster> posters;

  Topic({
    required this.id,
    required this.title,
    this.slug,
    this.excerpt,
    required this.postsCount,
    required this.replyCount,
    required this.likeCount,
    required this.views,
    this.categoryId,
    this.createdAt,
    this.lastPostedAt,
    this.bumpedAt,
    this.pinned = false,
    this.closed = false,
    this.archived = false,
    this.unseen = false,
    this.posters = const [],
  });

  factory Topic.fromJson(dynamic json) => Topic(
        id: toInt(json['id']) ?? 0,
        title: (json['fancy_title'] ?? json['title'])?.toString() ?? '',
        slug: json['slug']?.toString(),
        excerpt: json['excerpt']?.toString(),
        postsCount: toInt(json['posts_count']) ?? 0,
        replyCount: toInt(json['reply_count']) ?? 0,
        likeCount: toInt(json['like_count']) ?? 0,
        views: toInt(json['views']) ?? 0,
        categoryId: toInt(json['category_id']),
        createdAt: toDate(json['created_at']),
        lastPostedAt: toDate(json['last_posted_at']),
        bumpedAt: toDate(json['bumped_at']),
        pinned: toBool(json['pinned']),
        closed: toBool(json['closed']),
        archived: toBool(json['archived']),
        unseen: toBool(json['unseen']),
        posters: ((json['posters'] as List?) ?? [])
            .map((e) => TopicPoster.fromJson(e))
            .toList(),
      );
}

class TopicListResult {
  final List<Topic> topics;
  final Map<int, UserBrief> users;
  final bool hasMore;
  TopicListResult({required this.topics, required this.users, required this.hasMore});

  factory TopicListResult.fromJson(dynamic json) {
    final tl = json['topic_list'] ?? const {};
    final users = <int, UserBrief>{};
    for (final u in (json['users'] as List?) ?? []) {
      final ub = UserBrief.fromJson(u);
      users[ub.id] = ub;
    }
    return TopicListResult(
      topics: ((tl['topics'] as List?) ?? []).map((e) => Topic.fromJson(e)).toList(),
      users: users,
      hasMore: tl['more_topics_url'] != null,
    );
  }
}

class Category {
  final int id;
  final String name;
  final Color color;
  final Color textColor;
  final String? slug;
  final int topicCount;
  final String descriptionExcerpt;
  final int? parentId;
  final int? position;
  final bool readRestricted;

  Category({
    required this.id,
    required this.name,
    required this.color,
    required this.textColor,
    this.slug,
    required this.topicCount,
    required this.descriptionExcerpt,
    this.parentId,
    this.position,
    this.readRestricted = false,
  });

  factory Category.fromJson(dynamic json) => Category(
        id: toInt(json['id']) ?? 0,
        name: json['name']?.toString() ?? '',
        color: _hexColor(json['color'], const Color(0xFF118A53)),
        textColor: _hexColor(json['text_color'], const Color(0xFFFFFFFF)),
        slug: json['slug']?.toString(),
        topicCount: toInt(json['topic_count']) ?? 0,
        descriptionExcerpt: _stripTags(json['description_excerpt']?.toString() ?? ''),
        parentId: toInt(json['parent_category_id']),
        position: toInt(json['position']),
        readRestricted: toBool(json['read_restricted']),
      );

  static String _stripTags(String s) => s
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .trim();
}

class ReactionInfo {
  final String id;
  final int count;
  ReactionInfo({required this.id, required this.count});
  factory ReactionInfo.fromJson(dynamic json) => ReactionInfo(
    id: json['id']?.toString() ?? '',
    count: toInt(json['count']) ?? 0,
  );
}

/// 举报理由由站点提供；管理员可以添加或调整理由及其顺序。
class PostFlagReason {
  final int id;
  final String name;
  final bool requireMessage;
  final int position;

  PostFlagReason({required this.id, required this.name,
      required this.requireMessage, required this.position});

  static PostFlagReason? fromJson(dynamic value, {String? username}) {
    if (value is! Map) return null;
    final id = toInt(value['id']);
    final appliesTo = value['applies_to'];
    if (id == null || value['is_flag'] != true || value['enabled'] == false ||
        appliesTo is! List || !appliesTo.contains('Post')) return null;
    var name = (value['name'] ?? value['short_description'])?.toString() ?? '';
    if (name.contains('%{username}') && (username == null || username.isEmpty)) return null;
    name = name.replaceAll('%{username}', username ?? '').trim();
    if (name.isEmpty) return null;
    return PostFlagReason(id: id, name: name,
        requireMessage: value['require_message'] == true,
        position: toInt(value['position']) ?? 0);
  }
}

class Post {
  final int id;
  final int postNumber;
  final int? topicId;
  final String username;
  final String? name;
  final String? avatarTemplate;
  final String cooked;
  final DateTime? createdAt;
  final int likeCount;
  final bool likedByMe;
  final bool canEdit;
  final bool hidden;
  final int? replyToPostNumber;
  final bool bookmarked;
  final int? bookmarkId;
  final List<ReactionInfo> reactions;
  final String? currentUserReaction;
  final int reactionUsersCount;
  final int? voteScore;
  final String? voteDirection;
  final bool canVoteDown;
  final List<PostPoll> polls;
  final Map<String, List<String>> pollsVotes;

  Post({
    required this.id,
    required this.postNumber,
    this.topicId,
    required this.username,
    this.name,
    this.avatarTemplate,
    required this.cooked,
    this.createdAt,
    required this.likeCount,
    this.likedByMe = false,
    this.canEdit = false,
    this.hidden = false,
    this.replyToPostNumber,
    this.bookmarked = false,
    this.bookmarkId,
    this.reactions = const [],
    this.currentUserReaction,
    this.reactionUsersCount = 0,
    this.voteScore,
    this.voteDirection,
    this.canVoteDown = false,
    this.polls = const [],
    this.pollsVotes = const {},
  });

  factory Post.fromJson(dynamic json) {
    var likeCount = toInt(json['like_count']) ?? 0;
    var liked = toBool(json['acted']);
    for (final a in (json['actions_summary'] as List?) ?? []) {
      if (toInt(a['id']) == 2) {
        likeCount = toInt(a['count']) ?? likeCount;
        liked = toBool(a['acted']) || liked;
      }
    }
    return Post(
      id: toInt(json['id']) ?? 0,
      postNumber: toInt(json['post_number']) ?? 1,
      topicId: toInt(json['topic_id']),
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString(),
      avatarTemplate: json['avatar_template']?.toString(),
      cooked: json['cooked']?.toString() ?? '',
      createdAt: toDate(json['created_at']),
      likeCount: likeCount,
      likedByMe: liked,
      canEdit: toBool(json['can_edit']),
      hidden: toBool(json['hidden']),
      replyToPostNumber: toInt(json['reply_to_post_number']),
      bookmarked: toBool(json['bookmarked']),
      bookmarkId: toInt(json['bookmark_id']),
      reactions: ((json['reactions'] as List?) ?? [])
          .map((e) => ReactionInfo.fromJson(e))
          .toList(),
      currentUserReaction: json['current_user_reaction']?.toString(),
      reactionUsersCount: toInt(json['reaction_users_count']) ?? 0,
      voteScore: toInt(json['vote_score']),
      voteDirection: json['vote_direction']?.toString(),
      canVoteDown: toBool(json['can_vote_down']),
      polls: ((json['polls'] as List?) ?? [])
          .whereType<Map>().map(PostPoll.fromJson).toList(),
      pollsVotes: {
        for (final entry in ((json['polls_votes'] as Map?) ?? {}).entries)
          if (entry.value is List)
            entry.key.toString(): (entry.value as List).whereType<String>().toList(),
      },
    );
  }

  Post copyWith({
    int? likeCount,
    bool? likedByMe,
    bool? bookmarked,
    int? bookmarkId,
    List<ReactionInfo>? reactions,
    String? currentUserReaction,
    int? reactionUsersCount,
    int? voteScore,
    String? voteDirection,
    bool? canVoteDown,
    List<PostPoll>? polls,
    Map<String, List<String>>? pollsVotes,
    bool clearBookmarkId = false,
  }) => Post(
        id: id,
        postNumber: postNumber,
        topicId: topicId,
        username: username,
        name: name,
        avatarTemplate: avatarTemplate,
        cooked: cooked,
        createdAt: createdAt,
        likeCount: likeCount ?? this.likeCount,
        likedByMe: likedByMe ?? this.likedByMe,
        canEdit: canEdit,
        hidden: hidden,
        replyToPostNumber: replyToPostNumber,
        bookmarked: bookmarked ?? this.bookmarked,
        bookmarkId: clearBookmarkId ? null : bookmarkId ?? this.bookmarkId,
        reactions: reactions ?? this.reactions,
        currentUserReaction: currentUserReaction ?? this.currentUserReaction,
        reactionUsersCount: reactionUsersCount ?? this.reactionUsersCount,
        voteScore: voteScore ?? this.voteScore,
        voteDirection: voteDirection ?? this.voteDirection,
        canVoteDown: canVoteDown ?? this.canVoteDown,
        polls: polls ?? this.polls,
        pollsVotes: pollsVotes ?? this.pollsVotes,
      );
}

class TopicDetail {
  final int id;
  final String title;
  final String? slug;
  final int postsCount;
  final int? categoryId;
  final int views;
  final int likeCount;
  final bool closed;
  final bool archived;
  final int? notificationLevel;
  final DateTime? createdAt;
  final List<Post> posts;
  final List<int> stream;
  final List<String> tags;

  TopicDetail({
    required this.id,
    required this.title,
    this.slug,
    required this.postsCount,
    this.categoryId,
    required this.views,
    required this.likeCount,
    required this.closed,
    required this.archived,
    this.notificationLevel,
    this.createdAt,
    required this.posts,
    required this.stream,
    this.tags = const [],
  });

  factory TopicDetail.fromJson(dynamic json) {
    final ps = json['post_stream'] ?? const {};
    return TopicDetail(
      id: toInt(json['id']) ?? 0,
      title: (json['fancy_title'] ?? json['title'])?.toString() ?? '',
      slug: json['slug']?.toString(),
      postsCount: toInt(json['posts_count']) ?? 0,
      categoryId: toInt(json['category_id']),
      views: toInt(json['views']) ?? 0,
      likeCount: toInt(json['like_count']) ?? 0,
      closed: toBool(json['closed']),
      archived: toBool(json['archived']),
      notificationLevel: toInt((json['details'] as Map?)?['notification_level']),
      createdAt: toDate(json['created_at']),
      posts: ((ps['posts'] as List?) ?? []).map((e) => Post.fromJson(e)).toList(),
      stream: ((ps['stream'] as List?) ?? []).map((e) => toInt(e) ?? 0).toList(),
      tags: ((json['tags'] as List?) ?? []).whereType<String>().toList(),
    );
  }
}

class NotificationItem {
  final int id;
  final int type;
  final bool read;
  final DateTime? createdAt;
  final int? postNumber;
  final int? topicId;
  final String topicTitle;
  final String displayUsername;
  final String? slug;

  NotificationItem({
    required this.id,
    required this.type,
    required this.read,
    this.createdAt,
    this.postNumber,
    this.topicId,
    required this.topicTitle,
    required this.displayUsername,
    this.slug,
  });

  factory NotificationItem.fromJson(dynamic json) {
    final data = json['data'] ?? const {};
    return NotificationItem(
      id: toInt(json['id']) ?? 0,
      type: toInt(json['notification_type']) ?? 0,
      read: toBool(json['read']),
      createdAt: toDate(json['created_at']),
      postNumber: toInt(json['post_number']),
      topicId: toInt(json['topic_id']),
      topicTitle: (json['fancy_title'] ?? data['topic_title'])?.toString() ?? '',
      displayUsername: (data['display_username'] ??
              data['original_username'] ??
              json['display_username'])
          ?.toString() ?? '',
      slug: json['slug']?.toString(),
    );
  }
}

class CurrentUser {
  final int id;
  final String username;
  final String? name;
  final String? avatarTemplate;
  final int unreadNotifications;
  final int unreadHighPriority;
  final bool admin;
  final int unreadPrivateMessages;

  CurrentUser({
    required this.id,
    required this.username,
    this.name,
    this.avatarTemplate,
    this.unreadNotifications = 0,
    this.unreadHighPriority = 0,
    this.admin = false,
    this.unreadPrivateMessages = 0,
  });

  factory CurrentUser.fromJson(dynamic json) => CurrentUser(
        id: toInt(json['id']) ?? 0,
        username: json['username']?.toString() ?? '',
        name: json['name']?.toString(),
        avatarTemplate: json['avatar_template']?.toString(),
        unreadNotifications: toInt(json['unread_notifications']) ?? 0,
        unreadHighPriority: toInt(json['unread_high_priority_notifications']) ?? 0,
        admin: toBool(json['admin']),
        unreadPrivateMessages: toInt(json['unread_private_messages']) ?? 0,
      );

  int get totalUnread => unreadNotifications + unreadHighPriority;
}

class UserProfile {
  final String username;
  final String? name;
  final String? avatarTemplate;
  final String bioCooked;
  final int postCount;
  final int badgeCount;
  final int? topicCount;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final String? location;
  final String? website;
  final bool canFollow;
  final bool isFollowed;
  final int? totalFollowers;
  final List<String> ignoredUsernames;
  final bool canIgnoreUsers;

  UserProfile({
    required this.username,
    this.name,
    this.avatarTemplate,
    required this.bioCooked,
    required this.postCount,
    required this.badgeCount,
    this.topicCount,
    this.createdAt,
    this.lastSeenAt,
    this.location,
    this.website,
    this.canFollow = false,
    this.isFollowed = false,
    this.totalFollowers,
    this.ignoredUsernames = const [],
    this.canIgnoreUsers = false,
  });

  factory UserProfile.fromJson(dynamic json) => UserProfile(
        username: json['username']?.toString() ?? '',
        name: json['name']?.toString(),
        avatarTemplate: json['avatar_template']?.toString(),
        bioCooked: json['bio_cooked']?.toString() ?? '',
        postCount: toInt(json['post_count']) ?? 0,
        badgeCount: toInt(json['badge_count']) ?? 0,
        topicCount: toInt(json['topic_count']),
        createdAt: toDate(json['created_at']),
        lastSeenAt: toDate(json['last_seen_at']),
        location: json['location']?.toString(),
        website: json['website']?.toString(),
        canFollow: toBool(json['can_follow']),
        isFollowed: toBool(json['is_followed']),
        totalFollowers: toInt(json['total_followers']),
        ignoredUsernames: ((json['ignored_usernames'] as List?) ?? [])
            .whereType<String>().toList(),
        canIgnoreUsers: toBool(json['can_ignore_users']),
      );
}

class SearchPostItem {
  final int id;
  final int topicId;
  final String topicTitle;
  final String blurb;
  final String username;
  final String? avatarTemplate;
  final int postNumber;
  final DateTime? createdAt;

  SearchPostItem({
    this.id = 0,
    required this.topicId,
    required this.topicTitle,
    required this.blurb,
    required this.username,
    this.avatarTemplate,
    required this.postNumber,
    this.createdAt,
  });
}

class SearchResult {
  final List<SearchPostItem> items;
  final bool hasMore;
  SearchResult({required this.items, this.hasMore = false});

  factory SearchResult.fromJson(dynamic json) {
    final titles = <int, String>{};
    for (final t in (json['topics'] as List?) ?? []) {
      final id = toInt(t['id']) ?? 0;
      titles[id] = (t['fancy_title'] ?? t['title'])?.toString() ?? '';
    }
    final items = <SearchPostItem>[];
    for (final p in (json['posts'] as List?) ?? []) {
      final tid = toInt(p['topic_id']) ?? 0;
      var title = titles[tid] ?? p['topic_title_headline']?.toString() ?? '';
      title = title
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll('&amp;', '&')
          .replaceAll('&#39;', "'")
          .replaceAll('&quot;', '"');
      items.add(SearchPostItem(
        id: toInt(p['id']) ?? 0,
        topicId: tid,
        topicTitle: title,
        blurb: p['blurb']?.toString() ?? '',
        username: p['username']?.toString() ?? '',
        avatarTemplate: p['avatar_template']?.toString(),
        postNumber: toInt(p['post_number']) ?? 1,
        createdAt: toDate(p['created_at']),
      ));
    }
    return SearchResult(items: items,
      hasMore: toBool((json['grouped_search_result'] as Map?)?['more_full_page_results']));
  }
}

class BookmarkItem {
  final int id;
  final int? topicId;
  final int? postId;
  final String title;
  final String excerpt;
  final DateTime? createdAt;
  final String? username;

  BookmarkItem({
    required this.id,
    this.topicId,
    this.postId,
    required this.title,
    required this.excerpt,
    this.createdAt,
    this.username,
  });

  factory BookmarkItem.fromJson(dynamic json) {
    final user = json['user'];
    final type = json['bookmarkable_type']?.toString();
    return BookmarkItem(
      id: toInt(json['id']) ?? 0,
      topicId: toInt(json['topic_id']),
      postId: type == 'Topic' ? null : toInt(json['bookmarkable_id']),
      title: (json['fancy_title'] ?? json['title'])?.toString() ?? '',
      excerpt: json['excerpt']?.toString() ?? '',
      createdAt: toDate(json['created_at']),
      username: user is Map ? user['username']?.toString() : null,
    );
  }
}

/// Find the bookmark for a post without selecting a different floor's bookmark.
int? bookmarkIdForPost(List<BookmarkItem> bookmarks, int postId, int topicId,
    {bool allowTopicBookmark = true}) {
  for (final bookmark in bookmarks) {
    if (bookmark.postId == postId) return bookmark.id;
  }
  for (final bookmark in bookmarks) {
    if (allowTopicBookmark && bookmark.postId == null && bookmark.topicId == topicId) {
      return bookmark.id;
    }
  }
  return null;
}
