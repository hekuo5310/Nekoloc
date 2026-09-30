import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../api/discourse_api.dart';
import '../models.dart';
import '../reactions.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';
import '../widgets/image_viewer.dart';
import '../widgets/poll_card.dart';
import 'composer_screen.dart';
import 'tag_topics_screen.dart';
import 'public_profile_screen.dart';

/// 提取 HTML 中所有 http(s) 图片地址（供全屏查看器翻页）
List<String> _extractImages(String cookedHtml) {
  return RegExp(r'<img\b[^>]*\bsrc="([^"]+)"', caseSensitive: false)
      .allMatches(cookedHtml)
      .map((m) => Uri.parse(AppState.baseUrl).resolve(m.group(1)!).toString())
      .where((url) => url.startsWith('https://') || url.startsWith('http://'))
      .toList();
}

/// 话题详情：楼层列表 + 点赞 + 回复
class TopicDetailScreen extends StatefulWidget {
  final int topicId;
  const TopicDetailScreen({super.key, required this.topicId});

  @override
  State<TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends State<TopicDetailScreen> {
  TopicDetail? _detail;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _likingBusy = false;
  int? _votingPostId;
  bool _bookmarkBusy = false;
  bool _notificationBusy = false;
  final Set<String> _pollBusy = {};
  final _scroll = ScrollController();
  DateTime _openedAt = DateTime.now();
  int _reportedPosts = 0;
  DiscourseApi? _apiRef;

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    _apiRef = context.read<AppState>().api;
    _load();
    _scroll.addListener(() {
      final d = _detail;
      if (d == null) return;
      if (_scroll.position.extentAfter < 600 &&
          !_loadingMore &&
          !_loading &&
          _detail!.posts.length < _detail!.stream.length) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _reportTimings();
    _scroll.dispose();
    super.dispose();
  }

  /// 上报阅读进度（同步已读/未读状态）
  void _reportTimings() {
    final d = _detail;
    final api = _apiRef;
    if (d == null || api == null || d.posts.isEmpty) return;
    final totalMs = DateTime.now().difference(_openedAt).inMilliseconds;
    if (totalMs < 2000) return;
    final readPosts = d.posts.length - _reportedPosts;
    if (readPosts <= 0) return;
    _reportedPosts = d.posts.length;
    final per = (totalMs / d.posts.length).round().clamp(1000, 60000);
    final timings = <int, int>{};
    for (final p in d.posts) {
      timings[p.postNumber] = per;
    }
    // 不依赖 context，静默上报
    api.postTimings(d.id, totalMs.clamp(0, 3600000), timings);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await context.read<AppState>().api.topic(widget.topicId);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final d = _detail;
    if (d == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final loaded = d.posts.map((p) => p.id).toSet();
      final nextIds =
          d.stream.where((id) => !loaded.contains(id)).take(20).toList();
      if (nextIds.isEmpty) {
        setState(() => _loadingMore = false);
        return;
      }
      final more =
          await context.read<AppState>().api.topicPosts(widget.topicId, nextIds);
      if (!mounted) return;
      final latest = _detail ?? d;
      final currentIds = latest.posts.map((p) => p.id).toSet();
      final merged = [...latest.posts, ...more.where((p) => !currentIds.contains(p.id))]
        ..sort((a, b) => a.postNumber.compareTo(b.postNumber));
      setState(() => _detail = _copyWithPosts(latest, merged));
    } catch (e) {
      _hint('加载楼层失败：$e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  TopicDetail _copyWithPosts(TopicDetail d, List<Post> posts) => TopicDetail(
        id: d.id,
        title: d.title,
        slug: d.slug,
        postsCount: d.postsCount,
        categoryId: d.categoryId,
        views: d.views,
        likeCount: d.likeCount,
        closed: d.closed,
        archived: d.archived,
        notificationLevel: d.notificationLevel,
        createdAt: d.createdAt,
        posts: posts,
        stream: d.stream,
        tags: d.tags,
      );

  Future<void> _toggleLike(Post post) async {
    // 心=等价于 like，走 reactions 接口
    await _toggleReaction(post, 'heart');
  }

  Future<void> _vote(Post post, String direction) async {
    final app = context.read<AppState>();
    if (!app.isLoggedIn) {
      _hint('请先登录');
      return;
    }
    if (_votingPostId != null) return;
    setState(() => _votingPostId = post.id);
    try {
      final target = post.voteDirection == direction ? 'none' : direction;
      final result = await app.api.castPostVote(post.id, target);
      if (!mounted || _detail == null) return;
      final d = _detail!;
      final index = d.posts.indexWhere((p) => p.id == post.id);
      if (index >= 0) {
        final posts = [...d.posts];
        posts[index] = post.copyWith(
          voteScore: toInt(result['vote_score']) ?? post.voteScore,
          voteDirection: result['vote_direction']?.toString() ?? target,
          canVoteDown: result.containsKey('can_vote_down')
              ? result['can_vote_down'] == true : post.canVoteDown,
        );
        setState(() => _detail = _copyWithPosts(d, posts));
      }
    } catch (e) {
      _hint('投票失败：$e');
    } finally {
      if (mounted) setState(() => _votingPostId = null);
    }
  }

  /// 切换表情反应（discourse-reactions 插件）
  Future<void> _toggleReaction(Post post, String reactionId) async {
    final app = context.read<AppState>();
    if (!app.isLoggedIn) {
      _hint('请先登录');
      return;
    }
    if (_likingBusy) return;
    setState(() => _likingBusy = true);
    try {
      final updated = await app.api.toggleReaction(post.id, reactionId);
      final d = _detail;
      if (d == null || !mounted) return;
      final idx = d.posts.indexWhere((p) => p.id == post.id);
      if (idx >= 0) {
        final newPost = Post.fromJson(updated);
        final posts = [...d.posts];
        posts[idx] = newPost;
        setState(() => _detail = _copyWithPosts(d, posts));
      }
    } catch (e) {
      _hint(e.toString());
    } finally {
      if (mounted) setState(() => _likingBusy = false);
    }
  }

  Future<void> _pollVote(Post post, PostPoll poll, List<String>? options) async {
    final app = context.read<AppState>();
    final key = '${post.id}:${poll.name}';
    if (!app.isLoggedIn) { _hint('请先登录'); return; }
    if (_pollBusy.contains(key) || !poll.canVote) return;
    if (options != null && !poll.validSelection(options.toSet())) {
      _hint('请选择 ${poll.minimum}–${poll.maximum} 项'); return;
    }
    setState(() => _pollBusy.add(key));
    try {
      final result = options == null
          ? await app.api.removePollVote(post.id, poll.name)
          : await app.api.votePoll(post.id, poll.name, options);
      if (!mounted) return;
      // If a plugin version omits its state, fetch server truth instead of
      // guessing hidden results or claiming that a vote succeeded locally.
      if (result.poll == null || result.vote == null) {
        await _load();
        return;
      }
      final d = _detail;
      if (d == null) return;
      final posts = d.posts.map((p) => p.id != post.id ? p : p.copyWith(
        polls: p.polls.map((item) => item.name == poll.name ? result.poll! : item).toList(),
        pollsVotes: {...p.pollsVotes, poll.name: result.vote!},
      )).toList();
      setState(() => _detail = _copyWithPosts(d, posts));
    } catch (e) {
      _hint('投票操作失败：$e');
    } finally {
      if (mounted) setState(() => _pollBusy.remove(key));
    }
  }

  /// 首帖工具栏和逐楼菜单共用同一收藏状态。
  Future<void> _toggleBookmark([Post? target]) async {
    final app = context.read<AppState>();
    final d = _detail;
    if (d == null || d.posts.isEmpty) return;
    if (!app.isLoggedIn) { _hint('请先登录'); return; }
    if (_bookmarkBusy) return;
    final post = target ?? d.posts.first;
    setState(() => _bookmarkBusy = true);
    int? newId;
    try {
      if (post.bookmarked) {
        var bid = post.bookmarkId;
        var page = 0;
        int? topicBookmarkId;
        final seen = <int>{};
        while (bid == null) {
          final list = await app.api.bookmarks(app.user!.username, page: page++);
          final unseen = list.where((b) => seen.add(b.id)).toList();
          bid = bookmarkIdForPost(unseen, post.id, d.id, allowTopicBookmark: false);
          if (post.postNumber == 1) {
            for (final bookmark in unseen) {
              if (bookmark.postId == null && bookmark.topicId == d.id) {
                topicBookmarkId ??= bookmark.id;
              }
            }
          }
          if (unseen.isEmpty) break;
        }
        bid ??= topicBookmarkId;
        if (bid == null) throw ApiException('找不到此楼层的收藏记录，请刷新后重试');
        await app.api.removeBookmark(bid);
      } else {
        newId = await app.api.addBookmark(post.id);
      }
      if (!mounted || _detail == null) return;
      final latest = _detail!;
      final posts = latest.posts.map((p) => p.id != post.id ? p : p.copyWith(
        bookmarked: !post.bookmarked, bookmarkId: newId,
        clearBookmarkId: post.bookmarked,
      )).toList();
      setState(() => _detail = _copyWithPosts(latest, posts));
      _hint(post.bookmarked ? '已取消收藏' : '已收藏楼层');
    } catch (e) {
      _hint('收藏操作失败：$e');
    } finally {
      if (mounted) setState(() => _bookmarkBusy = false);
    }
  }

  /// 弹出表情反应选择器
  void _showReactionPicker(Post post) {
    final app = context.read<AppState>();
    if (!app.isLoggedIn) {
      _hint('请先登录');
      return;
    }
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    '选择反应',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (final r in kReactions)
                      _ReactionChip(
                        emoji: r.emoji,
                        label: r.label,
                        count: post.reactions
                            .firstWhere(
                              (rr) => rr.id == r.id,
                              orElse: () => ReactionInfo(id: r.id, count: 0),
                            )
                            .count,
                        highlighted: post.currentUserReaction == r.id,
                        onTap: () {
                          Navigator.pop(ctx);
                          _toggleReaction(post, r.id);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _hint(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _reply({int? replyToPostNumber, String? hint}) async {
    final app = context.read<AppState>();
    if (!app.isLoggedIn) {
      _hint('请先登录');
      return;
    }
    if (_detail?.closed == true || _detail?.archived == true) {
      _hint('该话题已关闭，无法回复');
      return;
    }
    final ok = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComposerScreen(
          isNewTopic: false,
          topicId: widget.topicId,
          replyToPostNumber: replyToPostNumber,
          hint: hint,
        ),
      ),
    );
    if (ok == true && mounted) {
      _load();
    }
  }

  void _copyLink(int postNumber) {
    final d = _detail;
    if (d == null) return;
    final url =
        '${AppState.baseUrl}/t/${d.slug ?? d.id}/${d.id}/$postNumber';
    Clipboard.setData(ClipboardData(text: url));
    _hint('链接已复制');
  }

  Future<void> _openInBrowser() async {
    final d = _detail;
    if (d == null) return;
    final url =
        '${AppState.baseUrl}/t/${d.slug ?? 'topic'}/${d.id}';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _editPost(Post post) async {
    final app = context.read<AppState>();
    try {
      final raw = await app.api.postRaw(post.id);
      if (!mounted) return;
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => ComposerScreen(editPostId: post.id, initialRaw: raw)),
      );
      if (changed == true && mounted) _load();
    } catch (e) {
      _hint('无法编辑：$e');
    }
  }

  Future<void> _changeNotificationLevel(int level) async {
    if (_notificationBusy) return;
    setState(() => _notificationBusy = true);
    try {
      await context.read<AppState>().api.setTopicNotificationLevel(widget.topicId, level);
      if (!mounted) return;
      // Refresh the server state rather than guessing the topic's other fields.
      await _load();
      _hint('通知设置已更新');
    } catch (e) {
      _hint('通知设置失败：$e');
    } finally {
      if (mounted) setState(() => _notificationBusy = false);
    }
  }

  Future<void> _reportPost(Post post) async {
    final app = context.read<AppState>();
    if (!app.isLoggedIn) {
      _hint('请先登录');
      return;
    }
    try {
      final reasons = await app.api.postFlagReasons(username: post.username);
      if (!mounted) return;
      if (reasons.isEmpty) {
        _hint('站点暂未提供可用的举报理由');
        return;
      }
      final sent = await showDialog<bool>(
        context: context,
        builder: (_) => _ReportPostDialog(postId: post.id, reasons: reasons),
      );
      if (sent == true) _hint('举报已提交');
    } catch (e) {
      _hint('获取举报理由失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          d?.title.replaceAll(RegExp(r'<[^>]*>'), '') ?? '话题',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16.5),
        ),
        actions: [
          if (d != null && d.posts.isNotEmpty)
            IconButton(
              tooltip: d.posts.first.bookmarked ? '取消收藏' : '收藏话题',
              onPressed: _bookmarkBusy ? null : _toggleBookmark,
              icon: _bookmarkBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      d.posts.first.bookmarked
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      color: d.posts.first.bookmarked
                          ? scheme.secondary
                          : null,
                    ),
            ),
          IconButton(
            tooltip: '在浏览器中打开',
            icon: const Icon(Icons.open_in_new),
            onPressed: d == null ? null : _openInBrowser,
          ),
          if (d != null && context.watch<AppState>().isLoggedIn)
            PopupMenuButton<int>(
              tooltip: '话题通知',
              enabled: !_notificationBusy,
              icon: const Icon(Icons.notifications_outlined),
              onSelected: _changeNotificationLevel,
              itemBuilder: (_) => [
                for (final (level, label) in [
                  (3, '关注：每条回复都通知'),
                  (2, '追踪：显示未读回复'),
                  (1, '普通：仅提及时通知'),
                  (0, '静音：不提醒'),
                ])
                  PopupMenuItem(
                    value: level,
                    child: Row(children: [
                      if (d.notificationLevel == level) const Icon(Icons.check, size: 18),
                      if (d.notificationLevel == level) const SizedBox(width: 6),
                      Text(label),
                    ]),
                  ),
              ],
            ),
          PopupMenuButton<String>(
            enabled: d != null,
            onSelected: (v) {
              if (v == 'copy') _copyLink(1);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('复制话题链接')),
            ],
          ),
        ],
      ),
      floatingActionButton: d == null || d.closed || d.archived
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _reply(),
              icon: const Icon(Icons.reply),
              label: const Text('回复'),
            ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : d == null
                  ? const EmptyView(text: '内容不存在')
                  : d.posts.isEmpty
                      ? const EmptyView(text: '暂无可显示的帖子')
                      : ListView.separated(
                      controller: _scroll,
                      padding: const EdgeInsets.only(
                          left: 10, right: 10, top: 10, bottom: 96),
                      itemCount: d.posts.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Column(
                            children: [
                              _TopicHeader(detail: d),
                              const SizedBox(height: 8),
                              _PostCard(
                                post: d.posts.first,
                                detail: d,
                                onLike: () => _toggleLike(d.posts.first),
                                onShowReactions: () => _showReactionPicker(d.posts.first),
                                onReply: () => _reply(
                                    replyToPostNumber: 1,
                                    hint: '回复 #1 ${d.posts.first.username}'),
                                onCopyLink: () => _copyLink(d.posts.first.postNumber),
                                onChanged: _load,
                                onEdit: d.posts.first.canEdit
                                    ? () => _editPost(d.posts.first) : null,
                                onReport: () => _reportPost(d.posts.first),
                                onVote: (direction) => _vote(d.posts.first, direction),
                                voting: _votingPostId == d.posts.first.id,
                                onBookmark: () => _toggleBookmark(d.posts.first),
                                bookmarking: _bookmarkBusy,
                                onPollVote: (poll, options) => _pollVote(d.posts.first, poll, options),
                                pollBusy: _pollBusy,
                              ),
                            ],
                          );
                        }
                        if (i == d.posts.length) {
                          if (d.posts.length < d.stream.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: _loadingMore
                                    ? const NekolocLoadingFooter()
                                    : TextButton.icon(
                                        onPressed: _loadMore,
                                        icon: const Icon(Icons.expand_more,
                                            size: 20),
                                        label: Text(
                                            '加载更多（${d.posts.length}/${d.stream.length}）'),                                      ),
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                '已经到底了 · 共 ${d.postsCount} 楼',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant),
                              ),
                            ),
                          );
                        }
                        final post = d.posts[i];
                        return _PostCard(
                          post: post,
                          detail: d,
                          onLike: () => _toggleLike(post),
                          onShowReactions: () => _showReactionPicker(post),
                          onReply: () => _reply(
                              replyToPostNumber: post.postNumber,
                              hint: '回复 #${post.postNumber} ${post.username}'),
                          onCopyLink: () => _copyLink(post.postNumber),
                          onChanged: _load,
                          onEdit: post.canEdit
                              ? () => _editPost(post) : null,
                          onReport: () => _reportPost(post),
                          onVote: (direction) => _vote(post, direction),
                          voting: _votingPostId == post.id,
                          onBookmark: () => _toggleBookmark(post),
                          bookmarking: _bookmarkBusy,
                          onPollVote: (poll, options) => _pollVote(post, poll, options),
                          pollBusy: _pollBusy,
                        );
                      },
                    ),
    );
  }
}

