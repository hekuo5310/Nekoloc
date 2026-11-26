/// 新版站点接口（`/api/v1`）的响应，整理成界面一直在用的模型。
///
/// 站点从 Discourse 换成了自建后端，字段和结构都变了。这里只做纯转换，没有任何网络请求，
/// 所以每个映射都能用从真实服务器抓取的样本（test/fixtures/api）做单元测试。
/// 规则对齐参考客户端 NodeLoc Android 的 LegacyMapping：旧模型的含义尽量填满，
/// 新接口没有给的数据留空，绝不编造。
library;

import '../account_models.dart';
import '../chat_models.dart';
import '../models.dart';
import '../plugins.dart';

int? _i(dynamic v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
String? _s(dynamic v) => v?.toString();
bool _b(dynamic v) => v == true || v == 1 || v == 'true';
Map _m(dynamic v) => v is Map ? v : const {};
List _l(dynamic v) => v is List ? v : const [];

/// 只有用户名、没有 id 的地方用的占位 id。
///
/// 旧的列表响应用 users 数组按 id 关联作者，新接口直接给用户名；
/// 用名字算出的稳定 id 让同一个响应里的关联继续成立，它也只在这里被比较。
/// 用 FNV-1a 而不是 String.hashCode：后者在不同运行之间不保证一致。
int syntheticUserId(String? username) {
  if (username == null || username.isEmpty) return 0;
  var hash = 0x811c9dc5;
  for (final unit in username.toLowerCase().codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return (hash & 0x3fffffff) | 0x40000000;
}

/// 作者 id：接口给了正数 id 就用它，否则（如系统账号的 -1）用名字算。
int authorIdOf(Map json) {
  final id = _i(json['author_id']);
  return id != null && id > 0 ? id : syntheticUserId(_s(json['author']));
}

String voteDirectionOf(int viewerVote) =>
    viewerVote > 0 ? 'up' : (viewerVote < 0 ? 'down' : 'none');

int voteValueOf(String direction) => switch (direction) {
      'up' => 1,
      'down' => -1,
      _ => 0,
    };

/// HTML 转纯文本（摘要、聊天文本用）。
String plainTextOf(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</p>\s*<p[^>]*>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&')
    .trim();

// ---------------------------------------------------------------- 话题列表

Topic topicFromSummary(Map t, {int? nodeId}) {
  final replies = _i(t['reply_count']) ?? 0;
  final author = _s(t['author']);
  return Topic(
    id: _i(t['id']) ?? 0,
    title: _s(t['title']) ?? '',
    excerpt: _s(t['excerpt']),
    postsCount: replies + 1,
    replyCount: replies,
    // 列表里没有点赞数，用首帖的投票分代替（站点的“赞”就是赞成票）。
    likeCount: _i(t['vote_score']) ?? 0,
    views: _i(t['views']) ?? 0,
    categoryId: nodeId,
    createdAt: toDate(t['created_at']),
    lastPostedAt: toDate(t['last_posted_at']),
    bumpedAt: toDate(t['last_posted_at'] ?? t['created_at']),
    pinned: _b(t['pinned']),
    closed: _b(t['closed']),
    unseen: (_i(t['unread_count']) ?? 0) > 0,
    posters: author == null
        ? const []
        : [TopicPoster(userId: authorIdOf(t), description: 'Original Poster')],
  );
}

UserBrief? authorOf(Map t) {
  final author = _s(t['author']);
  if (author == null || author.isEmpty) return null;
  return UserBrief(id: authorIdOf(t), username: author, avatarTemplate: _s(t['author_avatar']));
}

/// [nodeIdOf] 把节点别名换成节点 id（来自节点目录）。
TopicListResult topicListFrom(Map json, {int? Function(String? slug)? nodeIdOf}) {
  final topics = <Topic>[];
  final users = <int, UserBrief>{};
  for (final raw in _l(json['topics'])) {
    final t = _m(raw);
    topics.add(topicFromSummary(t, nodeId: nodeIdOf?.call(_s(t['node_slug']))));
    final author = authorOf(t);
    if (author != null) users[author.id] = author;
  }
  final hasMore = json['next_cursor'] != null || json['next_offset'] != null;
  return TopicListResult(topics: topics, users: users, hasMore: hasMore);
}

// ---------------------------------------------------------------- 楼层

/// [viewerId] 为当前用户 id（未登录为 null），[canModerate] 来自话题的 permissions.moderate。
Post postFrom(Map p, {int? topicId, int? viewerId, bool canModerate = false}) {
  final id = _i(p['id']) ?? 0;
  final up = _i(p['upvotes']) ?? 0;
  final down = _i(p['downvotes']) ?? 0;
  final viewerVote = _i(p['viewer_vote']) ?? 0;
  final deleted = _b(p['deleted']);
  final yours = viewerId != null && _i(p['author_id']) == viewerId;
  final bookmarked = _b(p['viewer_bookmarked']);
  return Post(
    id: id,
    postNumber: _i(p['post_number']) ?? 1,
    topicId: topicId ?? _i(p['topic_id']),
    username: _s(p['author']) ?? '',
    avatarTemplate: _s(p['author_avatar']),
    cooked: _s(p['html']) ?? '',
    createdAt: toDate(p['created_at']),
    likeCount: up,
    likedByMe: viewerVote > 0,
    canEdit: p['can_edit'] is bool ? p['can_edit'] as bool : ((yours || canModerate) && !deleted),
    // 线上实测：自己的回复和自己话题的一楼 can_delete 都是 false，删除请求却能成功
    // （删一楼即删整个话题，界面会先确认）。所以自己的帖子总是允许删除，其余以站点为准。
    canDelete: !deleted &&
        ((p['can_delete'] is bool && p['can_delete'] as bool) || yours ||
            (canModerate && p['can_delete'] is! bool && (_i(p['post_number']) ?? 1) > 1)),
    hidden: _b(p['hidden']) || deleted,
    replyToPostNumber: _i(p['reply_to_post_number']),
    bookmarked: bookmarked,
    // 收藏现在按帖子记录；取消收藏也用帖子 id，所以“收藏编号”就是帖子 id。
    bookmarkId: bookmarked ? id : null,
    voteScore: up - down,
    voteDirection: voteDirectionOf(viewerVote),
    canVoteDown: viewerId != null,
  );
}

/// 话题详情的第一页（或按楼层号往后的一页）。
TopicDetail topicDetailFrom(
  Map page, {
  int? nodeId,
  int? viewerId,
  List<Post>? posts,
  TopicRedEnvelope? redEnvelope,
  int? gapAfter,
  int? gapBefore,
}) {
  final topic = _m(page['topic']);
  final permissions = _m(page['permissions']);
  final canModerate = _b(permissions['moderate']);
  final id = _i(topic['id']) ?? 0;
  final list = posts ??
      _l(page['posts'])
          .map(_m)
          .where((p) => _s(p['kind']) != 'action')
          .map((p) => postFrom(p, topicId: id, viewerId: viewerId, canModerate: canModerate))
          .toList();
  final replies = _i(topic['reply_count']) ?? (list.length - 1).clamp(0, 1 << 30);
  final firstUpvotes = list.where((p) => p.postNumber == 1).map((p) => p.likeCount).firstOrNull;
  return TopicDetail(
    id: id,
    title: _s(topic['title']) ?? '',
    postsCount: replies + 1,
    categoryId: nodeId,
    views: _i(topic['views']) ?? 0,
    likeCount: firstUpvotes ?? (_i(topic['vote_score']) ?? 0),
    closed: _b(topic['closed']),
    archived: false,
    // 新接口只有“关注/普通/静音”，关注对应旧的 watching(3)。
    notificationLevel: _b(topic['viewer_following']) ? 3 : 1,
    createdAt: toDate(topic['created_at']),
    posts: list,
    stream: const [],
    tags: _l(topic['tags']).map((e) => e.toString()).toList(),
    redEnvelope: redEnvelope,
    nextAfter: _i(page['next_after']),
    canReply: permissions.containsKey('reply') ? _b(permissions['reply']) : !_b(topic['closed']),
    gapAfter: gapAfter,
    gapBefore: gapBefore,
  );
}

/// 嵌套视图的楼层，整理成旧的嵌套 JSON（id / post_number / username / cooked / children…），
/// 让嵌套页面现有的解析继续工作。
///
/// 新接口按先序列表给出每层的 depth，而不是嵌套结构：深度变大是上一条的子回复，
/// 变小则回到更早的祖先。
List<Map<String, dynamic>> threadTree(List posts) {
  final roots = <Map<String, dynamic>>[];
  final stack = <(int, Map<String, dynamic>)>[];
  final depths = posts.map((p) => _i(_m(p)['depth']) ?? 1);
  final base = depths.isEmpty ? 1 : depths.reduce((a, b) => a < b ? a : b);
  for (final raw in posts) {
    final p = _m(raw);
    if (_s(p['kind']) == 'action') continue;
    final depth = _i(p['depth']) ?? base;
    final node = <String, dynamic>{
      'id': _i(p['id']) ?? 0,
      'post_number': _i(p['post_number']) ?? 1,
      'username': _s(p['author']) ?? '',
      'avatar_template': _s(p['author_avatar']),
      'cooked': _s(p['html']) ?? '',
      'created_at': _s(p['created_at']),
      'like_count': _i(p['upvotes']) ?? 0,
      'hidden': _b(p['hidden']) || _b(p['deleted']),
      'reply_to_post_number': _i(p['reply_to_post_number']),
      'direct_reply_count': _i(p['replies']) ?? _i(p['reply_count']) ?? 0,
      'children': <Map<String, dynamic>>[],
    };
    while (stack.isNotEmpty && stack.last.$1 >= depth) {
      stack.removeLast();
    }
    if (stack.isEmpty) {
      roots.add(node);
    } else {
      (stack.last.$2['children'] as List).add(node);
    }
    stack.add((depth, node));
  }
  return roots;
}

// ---------------------------------------------------------------- 投票 / 抽奖 / 红包

PostPoll pollFrom(Map poll) => PostPoll(
      name: (_s(poll['name']) ?? '').isEmpty ? 'poll' : _s(poll['name'])!,
      type: (_s(poll['type']) ?? '').isEmpty ? 'regular' : _s(poll['type'])!,
      status: _b(poll['closed']) ? 'closed' : 'open',
      title: '投票',
      min: _i(poll['min']),
      max: _i(poll['max']),
      voters: _i(poll['voters']),
      options: _l(poll['options'])
          .map(_m)
          .map((o) => PollOption(
                id: '${_i(o['id']) ?? ''}',
                html: _s(o['text']) ?? '',
                // 结果不可见时不显示票数。
                votes: _b(poll['results_visible']) || !poll.containsKey('results_visible')
                    ? _i(o['votes'])
                    : null,
              ))
          .where((o) => o.id.isNotEmpty)
          .toList(),
    );

/// 我在每个投票里选中的选项 id。
Map<String, List<String>> pollVotesFrom(List polls) => {
      for (final raw in polls)
        if (_l(_m(raw)['options']).any((o) => _b(_m(o)['chosen'])))
          ((_s(_m(raw)['name']) ?? '').isEmpty ? 'poll' : _s(_m(raw)['name'])!): _l(_m(raw)['options'])
              .map(_m)
              .where((o) => _b(o['chosen']))
              .map((o) => '${_i(o['id'])}')
              .toList(),
    };

PostLottery lotteryFrom(Map l) {
  final prizes = _l(l['prizes']).map(_m).toList();
  final mine = _i(l['my_tickets']) ?? 0;
  return PostLottery(
    id: _i(l['id']) ?? 0,
    title: _s(l['title']) ?? '抽奖',
    status: _s(l['status']) ?? '',
    participantsCount: _i(l['participant_count']) ?? 0,
    maxParticipants: _i(l['max_participants']),
    drawAt: toDate(l['draw_at']),
    prizes: [
      for (final p in prizes)
        if (_s(p['prize']) != null) _s(p['prize'])!,
    ],
    minTicketsPerUser: _i(l['min_tickets']) ?? 1,
    maxTicketsPerUser: _i(l['max_tickets']) ?? 1,
    userTickets: mine,
    isParticipating: mine > 0,
  );
}

TopicRedEnvelope redEnvelopeFrom(Map e) {
  final total = _i(e['total_count']) ?? 0;
  final claimed = _i(e['claimed_count']) ?? _l(e['claims']).length;
  return TopicRedEnvelope(
    totalPoints: _i(e['total_points']) ?? 0,
    totalCount: total,
    availableCount: (total - claimed).clamp(0, 1 << 30),
    exhausted: _b(e['ended']) || (total > 0 && claimed >= total),
  );
}

/// 红包领取记录按楼层分发：只有领取记录指向的那一楼才带上它。
Map<int, RedEnvelopeClaim> redEnvelopeClaimsFrom(Map e) => {
      for (final raw in _l(e['claims']))
        if (_i(_m(raw)['post_id']) != null)
          _i(_m(raw)['post_id'])!: RedEnvelopeClaim(
            postId: _i(_m(raw)['post_id']),
            pointsReceived: _i(_m(raw)['points']) ?? 0,
          ),
    };

// ---------------------------------------------------------------- 节点

Category categoryFrom(Map n) => Category.fromJson({
      'id': _i(n['id']) ?? 0,
      'name': _s(n['name']) ?? '',
      'color': _s(n['color']),
      'slug': _s(n['slug']),
      'topic_count': _i(n['topic_count']) ?? 0,
      'description_excerpt': _s(n['description']) ?? '',
      'parent_category_id': _i(n['parent_id']),
      'member_count': _i(n['member_count']) ?? 0,
      'is_joined': _b(n['joined']),
      'description': _s(n['description']),
      'topic_policy': _s(n['topic_policy']),
      'read_restricted': _s(n['visibility']) != null && _s(n['visibility']) != 'public',
    });

// ---------------------------------------------------------------- 通知

/// Discourse 通知类型编号（推送、通知页按它分类）。
const int notifyMentioned = 1;
const int notifyReplied = 2;
const int notifyLiked = 5;
const int notifyPosted = 9;
const int notifyLinked = 11;
const int notifyLikedConsolidated = 19;
const int notifyChatMessage = 30;
const int notifyWatchingCategory = 36;
const int notifyFollowing = 800;
const int notifyFollowingCreatedTopic = 801;

int notificationTypeOf(String kind, {int actorCount = 1}) => switch (kind) {
      'reply' => notifyReplied,
      'mention' => notifyMentioned,
      'vote' => actorCount > 1 ? notifyLikedConsolidated : notifyLiked,
      'watching' => notifyPosted,
      'followed_topic' => notifyFollowingCreatedTopic,
      'follow' => notifyFollowing,
      'message' => notifyChatMessage,
      'node_topic' || 'node_hot_topic' => notifyWatchingCategory,
      'repost' => notifyLinked,
      // 系统通知：通知页直接显示它自带的标题。
      _ => 0,
    };

int? _topicIdFromPath(String? path) {
  final m = RegExp(r'^/t/(?:[^/]+/)?(\d+)').firstMatch(path ?? '');
  return m == null ? null : int.tryParse(m.group(1)!);
}

NotificationItem notificationFrom(Map n) {
  final data = _m(n['data']);
  final kind = _s(n['kind']) ?? '';
  final title = _s(n['topic_title']) ??
      (kind == 'message' ? _s(data['excerpt']) : (_s(data['title']) ?? _s(data['body']))) ??
      '';
  return NotificationItem(
    id: _i(n['id']) ?? 0,
    type: notificationTypeOf(kind, actorCount: _i(n['actor_count']) ?? 1),
    read: _b(n['read']),
    createdAt: toDate(n['created_at']),
    postNumber: _i(n['post_number']),
    // 系统通知不带 topic_id，链接只在 data.path（如 /t/119445）里。
    topicId: _i(n['topic_id']) ?? _topicIdFromPath(_s(data['path'])),
    topicTitle: title,
    displayUsername: _s(n['actor']) ?? '',
  );
}

// ---------------------------------------------------------------- 用户

CurrentUser currentUserFrom(Map user, {int unread = 0}) => CurrentUser(
      id: _i(user['id']) ?? 0,
      username: _s(user['username']) ?? '',
      name: _s(user['name']),
      avatarTemplate: _s(user['avatar_url'] ?? user['avatar']),
      unreadNotifications: unread,
      admin: _s(user['role']) == 'admin',
    );

/// `GET /users/{username}`：`{user, stats}`。
UserProfile userProfileFrom(Map envelope, {String? me}) {
  final u = _m(envelope['user']);
  final stats = _m(envelope['stats']);
  final username = _s(u['username']) ?? '';
  final self = me != null && me.toLowerCase() == username.toLowerCase();
  return UserProfile(
    username: username,
    name: _s(u['name']),
    avatarTemplate: _s(u['avatar_url'] ?? u['avatar']),
    bioCooked: _s(u['bio_html']) ?? '',
    postCount: _i(stats['post_count']) ?? 0,
    badgeCount: _i(u['achievement_count']) ?? 0,
    topicCount: _i(stats['topic_count']),
    createdAt: toDate(u['created_at']),
    lastSeenAt: toDate(u['last_seen_at']),
    location: _s(u['location']),
    website: _s(u['website']),
    canFollow: !self,
    isFollowed: _b(u['viewer_following']),
    totalFollowers: _i(u['follower_count']),
    canIgnoreUsers: !self,
    viewerBlocked: _b(u['viewer_blocked']),
  );
}

UserBadge badgeFromAchievement(Map a, int index) => UserBadge(
      id: index + 1,
      name: _s(a['name']) ?? '',
      description: _s(a['description']),
      imageUrl: _s(a['icon']),
    );

// ---------------------------------------------------------------- 搜索 / 收藏

/// 新接口的搜索返回帖子和话题两部分：有帖子按帖子列；只命中话题标题的也列出来（指向一楼）。
SearchResult searchResultFrom(Map json) {
  final titles = <int, String>{};
  for (final raw in _l(json['topics'])) {
    final t = _m(raw);
    titles[_i(t['id']) ?? 0] = _s(t['title']) ?? '';
  }
  final items = <SearchPostItem>[];
  final covered = <int>{};
  for (final raw in _l(json['posts'])) {
    final p = _m(raw);
    final tid = _i(p['topic_id']) ?? 0;
    covered.add(tid);
    items.add(SearchPostItem(
      id: _i(p['id']) ?? 0,
      topicId: tid,
      topicTitle: titles[tid] ?? _s(p['topic_title']) ?? '',
      blurb: plainTextOf(_s(p['blurb']) ?? _s(p['excerpt']) ?? ''),
      username: _s(p['author']) ?? '',
      postNumber: _i(p['post_number']) ?? 1,
    ));
  }
  for (final raw in _l(json['topics'])) {
    final t = _m(raw);
    final tid = _i(t['id']) ?? 0;
    if (covered.contains(tid)) continue;
    items.add(SearchPostItem(
      id: _i(t['first_post_id']) ?? 0,
      topicId: tid,
      topicTitle: _s(t['title']) ?? '',
      blurb: plainTextOf(_s(t['excerpt']) ?? ''),
      username: _s(t['author']) ?? '',
      avatarTemplate: _s(t['author_avatar']),
      postNumber: 1,
      createdAt: toDate(t['created_at']),
    ));
  }
  return SearchResult(items: items, hasMore: _b(json['has_more']));
}

/// `GET /saved` 的一行。收藏编号就是帖子 id（取消收藏按帖子）。
BookmarkItem bookmarkFrom(Map b) => BookmarkItem(
      id: _i(b['post_id']) ?? _i(b['id']) ?? 0,
      topicId: _i(b['topic_id']),
      postId: _i(b['post_id']),
      postNumber: _i(b['post_number']),
      title: _s(b['topic_title']) ?? '',
      excerpt: plainTextOf(_s(b['excerpt']) ?? _s(b['html']) ?? ''),
      createdAt: toDate(b['created_at']),
      username: _s(b['author']),
    );

// ---------------------------------------------------------------- 积分 / 签到 / 等级

PointsEntry pointsEntryFrom(Map e) {
  final amount = _i(e['amount']) ?? 0;
  return PointsEntry(
    points: amount,
    description: _s(e['memo']) ?? _s(e['counterpart']) ?? _s(e['kind']) ?? '',
    isPositive: amount >= 0,
    createdAt: toDate(e['created_at']),
  );
}

CheckinStatus checkinStatusFrom(Map s) {
  final done = _b(s['checked_in_today']);
  final points = _i(s['today_points']);
  return CheckinStatus(
    checkedInToday: done,
    pointsToday: done ? points : null,
    // 未签到时 today_points 是这次签到能拿到的积分；没给就按“可签到”处理。
    nextPoints: done ? null : (points ?? 0),
    streak: _i(s['streak']) ?? 0,
    totalDays: _i(s['total']) ?? 0,
  );
}

/// 等级只看声望，所以清单只有一项。
UpgradeProgress upgradeProgressFrom(Map rep) {
  final next = rep['next'] is Map ? rep['next'] as Map : null;
  final target = next == null ? null : _i(next['threshold']);
  final value = _i(rep['reputation']) ?? 0;
  return UpgradeProgress(
    currentLevel: _i(rep['tier']) ?? 0,
    currentLevelName: _s(rep['tier_name']),
    nextLevel: next == null ? null : _i(next['level']),
    nextLevelName: next == null ? null : _s(next['name']),
    conditions: target == null
        ? const []
        : [
            UpgradeCondition(
              label: '声望',
              text: '$value / $target',
              scope: '',
              group: 'standing',
              comparison: 'min',
              value: value,
              target: target,
              met: value >= target,
            ),
          ],
    totalConditions: target == null ? 0 : 1,
    metCount: target != null && value >= target ? 1 : 0,
    maxLevelReached: next == null,
  );
}

// ---------------------------------------------------------------- 账号安全

/// `GET /me/identities` 列出站点支持的所有登录方式，只有 linked 的才算已关联。
List<AssociatedAccount> associatedAccountsFrom(Map json) => [
      for (final raw in _l(json['identities']))
        if (!_m(raw).containsKey('linked') || _b(_m(raw)['linked']))
          AssociatedAccount(
            name: _s(_m(raw)['provider']) ?? '',
            description: _s(_m(raw)['name']) ?? _s(_m(raw)['email']) ?? _s(_m(raw)['username']),
          ),
    ];

/// 把登录记录里的 User-Agent 读成「浏览器 · 系统」，认不出时退回原文。
String describeUserAgent(String? ua) {
  if (ua == null || ua.trim().isEmpty) return '未知设备';
  String? pick(List<(String, String)> rules) {
    for (final (needle, name) in rules) {
      if (ua.contains(needle)) return name;
    }
    return null;
  }
  final client = pick(const [
    ('Nekoloc/', 'Nekoloc'), ('NodeLoc/', 'NodeLoc 客户端'), ('okhttp', 'NodeLoc 客户端'),
    ('Edg/', 'Edge'), ('OPR/', 'Opera'), ('Firefox/', 'Firefox'), ('Chrome/', 'Chrome'),
    ('Safari/', 'Safari'),
  ]);
  final os = pick(const [
    ('Android', 'Android'), ('iPhone', 'iPhone'), ('iPad', 'iPad'), ('Windows', 'Windows'),
    ('Mac OS X', 'macOS'), ('Macintosh', 'macOS'), ('CrOS', 'ChromeOS'), ('Linux', 'Linux'),
  ]);
  final parts = [client, os].whereType<String>().toList();
  return parts.isEmpty ? ua : parts.join(' · ');
}

List<AuthSession> sessionsFrom(Map json) => [
      for (final raw in _l(json['sessions']))
        AuthSession(
          id: _i(_m(raw)['id']) ?? 0,
          deviceName: describeUserAgent(_s(_m(raw)['user_agent'])) +
              (_b(_m(raw)['current']) ? '（本机）' : ''),
          osName: _s(_m(raw)['ip']) == null ? null : 'IP ${_s(_m(raw)['ip'])}',
          seenAt: toDate(_m(raw)['last_seen_at']),
          isActive: _b(_m(raw)['current']),
        ),
    ];

// ---------------------------------------------------------------- 聊天

final _imgTag = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final _imgSrc = RegExp(r'''\bsrc\s*=\s*"([^"]+)"''', caseSensitive: false);
final _imgClass = RegExp(r'''\bclass\s*=\s*"([^"]*)"''', caseSensitive: false);

/// 聊天图片在消息 HTML 里以 `<img>` 出现；气泡用 [ChatMessage.imageUrls] 显示图片，
/// 所以把图片挪出来，表情（emoji 类名）保留在文字里。
(String, List<String>) splitChatImages(String html) {
  final images = <String>[];
  final stripped = html.replaceAllMapped(_imgTag, (m) {
    final tag = m.group(0)!;
    final classes = _imgClass.firstMatch(tag)?.group(1) ?? '';
    final src = _imgSrc.firstMatch(tag)?.group(1);
    final isEmoji = classes.split(' ').any((c) => c == 'emoji' || c.startsWith('emoji-'));
    if (src == null || isEmoji) return tag;
    images.add(src.replaceAll('&amp;', '&'));
    return '';
  });
  return (stripped, images);
}

ChatMessage chatMessageFrom(Map m) {
  final (html, images) = splitChatImages(_s(m['html']) ?? '');
  final sender = _s(m['sender']) ?? '';
  return ChatMessage(
    id: _i(m['id']) ?? 0,
    text: _b(m['deleted']) ? '' : plainTextOf(html),
    user: sender.isEmpty ? null : ChatUser(id: syntheticUserId(sender), username: sender),
    createdAt: toDate(m['created_at']),
    deleted: _b(m['deleted']),
    imageUrls: images,
  );
}

/// `GET /chat`：公开频道、群聊、私聊三类会话。
List<ChatChannel> chatChannelsFrom(Map json, {String? me}) {
  final out = <ChatChannel>[];
  for (final raw in _l(json['directs'])) {
    final d = _m(raw);
    final who = _s(d['with']) ?? '';
    out.add(ChatChannel(
      id: _i(d['id']) ?? 0,
      title: who,
      isDirect: true,
      lastExcerpt: _s(d['excerpt']),
      directUsername: who,
      unreadCount: _i(d['unread_count']) ?? 0,
      muted: _b(d['muted']),
      lastMessageAt: toDate(d['last_message_at']),
    ));
  }
  for (final raw in _l(json['groups'])) {
    final g = _m(raw);
    final members = _l(g['members']).map((e) => e.toString()).where((e) => e != me).toList();
    final name = _s(g['name']);
    out.add(ChatChannel(
      id: _i(g['id']) ?? 0,
      title: (name == null || name.trim().isEmpty) ? members.join('、') : name,
      isDirect: true,
      isGroup: true,
      lastExcerpt: _s(g['excerpt']),
      unreadCount: _i(g['unread_count']) ?? 0,
      muted: _b(g['muted']),
      lastMessageAt: toDate(g['last_message_at']),
    ));
  }
  out.sort((a, b) => (b.lastMessageAt ?? DateTime(0)).compareTo(a.lastMessageAt ?? DateTime(0)));
  final channels = _l(json['channels']).map(_m).toList()
    ..sort((a, b) => (_b(b['joined']) ? 1 : 0) - (_b(a['joined']) ? 1 : 0));
  for (final c in channels) {
    out.add(ChatChannel(
      id: _i(c['id']) ?? 0,
      title: _s(c['name']) ?? _s(c['slug']) ?? '',
      isDirect: false,
      lastExcerpt: _s(c['excerpt']),
      unreadCount: _i(c['unread_count']) ?? 0,
      muted: _b(c['muted']),
      lastMessageAt: toDate(c['last_message_at']),
    ));
  }
  return out;
}

/// `GET /me/blocks` 的用户名列表。结构未在公开文档中给出，按常见形状宽松读取。
List<String> blockedUsernamesFrom(dynamic json) {
  final source = json is List
      ? json
      : _l(_m(json)['users']).isNotEmpty
          ? _l(_m(json)['users'])
          : _l(_m(json)['blocks']).isNotEmpty
              ? _l(_m(json)['blocks'])
              : _l(_m(json)['blocked']);
  return [
    for (final e in source)
      if (e is String && e.isNotEmpty)
        e
      else if (e is Map && (_s(e['username']) ?? _s(e['blocked_username']) ?? '').isNotEmpty)
        (_s(e['username']) ?? _s(e['blocked_username']))!,
  ];
}

/// 举报理由：新接口接受固定的理由代码，界面按这个顺序列出。
const reportReasonCodes = [
  'spam',
  'inappropriate',
  'harassment',
  'off_topic',
  'illegal',
  'copyright',
  'other',
];

const _reportReasonNames = {
  'spam': '垃圾广告',
  'inappropriate': '不当内容',
  'harassment': '骚扰或攻击',
  'off_topic': '偏离主题',
  'illegal': '违法内容',
  'copyright': '侵犯版权',
  'other': '其他（请说明）',
};

List<PostFlagReason> reportReasons() => [
      for (var i = 0; i < reportReasonCodes.length; i++)
        PostFlagReason(
          id: i + 1,
          name: _reportReasonNames[reportReasonCodes[i]]!,
          requireMessage: reportReasonCodes[i] == 'other',
          position: i,
        ),
    ];

String reportReasonCodeFor(int id) =>
    id >= 1 && id <= reportReasonCodes.length ? reportReasonCodes[id - 1] : 'other';

// ---------------------------------------------------------------- 视频

/// 站内上传的视频在帖子里只是一个占位 div，只带视频的 SHA1：
/// `<div class="video-embed" data-provider="upload" data-video-id="<sha1>"></div>`。
final _uploadVideoDiv = RegExp(r'<div\b[^>]*\bclass="[^"]*\bvideo-embed\b[^"]*"[^>]*>\s*</div>', caseSensitive: false);
final _htmlAttr = RegExp(r'([\w-]+)\s*=\s*"([^"]*)"');
final _sha1Pattern = RegExp(r'^[0-9a-f]{40}$');

String? _uploadSha1(String div) {
  final attrs = {for (final m in _htmlAttr.allMatches(div)) m.group(1)!.toLowerCase(): m.group(2)!};
  final id = (attrs['data-video-id'] ?? '').toLowerCase();
  return attrs['data-provider'] == 'upload' && _sha1Pattern.hasMatch(id) ? id : null;
}

/// 帖子里站内上传视频的 SHA1（去重）。
Set<String> uploadVideoIds(String html) =>
    _uploadVideoDiv.allMatches(html).map((m) => _uploadSha1(m.group(0)!)).whereType<String>().toSet();

/// `GET /videos/{sha1}` 的结果里能播放的部分；没转码完（status 不是 ready）时为 null。
({String hls, String? poster, int? width, int? height})? playableVideoFrom(Map? video) {
  if (video == null) return null;
  final status = _s(video['status']);
  final hls = _s(video['hls_url']);
  if (hls == null || (status != null && status != 'ready')) return null;
  return (hls: hls, poster: _s(video['poster_url']), width: _i(video['width']), height: _i(video['height']));
}

String _escAttr(String v) =>
    v.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// 把已转码好的上传视频换成 `<video>`，阅读页的 HTML 渲染器会在安卓、iOS、macOS 上直接播放；
/// 其他平台显示里面的链接，去网页版观看。没转码完的保留原样（界面显示占位卡片）。
String rewriteUploadVideos(String html, Map<String, Map?> videos, {required String fallbackUrl}) =>
    html.replaceAllMapped(_uploadVideoDiv, (m) {
      final sha1 = _uploadSha1(m.group(0)!);
      final v = sha1 == null ? null : playableVideoFrom(videos[sha1]);
      if (v == null) return m.group(0)!;
      final w = v.width, h = v.height;
      final dims = w != null && h != null && w > 0 && h > 0 ? ' width="$w" height="$h"' : '';
      final poster = v.poster == null ? '' : ' poster="${_escAttr(v.poster!)}"';
      return '<video controls src="${_escAttr(v.hls)}"$poster$dims>'
          '<a href="${_escAttr(fallbackUrl)}">视频（点击在网页版观看）</a></video>';
    });
