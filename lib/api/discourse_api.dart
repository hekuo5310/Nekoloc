import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../models.dart';

/// 业务异常（展示给用户的错误信息）
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

/// 需要双重验证（2FA/TOTP）
class SecondFactorRequiredException implements Exception {
  final String message;
  SecondFactorRequiredException(this.message);
  @override
  String toString() => message;
}

/// 未登录 / 会话过期
class UnauthorizedException extends ApiException {
  UnauthorizedException([String message = '未登录或登录已过期']) : super(message, 401);
}

/// Discourse 用户级 API 客户端
/// 双模式：Cookie 会话（账号密码登录）或 User-Api-Key（浏览器授权登录）
class DiscourseApi {
  final String base;
  final Dio _dio;
  final String? userApiKey;
  String? _csrf;

  DiscourseApi({required this.base, required CookieJar jar, this.userApiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: base,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 45),
          headers: _buildHeaders(userApiKey),
          validateStatus: (status) => status != null && status < 500,
        )) {
    _dio.interceptors.add(CookieManager(jar));
  }

  static Map<String, String> _buildHeaders(String? apiKey) {
    return {
      'Accept': 'application/json',
      'X-Requested-With': 'XMLHttpRequest',
      'User-Agent':
          'Nekoloc/1.3 (+https://github.com/hekuo5310/Nekoloc)',
      if (apiKey != null) 'User-Api-Key': apiKey,
    };
  }

  // ---------------------------------------------------------------- 基础封装

  Future<Map<String, dynamic>> _getJson(String path,
      {Map<String, dynamic>? query}) async {
    try {
      final resp = await _dio.get(path, queryParameters: query);
      return _handle(resp);
    } on DioException catch (e) {
      throw _dioError(e);
    }
  }

  Map<String, dynamic> _handle(Response resp) {
    final map =
        resp.data is Map ? Map<String, dynamic>.from(resp.data as Map) : <String, dynamic>{};
    final code = resp.statusCode ?? 500;
    if (code == 401) throw UnauthorizedException();
    if (code == 403) {
      throw ApiException(_errorMessage(map, code), 403);
    }
    if (code >= 400) throw ApiException(_errorMessage(map, code), code);
    return map;
  }

  Future<Map<String, dynamic>> _mutate(String method, String path,
      {Map<String, dynamic>? data, Map<String, dynamic>? query}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (userApiKey == null) await ensureCsrf();
      try {
        final resp = await _dio.request(
          path,
          data: data,
          queryParameters: query,
          options: Options(
            method: method,
            contentType: Headers.formUrlEncodedContentType,
            headers: {if (_csrf != null && userApiKey == null) 'X-CSRF-Token': _csrf},
          ),
        );
        final map = resp.data is Map
            ? Map<String, dynamic>.from(resp.data as Map)
            : <String, dynamic>{};
        final code = resp.statusCode ?? 500;
        // CSRF 过期 → 重新获取后重试一次
        if (userApiKey == null && code == 403 && attempt == 0 && _isBadCsrf(map)) {
          _csrf = null;
          continue;
        }
        if (code == 401) throw UnauthorizedException();
        if (code >= 400) throw ApiException(_errorMessage(map, code), code);
        return map;
      } on DioException catch (e) {
        throw _dioError(e);
      }
    }
    throw ApiException('请求失败，请重试');
  }

  bool _isBadCsrf(Map<String, dynamic> map) =>
      map.toString().toUpperCase().contains('CSRF');

  String _errorMessage(Map<String, dynamic> map, int code) {
    final err = map['error'] ?? map['errors'] ?? map['message'];
    if (err is List && err.isNotEmpty) {
      final first = err.first;
      if (first is Map && first.containsKey('message')) return first['message'].toString();
      return first.toString();
    }
    if (err is String && err.isNotEmpty) return err;
    return '请求失败 (HTTP $code)';
  }

  ApiException _dioError(DioException e) {
    final response = e.response;
    if (response != null) {
      final data = response.data;
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final code = response.statusCode ?? 500;
      if (code == 401) return UnauthorizedException();
      return ApiException(_errorMessage(map, code), code);
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return ApiException('网络连接失败，请检查网络或站点地址是否正确');
    }
    return ApiException(e.message ?? '网络错误');
  }

  Future<void> ensureCsrf() async {
    // User API Key authenticates independently of the browser cookie session.
    if (userApiKey != null) return;
    if (_csrf != null) return;
    try {
      final resp = await _dio.get('/session/csrf.json');
      if (resp.statusCode == 200 && resp.data is Map) {
        _csrf = (resp.data as Map)['csrf']?.toString();
      }
    } on DioException catch (e) {
      throw _dioError(e);
    }
    if (_csrf == null) throw ApiException('无法获取 CSRF 令牌，站点可能开启了防火墙拦截');
  }

  // ---------------------------------------------------------------- 会话

  /// 账号密码登录（用户名或邮箱 + 密码，可选 TOTP 动态口令）
  /// 注意：部分 Discourse 站点登录失败也返回 HTTP 200 + error 字段
  Future<Map<String, dynamic>> login({
    required String login,
    required String password,
    String? totp,
  }) async {
    await ensureCsrf();
    final data = <String, dynamic>{'login': login, 'password': password};
    if (totp != null && totp.trim().isNotEmpty) {
      data['second_factor_method'] = '1';
      data['second_factor_token'] = totp.trim();
    }
    Response resp;
    try {
      resp = await _dio.post(
        '/session',
        data: data,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'X-CSRF-Token': _csrf},
        ),
      );
    } on DioException catch (e) {
      throw _dioError(e);
    }
    final map = resp.data is Map
        ? Map<String, dynamic>.from(resp.data as Map)
        : <String, dynamic>{};

    // CSRF 失效时提示重试，避免站点持续返回 403 导致无限递归。
    if (resp.statusCode == 403 && _isBadCsrf(map)) {
      _csrf = null;
      throw ApiException('登录令牌已过期，请重试', 403);
    }

    final user = map['user'];
    if (resp.statusCode == 200 && user != null && map['error'] == null) {
      return Map<String, dynamic>.from(user as Map);
    }

    final msg = _errorMessage(map, resp.statusCode ?? 0);
    if (_needsSecondFactor(map, msg)) throw SecondFactorRequiredException(msg);
    throw ApiException(msg, resp.statusCode);
  }

  bool _needsSecondFactor(Map<String, dynamic> map, String msg) {
    final hay = '$map $msg'.toLowerCase();
    const hints = [
      'second factor', 'second_factor', '2fa', 'otp', 'authenticator',
      '双重', '两步', '动态口令', '动态密码', '验证器',
    ];
    return hints.any(hay.contains);
  }

  Future<CurrentUser> currentUser() async {
    final d = await _getJson('/session/current.json');
    final u = d['current_user'];
    if (u == null) throw UnauthorizedException();
    return CurrentUser.fromJson(u);
  }

  Future<void> logout() async {
    try {
      await _mutate('DELETE', '/session');
    } catch (_) {}
  }

  Future<SiteInfo> siteBasicInfo() async {
    final d = await _getJson('/site/basic-info.json');
    return SiteInfo.fromJson(d);
  }

  // ---------------------------------------------------------------- 话题

  /// filter: latest / top / new / unread / after
  Future<TopicListResult> topicList(String filter, {int page = 0}) async {
    final d = await _getJson('/$filter.json', query: {'page': page});
    return TopicListResult.fromJson(d);
  }

  Future<TopicListResult> categoryTopics(int categoryId, {int page = 0}) async {
    final d = await _getJson('/c/$categoryId.json', query: {'page': page});
    return TopicListResult.fromJson(d);
  }

  /// 与官方客户端一致：标签话题列表复用 topic_list 响应。
  Future<TopicListResult> tagTopics(String tag, {int page = 0}) async {
    final d = await _getJson('/tag/${Uri.encodeComponent(tag)}.json',
        query: {'page': page});
    return TopicListResult.fromJson(d);
  }

  Future<List<PostFlagReason>> postFlagReasons({String? username}) async {
    final site = await _getJson('/site.json');
    final reasons = <PostFlagReason>[];
    for (final entry in (site['post_action_types'] as List?) ?? []) {
      final reason = PostFlagReason.fromJson(entry, username: username);
      if (reason != null) reasons.add(reason);
    }
    reasons.sort((a, b) => a.position.compareTo(b.position));
    return reasons;
  }

  Future<void> flagPost(int postId, PostFlagReason reason, String message) async {
    if (reason.requireMessage && message.trim().isEmpty) {
      throw ArgumentError.value(message, 'message', '此举报理由需要说明');
    }
    await _mutate('POST', '/post_actions', data: {
      'id': postId.toString(),
      'post_action_type_id': reason.id.toString(),
      'flag_topic': 'false',
      if (message.trim().isNotEmpty) 'message': message.trim(),
    });
  }

  /// discourse-vote: direction 是目标状态（up / down / none）。
  Future<Map<String, dynamic>> castPostVote(int postId, String direction) {
    if (!const {'up', 'down', 'none'}.contains(direction)) {
      throw ArgumentError.value(direction, 'direction');
    }
    return _mutate('PUT', '/vote/posts/$postId', data: {'direction': direction});
  }

  /// categories（含子分类，展平后返回）
  /// 注：Discourse 中顶级分类通常只是容器，实际发帖发生在子分类
  Future<List<Category>> categories({bool includeSubcategories = true}) async {
    final d = await _getJson('/categories.json', query: {
      if (includeSubcategories) 'include_subcategories': 'true',
    });
    final list = (d['category_list'] as Map?)?['categories'] as List? ?? [];
    final result = <Category>[];
    for (final e in list) {
      final top = Category.fromJson(e);
      result.add(top);
      for (final s in (e['subcategory_list'] as List? ?? [])) {
        final sub = Category.fromJson(s);
        result.add(Category(
          id: sub.id,
          name: sub.name,
          color: sub.color,
          textColor: sub.textColor,
          slug: sub.slug,
          topicCount: sub.topicCount,
          descriptionExcerpt: sub.descriptionExcerpt,
          parentId: top.id,
          position: sub.position,
          readRestricted: sub.readRestricted,
        ));
      }
    }
    return result;
  }

  Future<TopicDetail> topic(int id) async {
    final d = await _getJson('/t/$id.json');
    return TopicDetail.fromJson(d);
  }

  /// 分页拉取话题内更多楼层
  Future<List<Post>> topicPosts(int topicId, List<int> postIds) async {
    if (postIds.isEmpty) return [];
    final d = await _getJson('/t/$topicId/posts.json', query: {'post_ids[]': postIds});
    final list = (d['post_stream'] as Map?)?['posts'] as List? ?? [];
    return list.map((e) => Post.fromJson(e)).toList();
  }

  /// Fetch the original Markdown before editing; cooked HTML loses formatting.
  Future<String> postRaw(int postId) async {
    final d = await _getJson('/posts/$postId.json');
    final raw = d['raw'];
    if (raw is! String) throw ApiException('无法获取原始正文，请在网页版编辑');
    return raw;
  }

  Future<void> updatePost(int postId, String raw) async {
    await _mutate('PUT', '/posts/$postId.json', data: {'post[raw]': raw});
  }

  /// Discourse levels: muted 0, normal 1, tracking 2, watching 3.
  Future<void> setTopicNotificationLevel(int topicId, int level) async {
    if (level < 0 || level > 3) throw ArgumentError.value(level, 'level');
    await _mutate('POST', '/t/$topicId/notifications.json',
        data: {'notification_level': level.toString()});
  }

  /// 创建新话题。[mobileSource] 为发帖设备信息（mobile_source_* 字段，可空）
  Future<Map<String, dynamic>> createTopic({
    required String title,
    required String raw,
    int? categoryId,
    Map<String, String>? mobileSource,
  }) =>
      _mutate('POST', '/posts', data: {
        'title': title,
        'raw': raw,
        if (categoryId != null) 'category': categoryId.toString(),
        ...?mobileSource,
      });

  /// 回复话题。[mobileSource] 为发帖设备信息（mobile_source_* 字段，可空）
  Future<Map<String, dynamic>> createReply({
    required int topicId,
    required String raw,
    int? replyToPostNumber,
    Map<String, String>? mobileSource,
  }) =>
      _mutate('POST', '/posts', data: {
        'topic_id': topicId.toString(),
        'raw': raw,
        if (replyToPostNumber != null) 'reply_to_post_number': replyToPostNumber.toString(),
        ...?mobileSource,
      });

  // ---------------------------------------------------------------- 点赞 / 表情反应

  Future<void> likePost(int postId) =>
      _mutate('POST', '/post_actions',
              data: {'id': postId.toString(), 'post_action_type_id': '2'})
          .then((_) {});

  Future<void> unlikePost(int postId) => _mutate('DELETE', '/post_actions/$postId',
      query: {'post_action_type_id': '2'}).then((_) {});

  /// 切换帖子表情反应（discourse-reactions 插件）。
  /// 端点：PUT /discourse-reactions/posts/{id}/custom-reactions/{emoji}/toggle.json
  /// 返回更新后的 post JSON（含 current_user_reaction / reactions）
  Future<Map<String, dynamic>> toggleReaction(int postId, String reactionId) =>
      _mutate(
        'PUT',
        '/discourse-reactions/posts/$postId/custom-reactions/$reactionId/toggle.json',
      );

  // ---------------------------------------------------------------- 通知

  Future<List<NotificationItem>> notifications() async {
    final d = await _getJson('/notifications.json', query: {'recent': 'true', 'limit': '50'});
    final list = d['notifications'] as List? ?? [];
    return list.map((e) => NotificationItem.fromJson(e)).toList();
  }

  Future<void> markNotificationRead(int id) =>
      _mutate('PUT', '/notifications/$id/mark-read').then((_) {});

  Future<void> markAllNotificationsRead() =>
      _mutate('PUT', '/notifications/mark-read').then((_) {});

  // ---------------------------------------------------------------- 用户

  Future<UserProfile> userProfile(String username) async {
    final d = await _getJson('/u/${Uri.encodeComponent(username)}.json');
    return UserProfile.fromJson(d['user'] ?? const {});
  }

  Future<void> followUser(String username) =>
      _mutate('PUT', '/follow/${Uri.encodeComponent(username)}').then((_) {});

  Future<void> unfollowUser(String username) =>
      _mutate('DELETE', '/follow/${Uri.encodeComponent(username)}').then((_) {});

  /// Discourse 要求忽略用户时携带到期时间；恢复使用 normal 级别。
  Future<void> setUserIgnored(String username, bool ignored) async {
    await _mutate('PUT', '/u/${Uri.encodeComponent(username)}/notification_level', data: {
      'notification_level': ignored ? 'ignore' : 'normal',
      if (ignored) 'expiring_at': DateTime.now().toUtc()
          .add(const Duration(days: 3650)).toIso8601String(),
    });
  }

  Future<TopicListResult> userTopics(String username, {int page = 0}) async {
    final d = await _getJson('/topics/created-by/$username.json', query: {'page': page});
    return TopicListResult.fromJson(d);
  }

  // ---------------------------------------------------------------- 搜索

  Future<SearchResult> search(String q, {int page = 1}) async {
    final d = await _getJson('/search.json', query: {'q': q, 'page': page});
    return SearchResult.fromJson(d);
  }

  Future<PollVoteResult> votePoll(int postId, String pollName,
      List<String> options) async {
    if (options.isEmpty) throw ApiException('请选择投票选项');
    return PollVoteResult.fromJson(await _mutate('PUT', '/polls/vote', data: {
      'post_id': postId.toString(), 'poll_name': pollName, 'options[]': options,
    }));
  }

  Future<PollVoteResult> removePollVote(int postId, String pollName) async =>
      PollVoteResult.fromJson(await _mutate('DELETE', '/polls/vote', data: {
        'post_id': postId.toString(), 'poll_name': pollName,
      }));

  // ---------------------------------------------------------------- 私信

  Future<TopicListResult> privateMessages(String username, {int page = 0}) async {
    final d = await _getJson('/topics/private-messages/$username.json',
        query: {'page': page});
    return TopicListResult.fromJson(d);
  }

  /// 创建私信。注意：Nodeloc 要求 target_usernames 为数组格式（重复键）
  Future<Map<String, dynamic>> createPrivateMessage({
    required String title,
    required String raw,
    required List<String> targetUsernames,
  }) =>
      _mutate('POST', '/posts', data: {
        'archetype': 'private_message',
        'title': title,
        'raw': raw,
        'target_usernames[]': targetUsernames,
      });

  // ---------------------------------------------------------------- 收藏

  /// 收藏某楼层（新版 API：bookmarkable_id + bookmarkable_type=Post）
  Future<int> addBookmark(int postId) async {
    final d = await _mutate('POST', '/bookmarks', data: {
      'bookmarkable_id': postId.toString(),
      'bookmarkable_type': 'Post',
    });
    final id = toInt(d['id']);
    if (id == null || id <= 0) throw ApiException('收藏失败：服务器未返回收藏编号');
    return id;
  }

  Future<void> removeBookmark(int bookmarkId) =>
      _mutate('DELETE', '/bookmarks/$bookmarkId').then((_) {});

  Future<List<BookmarkItem>> bookmarks(String username, {int page = 0}) async {
    final d = await _getJson('/u/${Uri.encodeComponent(username)}/bookmarks.json',
        query: {'page': page});
    final list =
        (d['user_bookmark_list'] as Map?)?['bookmarks'] as List? ?? [];
    return list.map((e) => BookmarkItem.fromJson(e)).toList();
  }

  // ---------------------------------------------------------------- 阅读进度

  /// 上报阅读时间（同步已读进度 / 新帖未读列表）
  Future<void> postTimings(int topicId, int totalMs, Map<int, int> postMs) async {
    final data = <String, dynamic>{
      'topic_id': topicId.toString(),
      'topic_time': totalMs.toString(),
    };
    postMs.forEach((postNumber, ms) {
      data['timings[$postNumber]'] = ms.toString();
    });
    try {
      await _mutate('POST', '/topics/timings', data: data);
    } catch (_) {
      // 阅读进度失败静默忽略
    }
  }

  // ---------------------------------------------------------------- 上传

  /// 上传图片（composer 用途），返回包含 url / short_url 的响应
  Future<Map<String, dynamic>> uploadImage({
    required String filePath,
    required String filename,
    void Function(int sent, int total)? onProgress,
  }) async {
    await ensureCsrf();
    final form = FormData.fromMap({
      'type': 'composer',
      'synchronous': 'true',
      'files[]': await MultipartFile.fromFile(filePath, filename: filename),
    });
    try {
      final resp = await _dio.post(
        '/uploads.json',
        data: form,
        onSendProgress: onProgress,
        options: Options(headers: {
          if (_csrf != null && userApiKey == null) 'X-CSRF-Token': _csrf,
        }),
      );
      final map = resp.data is Map
          ? Map<String, dynamic>.from(resp.data as Map)
          : <String, dynamic>{};
      final code = resp.statusCode ?? 500;
      if (code >= 400) throw ApiException(_errorMessage(map, code), code);
      return map;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw _dioError(e);
    }
  }

  // ---------------------------------------------------------------- 工具

  /// 头像模板 -> 完整 URL
  String? resolveAvatarUrl(String? template, {int size = 96}) {
    if (template == null || template.isEmpty) return null;
    var url = template.replaceAll('{size}', size.toString());
    if (url.startsWith('http')) return url;
    return '$base$url';
  }
}