class _TopicHeader extends StatelessWidget {
  final TopicDetail detail;
  const _TopicHeader({required this.detail});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              detail.title.replaceAll(RegExp(r'<[^>]*>'), ''),
              style: const TextStyle(
                  fontSize: 17.5, fontWeight: FontWeight.w800, height: 1.4),
            ),
            const SizedBox(height: 8),
            if (detail.tags.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tag in detail.tags)
                    ActionChip(
                      label: Text('#$tag'),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => TagTopicsScreen(tag: tag),
                      )),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Icon(Icons.visibility, size: 13, color: muted),
                const SizedBox(width: 3),
                Text(compactNumber(detail.views),
                    style: TextStyle(fontSize: 12, color: muted)),
                const SizedBox(width: 12),
                Icon(Icons.chat_bubble_outline, size: 13, color: muted),
                const SizedBox(width: 3),
                Text('${detail.postsCount} 楼',
                    style: TextStyle(fontSize: 12, color: muted)),
                const SizedBox(width: 12),
                Icon(Icons.favorite_outline, size: 13, color: muted),
                const SizedBox(width: 3),
                Text(compactNumber(detail.likeCount),
                    style: TextStyle(fontSize: 12, color: muted)),
                const Spacer(),
                Text(timeAgo(detail.createdAt),
                    style: TextStyle(fontSize: 12, color: muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportPostDialog extends StatefulWidget {
  final int postId;
  final List<PostFlagReason> reasons;
  const _ReportPostDialog({required this.postId, required this.reasons});

  @override
  State<_ReportPostDialog> createState() => _ReportPostDialogState();
}

class _ReportPostDialogState extends State<_ReportPostDialog> {
  final _note = TextEditingController();
  PostFlagReason? _selected;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _selected;
    if (reason == null || _sending ||
        (reason.requireMessage && _note.text.trim().isEmpty)) return;
    setState(() { _sending = true; _error = null; });
    try {
      await context.read<AppState>().api.flagPost(widget.postId, reason, _note.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('举报帖子'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final reason in widget.reasons)
              RadioListTile<int>(
                dense: true,
                title: Text(reason.name),
                value: reason.id,
                groupValue: _selected?.id,
                onChanged: _sending ? null : (_) => setState(() {
                  _selected = reason;
                  _note.clear();
                }),
              ),
            if (_selected?.requireMessage == true)
              TextField(
                controller: _note,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '补充说明（必填）',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('取消')),
      FilledButton(
        onPressed: _selected == null || _sending ||
            (_selected!.requireMessage && _note.text.trim().isEmpty)
            ? null : _submit,
        child: Text(_sending ? '提交中…' : '提交举报'),
      ),
    ],
  );
}

/// 单个楼层
class _PostCard extends StatelessWidget {
  final Post post;
  final TopicDetail detail;
  final VoidCallback onLike;
  final VoidCallback onShowReactions;
  final VoidCallback onReply;
  final VoidCallback onCopyLink;
  final VoidCallback onChanged;
  final VoidCallback? onEdit;
  final VoidCallback onReport;
  final ValueChanged<String> onVote;
  final bool voting;
  final VoidCallback onBookmark;
  final bool bookmarking;
  final void Function(PostPoll, List<String>?) onPollVote;
  final Set<String> pollBusy;

  const _PostCard({
    required this.post,
    required this.detail,
    required this.onLike,
    required this.onShowReactions,
    required this.onReply,
    required this.onCopyLink,
    required this.onChanged,
    this.onEdit,
    required this.onReport,
    required this.onVote,
    required this.voting,
    required this.onBookmark,
    required this.bookmarking,
    required this.onPollVote,
    required this.pollBusy,
  });

  Future<void> _openAvatarLink(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;

    final body = post.hidden
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('该帖已被社区隐藏', style: TextStyle(color: muted)),
          )
        : HtmlWidget(
            post.cooked,
            onTapUrl: (url) async {
              final uri = Uri.parse(AppState.baseUrl).resolve(url);
              if (uri.scheme != 'https' && uri.scheme != 'http') return true;
              final id = inAppTopicId(uri, Uri.parse(AppState.baseUrl));
              if (id != null && context.mounted) {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => TopicDetailScreen(topicId: id),
                ));
                return true;
              }
              // Floor-specific links must retain their post number. The
              // browser can load even a post outside the app's first batch.
              await _openAvatarLink(uri.toString());
              return true;
            },
            // 图片：点击进入全屏查看器（缩放 / 双击 / 多图翻页）
            customWidgetBuilder: (element) {
              if (element.classes.contains('poll') && post.polls.any((poll) =>
                  poll.name == element.attributes['data-poll-name'])) {
                return const SizedBox.shrink();
              }
              if (element.localName != 'img') return null;
              final rawSrc = element.attributes['src'] ?? '';
              final src = Uri.parse(AppState.baseUrl).resolve(rawSrc).toString();
              if (!src.startsWith('https://') && !src.startsWith('http://')) return null;
              final images = _extractImages(post.cooked);
              final index = images.indexOf(src);
              return GestureDetector(
                onTap: () => ImageViewer.show(
                  context,
                  urls: images,
                  initialIndex: index < 0 ? 0 : index,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: src,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (_, __, ___) => const SizedBox(
                      height: 120,
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              );
            },
            customStylesBuilder: (element) {
              switch (element.localName) {
                case 'blockquote':
                  return {
                    'border-left': '3px solid ${cssHex(scheme.primary)}',
                    'background': cssHex(scheme.surfaceContainerHighest),
                    'padding': '8px 12px',
                    'margin': '8px 0',
                    'border-radius': '6px',
                  };
                case 'pre':
                  return {
                    'background': cssHex(scheme.surfaceContainerHighest),
                    'padding': '12px',
                    'border-radius': '8px',
                  };
                case 'code':
                  return {'font-family': 'monospace', 'font-size': '13px'};
                case 'a':
                  return {'color': cssHex(scheme.primary)};
                case 'img':
                  return {'max-width': '100%', 'border-radius': '8px'};
              }
              return null;
            },
          );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  avatarTemplate: post.avatarTemplate,
                  username: post.username,
                  size: 38,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: InkWell(
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => PublicProfileScreen(username: post.username),
                              )),
                              child: Text(
                                post.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('#${post.postNumber}',
                              style: TextStyle(fontSize: 11.5, color: muted)),
                        ],
                      ),
                      Text(
                        timeAgo(post.createdAt),
                        style: TextStyle(fontSize: 11.5, color: muted),
                      ),
                    ],
                  ),
                ),
                if (post.replyToPostNumber != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '回复 #${post.replyToPostNumber}',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  tooltip: '更多',
                  onSelected: (v) {
                    if (v == 'copy') onCopyLink();
                    if (v == 'edit') onEdit?.call();
                    if (v == 'report') onReport();
                    if (v == 'bookmark') onBookmark();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'copy', child: Text('复制楼层链接')),
                    PopupMenuItem(value: 'bookmark', enabled: !bookmarking,
                      child: Text(post.bookmarked ? '取消收藏此楼层' : '收藏此楼层')),
                    if (onEdit != null)
                      const PopupMenuItem(value: 'edit', child: Text('编辑帖子')),
                    const PopupMenuItem(value: 'report', child: Text('举报帖子')),
                  ],
                  icon: Icon(Icons.more_horiz, size: 20, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            body,
            if (!post.hidden)
              for (final poll in post.polls)
                PollCard(
                  key: ValueKey('${post.id}:${poll.name}'),
                  poll: poll, myVotes: post.pollsVotes[poll.name] ?? const [],
                  busy: pollBusy.contains('${post.id}:${poll.name}'),
                  loggedIn: context.watch<AppState>().isLoggedIn,
                  onVote: (options) => onPollVote(poll, options),
                  onRemove: () => onPollVote(poll, null),
                ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (post.voteScore != null) ...[
                  IconButton(
                    tooltip: post.voteDirection == 'up' ? '撤回赞成票' : '赞成',
                    onPressed: voting ? null : () => onVote('up'),
                    icon: Icon(post.voteDirection == 'up'
                        ? Icons.arrow_circle_up : Icons.arrow_circle_up_outlined),
                  ),
                  Text('${post.voteScore}', style: const TextStyle(fontSize: 13)),
                  IconButton(
                    tooltip: post.voteDirection == 'down' ? '撤回反对票' : '反对',
                    onPressed: voting || (!post.canVoteDown && post.voteDirection != 'down')
                        ? null : () => onVote('down'),
                    icon: Icon(post.voteDirection == 'down'
                        ? Icons.arrow_circle_down : Icons.arrow_circle_down_outlined),
                  ),
                ],
                // 表情反应区：单击 toggle 心、长按打开选择器
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onLike,
                  onLongPress: onShowReactions,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          post.currentUserReaction != null
                              ? reactionEmoji(post.currentUserReaction)
                              : '❤',
                          style: const TextStyle(fontSize: 15),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          post.reactionUsersCount > 0
                              ? '${post.reactionUsersCount}'
                              : '赞',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: post.currentUserReaction != null
                                ? NL.love
                                : muted,
                            fontWeight: post.currentUserReaction != null
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 小箭头点击展开表情选择器
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onShowReactions,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 6),
                    child: Icon(Icons.expand_less,
                        size: 16, color: muted),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: onReply,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: Icon(Icons.reply, size: 17, color: muted),
                  label: Text('回复', style: TextStyle(fontSize: 12.5, color: muted)),
                ),
                const Spacer(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 表情反应选择芯片
class _ReactionChip extends StatelessWidget {
  final String emoji;
  final String label;
  final int count;
  final bool highlighted;
  final VoidCallback onTap;

  const _ReactionChip({
    required this.emoji,
    required this.label,
    required this.count,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: highlighted
              ? NL.love.withOpacity(0.18)
              : scheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: highlighted
              ? Border.all(color: NL.love.withOpacity(0.5), width: 1.4)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 3),
            Text(
              count > 0 ? '$count' : label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: highlighted ? NL.love : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
