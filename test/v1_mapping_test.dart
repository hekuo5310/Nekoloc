import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/api/v1_mapping.dart';

/// 样本取自参考客户端（NodeLoc Android api-v1 分支）从真实服务器抓取的响应。
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/api/$name').readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('话题列表：回复数 +1 为楼数，作者以 id 关联，有游标即有下一页', () {
    final list = topicListFrom(fixture('topics.json'), nodeIdOf: (slug) => slug == 'announcement' ? 1 : null);
    final first = list.topics.first;
    expect(first.id, 18);
    expect(first.title, '本周六凌晨两点到四点停机维护');
    expect(first.postsCount, (fixture('topics.json')['topics'][0]['reply_count'] as int) + 1);
    expect(first.categoryId, 1);
    expect(first.pinned, isTrue);
    expect(first.closed, isTrue);
    final poster = first.posters.single;
    expect(list.users[poster.userId]!.username, 'system');
    expect(list.hasMore, isTrue);
  });

  test('系统账号 author_id 为 -1 时用名字算出的稳定 id', () {
    expect(authorIdOf({'author': 'system', 'author_id': -1}), syntheticUserId('system'));
    expect(syntheticUserId('Alice'), syntheticUserId('alice'));
    expect(syntheticUserId('alice'), isNot(syntheticUserId('bob')));
    expect(syntheticUserId(''), 0);
  });

  test('话题详情：赞即赞成票，收藏编号为帖子 id，权限决定能否回复', () {
    final page = fixture('topic_1.json');
    final detail = topicDetailFrom(page, viewerId: 3);
    expect(detail.title, '欢迎来到新的 NodeLoc');
    expect(detail.postsCount, 6);
    expect(detail.canReply, isTrue);
    expect(detail.nextAfter, isNull);
    expect(detail.hasMorePosts, isFalse);
    final op = detail.posts.first;
    expect(op.postNumber, 1);
    expect(op.likeCount, 5);
    expect(op.likedByMe, isTrue);
    expect(op.voteDirection, 'up');
    expect(op.voteScore, 5);
    expect(op.cooked, contains('Go 重写'));
    expect(detail.tags, ['公告']);
  });

  test('楼层：已收藏的帖子带上收藏编号，删除的帖子按隐藏处理', () {
    final post = postFrom({
      'id': 9, 'post_number': 2, 'author': 'bob', 'author_id': 4,
      'html': '<p>x</p>', 'viewer_bookmarked': true, 'deleted': true,
      'upvotes': 3, 'downvotes': 1, 'viewer_vote': -1,
    }, viewerId: 4);
    expect(post.bookmarkId, 9);
    expect(post.hidden, isTrue);
    expect(post.voteScore, 2);
    expect(post.voteDirection, 'down');
    // 自己的帖子被删除后不能再编辑或删除。
    expect(post.canEdit, isFalse);
    expect(post.canDelete, isFalse);
    expect(postFrom({'id': 1, 'post_number': 3, 'author': 'bob', 'can_delete': true}, viewerId: 9).canDelete, isTrue);
    // 自己的帖子（含自己话题的一楼）即使站点给 can_delete=false 也能删。
    expect(postFrom({'id': 2, 'post_number': 3, 'author': 'bob', 'author_id': 4, 'can_delete': false}, viewerId: 4).canDelete, isTrue);
    expect(postFrom({'id': 3, 'post_number': 1, 'author': 'bob', 'author_id': 4, 'can_delete': false}, viewerId: 4).canDelete, isTrue);
    expect(postFrom({'id': 4, 'post_number': 3, 'author': 'carol', 'author_id': 5, 'can_delete': false}, viewerId: 4).canDelete, isFalse);
  });

  test('嵌套视图：按 depth 还原楼中楼', () {
    final roots = threadTree(fixture('thread_2.json')['posts'] as List);
    expect(roots, isNotEmpty);
    final first = roots.first;
    expect(first['post_number'], 2);
    expect(first['username'], 'dave');
    final children = first['children'] as List;
    expect(children, isNotEmpty);
    expect((children.first as Map)['reply_to_post_number'], 2);
  });

  test('投票：选项 id 转为字符串，已选的记入 pollsVotes', () {
    final polls = fixture('polls_59.json')['polls'] as List;
    final poll = pollFrom(polls.first as Map);
    expect(poll.name, 'poll');
    expect(poll.isMultiple, isTrue);
    expect(poll.maximum, 2);
    expect(poll.options.map((o) => o.id), ['1', '2', '3']);
    expect(pollVotesFrom(polls), isEmpty);
    final voted = {
      ...(polls.first as Map),
      'options': [
        {'id': 1, 'text': 'a', 'chosen': true},
        {'id': 2, 'text': 'b', 'chosen': false},
      ],
    };
    expect(pollVotesFrom([voted]), {'poll': ['1']});
  });

  test('通知：系统通知显示自带标题，类型编号沿用旧的分类', () {
    final items = (fixture('notifications.json')['notifications'] as List)
        .map((e) => notificationFrom(e as Map))
        .toList();
    final system = items.first;
    expect(system.type, 0);
    expect(system.topicTitle, '你解锁了成就「最初的结」');
    expect(system.read, isFalse);
    expect(notificationTypeOf('reply'), 2);
    expect(notificationTypeOf('mention'), 1);
    expect(notificationTypeOf('vote', actorCount: 3), 19);
    expect(notificationTypeOf('message'), 30);
  });

  test('聊天：私聊与群聊列在公开频道之前，私聊记下对方用户名', () {
    final channels = chatChannelsFrom(fixture('chat.json'), me: 'alice');
    final directs = channels.where((c) => c.isDirect).toList();
    final public = channels.where((c) => !c.isDirect).toList();
    expect(public.first.title, '闲聊');
    expect(channels.indexOf(public.first), greaterThanOrEqualTo(directs.length));
    for (final d in directs.where((c) => !c.isGroup)) {
      expect(d.directUsername, isNotNull);
    }
  });

  test('聊天消息：HTML 转为文字，发送者保留', () {
    final messages = (fixture('channel_1_messages.json')['messages'] as List)
        .map((e) => chatMessageFrom(e as Map))
        .toList();
    expect(messages.first.text, '求个链接');
    expect(messages.first.user!.username, 'carol');
    expect(messages[1].text, contains('ping'));
  });

  test('聊天图片从消息 HTML 中挪出，表情留在文字里', () {
    final (html, images) = splitChatImages(
      '<p>看 <img class="emoji" src="/e/smile.png"> 这张 <img src="/uploads/a.png?x=1&amp;y=2"></p>',
    );
    expect(images, ['/uploads/a.png?x=1&y=2']);
    expect(html, contains('emoji'));
    expect(html, isNot(contains('/uploads/a.png')));
  });

  test('个人资料：统计来自 stats，关注与屏蔽状态来自 viewer_*', () {
    final profile = userProfileFrom(fixture('user_bob.json'), me: 'alice');
    expect(profile.username, 'bob');
    expect(profile.postCount, 10);
    expect(profile.topicCount, 3);
    expect(profile.canFollow, isTrue);
    expect(profile.viewerBlocked, isFalse);
    final self = userProfileFrom(fixture('user_bob.json'), me: 'Bob');
    expect(self.canFollow, isFalse);
  });

  test('当前用户：头像与管理员身份', () {
    final me = currentUserFrom(fixture('me.json')['user'] as Map, unread: 2);
    expect(me.username, 'alice');
    expect(me.id, 3);
    expect(me.admin, isFalse);
    expect(me.unreadNotifications, 2);
  });

  test('节点：父子关系与成员数，非公开节点标为受限', () {
    final nodes = (fixture('nodes.json')['nodes'] as List).map((e) => categoryFrom(e as Map)).toList();
    expect(nodes, isNotEmpty);
    expect(nodes.any((n) => n.parentId != null), isTrue);
    final restricted = categoryFrom({'id': 1, 'name': 'x', 'visibility': 'private'});
    expect(restricted.readRestricted, isTrue);
    expect(categoryFrom({'id': 2, 'name': 'y', 'visibility': 'public', 'topic_policy': 'members'}).topicPolicy, 'members');
  });

  test('红包：领完与剩余；领取记录只挂在它指向的楼层', () {
    final e = {
      'total_points': 100, 'total_count': 3, 'claimed_count': 3, 'ended': false,
      'claims': [
        {'username': 'bob', 'post_id': 12, 'points': 40},
      ],
    };
    final envelope = redEnvelopeFrom(e);
    expect(envelope.exhausted, isTrue);
    expect(envelope.availableCount, 0);
    final claims = redEnvelopeClaimsFrom(e);
    expect(claims.keys, [12]);
    expect(claims[12]!.pointsReceived, 40);
  });

  test('抽奖：票数上下限与我的票数', () {
    final lottery = lotteryFrom({
      'id': 5, 'title': '周年', 'status': 'open', 'min_tickets': 1, 'max_tickets': 5,
      'participant_count': 8, 'my_tickets': 2,
      'prizes': [
        {'name': '一等奖', 'prize': '键盘', 'quantity': 1},
      ],
    });
    expect(lottery.isOpen, isTrue);
    expect(lottery.maxTicketsPerUser, 5);
    expect(lottery.userTickets, 2);
    expect(lottery.isParticipating, isTrue);
    expect(lottery.prizes, ['键盘']);
  });

  test('签到：未签到时 today_points 是这次能拿到的积分', () {
    final before = checkinStatusFrom({'checked_in_today': false, 'today_points': 5, 'streak': 2, 'total': 9});
    expect(before.canCheckIn, isTrue);
    expect(before.nextPoints, 5);
    final after = checkinStatusFrom({'checked_in_today': true, 'today_points': 5});
    expect(after.canCheckIn, isFalse);
    expect(after.pointsToday, 5);
  });

  test('搜索：只命中标题的话题也列出，指向一楼', () {
    final result = searchResultFrom({
      'topics': [
        {'id': 1, 'title': '甲', 'excerpt': '<b>摘要</b>', 'author': 'bob', 'first_post_id': 10},
        {'id': 2, 'title': '乙'},
      ],
      'posts': [
        {'id': 20, 'topic_id': 2, 'post_number': 3, 'blurb': '命中', 'author': 'carol'},
      ],
      'has_more': true,
    });
    expect(result.items.map((i) => i.topicId), [2, 1]);
    expect(result.items.first.topicTitle, '乙');
    expect(result.items.last.postNumber, 1);
    expect(result.items.last.blurb, '摘要');
    expect(result.hasMore, isTrue);
  });

  test('等级：只有声望一项要求', () {
    final p = upgradeProgressFrom({
      'reputation': 120, 'tier': 2, 'tier_name': '黄金',
      'next': {'level': 3, 'name': '钻石', 'threshold': 200},
    });
    expect(p.currentLevelName, '黄金');
    expect(p.nextLevelName, '钻石');
    expect(p.conditions.single.target, 200);
    expect(p.allMet, isFalse);
    expect(upgradeProgressFrom({'tier': 5}).maxLevelReached, isTrue);
  });

  test('系统通知没有 topic_id 时从 data.path 取话题', () {
    final n = notificationFrom({
      'id': 1, 'kind': 'system', 'read': false,
      'data': {'title': 'App 已适配', 'path': '/t/119445'},
    });
    expect(n.topicId, 119445);
    expect(n.topicTitle, 'App 已适配');
    expect(notificationFrom({'id': 2, 'kind': 'system', 'data': {'path': '/u/bob'}}).topicId, isNull);
  });

  test('登录设备：User-Agent 读成浏览器与系统，IP 单独列出', () {
    final s = sessionsFrom({
      'sessions': [
        {'id': 1, 'user_agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:160.0) Gecko/20100101 Firefox/160.0', 'ip': '1.2.3.4', 'current': true},
        {'id': 2, 'user_agent': 'Nekoloc/2.0.0 (Flutter; android; +https://github.com/hekuo5310/Nekoloc)'},
      ],
    });
    expect(s.first.deviceName, 'Firefox · Windows（本机）');
    expect(s.first.osName, 'IP 1.2.3.4');
    expect(s.last.deviceName, 'Nekoloc');
    expect(describeUserAgent('Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/140 Mobile Safari/537.36'), 'Chrome · Android');
    expect(describeUserAgent('curl/8'), 'curl/8');
  });

  test('屏蔽名单：宽松读取几种可能的结构', () {
    expect(blockedUsernamesFrom({'users': [{'username': 'bob'}]}), ['bob']);
    expect(blockedUsernamesFrom({'users': [{'username': 'pencilnav', 'avatar': null, 'since': '2026-01-01', 'name': ''}]}), ['pencilnav']);
    expect(blockedUsernamesFrom({'blocks': ['carol']}), ['carol']);
    expect(blockedUsernamesFrom([{'username': 'dave'}]), ['dave']);
    expect(blockedUsernamesFrom({}), isEmpty);
  });

  test('举报理由：编号与理由代码一一对应', () {
    final reasons = reportReasons();
    expect(reasons.first.name, '垃圾广告');
    expect(reportReasonCodeFor(reasons.first.id), 'spam');
    expect(reasons.last.requireMessage, isTrue);
    expect(reportReasonCodeFor(99), 'other');
  });
}
