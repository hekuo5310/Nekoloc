import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:dio/dio.dart';

import '../account_models.dart';
import '../chat_models.dart';
import '../models.dart';
import '../plugins.dart';
import 'captcha.dart';
import 'v1_mapping.dart';

/// 业务异常（展示给用户的错误信息）
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  /// 服务端错误信封里的 `error.code`，如 `second_factor_required`。
  final String? code;
  ApiException(this.message, [this.statusCode, this.code]);
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
  UnauthorizedException([String message = '未登录或登录已过期']) : super(message, 401, 'unauthorized');
}

/// 新版站点没有对应接口的功能。入口应当已经隐藏；这里是最后一道保护。
class UnsupportedFeatureException extends ApiException {
  UnsupportedFeatureException([String message = '新版站点暂不支持此功能']) : super(message, null, 'unsupported');
}

/// 需要人机验证，但当前平台无法显示验证组件（或用户关闭了它）。
class CaptchaUnavailableException extends ApiException {
  CaptchaUnavailableException(String message) : super(message, null, 'captcha_unavailable');
}

/// NodeLoc 站点客户端（新版自建后端 `/api/v1`）。
///
/// 站点已从 Discourse 迁移到自建后端，旧的 Discourse 路径对客户端一律返回 410。
/// 这个类保留原来的方法名和返回类型，内部全部调用 `/api/v1`，再经 v1_mapping.dart
/// 映射回界面使用的模型，所以界面基本不用改。鉴权是 Bearer token（登录、注册、
/// 浏览器授权交换得到），错误统一为 `{"error":{"code","message","fields"}}`。
class DiscourseApi {
  static const String appVersion = '2.0.0';

  final String base;
  final Dio _dio;

  /// 会话 token。为 null 表示未登录。
  String? token;

  /// 两步验证通过后服务端发的“受信任设备”标记，之后登录可免输动态码。
  String? trustToken;

  /// 带着 token 的请求被服务端以 401 拒绝时调用（会话在别处被注销）。
  void Function()? onSessionRejected;

  /// 由界面层设置，用于完成人机验证。
  CaptchaSolver? captchaSolver;

  // 只在这个客户端实例里有效的缓存。
  List<Map>? _nodes;
  DateTime _nodesAt = DateTime.fromMillisecondsSinceEpoch(0);
  Map<String, Map>? _myNodes;
  final Map<String, String> _cursors = {};
  final Map<int, String> _directUsers = {};
  final Map<String, int> _pollIds = {};
  final Map<int, String> _uploadUrls = {};
  CaptchaConfig? _captcha;
  DateTime _captchaAt = DateTime.fromMillisecondsSinceEpoch(0);
  int? _meId;
  String? _meName;

  static const int _page = 30;
  static const int _threadPage = 20;

  DiscourseApi({required this.base, this.token, this.trustToken, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: base,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 60),
              // 状态码统一在 _check 里处理，好读出错误信封。
              validateStatus: (status) => status != null,
              responseType: ResponseType.plain,
            )) {
    final host = Uri.parse(base).host;
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      options.headers['Accept'] ??= 'application/json';
      // 服务端靠 User-Agent 区分新旧客户端；登录响应只在请求不像浏览器时才带 token，
      // 所以这里绝不能出现 Sec-Fetch-* 头。
      options.headers['User-Agent'] = userAgent;
      options.headers['Accept-Language'] ??= 'zh-CN,zh;q=0.9,en;q=0.6';
      // token 只发给站点本身；外站图片等请求不能看到它。
      if (token != null && options.uri.host == host && !options.headers.containsKey('Authorization')) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    }));
  }

  static String get userAgent {
    String os;
    try {
      os = Platform.operatingSystem;
    } catch (_) {
      os = 'unknown';
    }
    return 'Nekoloc/$appVersion (Flutter; $os; +https://github.com/hekuo5310/Nekoloc)';
  }

  bool get isLoggedIn => token != null;

  // ---------------------------------------------------------------- 基础封装

  Future<Map<String, dynamic>> _get(String path, {Map<String, dynamic>? query}) async {
    try {
      final resp = await _dio.get(path, queryParameters: query);
      return _check(resp);
    } on DioException catch (e) {
      throw _dioError(e);
    }
  }

  /// JSON 写请求。服务端拒绝空请求体，所以没有参数时也发送 `{}`。
  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    String? bearer,
  }) async {
    try {
      final resp = await _dio.request(
        path,
        data: jsonEncode(body ?? const {}),
        queryParameters: query,
        options: Options(
          method: method,
          contentType: Headers.jsonContentType,
          headers: {
            ...?headers,
            if (bearer != null) 'Authorization': 'Bearer $bearer',
          },
        ),
      );
      return _check(resp);
    } on DioException catch (e) {
      throw _dioError(e);
    }
  }

  Map<String, dynamic> _decode(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(data);
        if (parsed is Map) return Map<String, dynamic>.from(parsed);
        if (parsed is List) return {'_list': parsed};
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _check(Response resp) {
    final code = resp.statusCode ?? 500;
    final map = _decode(resp.data);
    if (code >= 200 && code < 300) return map;
    throw _fault(code, map, resp.headers.value('retry-after'), resp.requestOptions);
  }

  /// 服务端的消息已经是读者的语言，可直接展示；但 unauthorized / not_found
  /// 这类用我们自己的说法更清楚。
  static const _nonQuotable = {'unauthorized', 'not_found'};

  ApiException _fault(int code, Map<String, dynamic> map, String? retryAfter, RequestOptions request) {
    final envelope = map['error'];
    final type = envelope is Map ? envelope['code']?.toString() : map['error_type']?.toString();
    String? message;
    if (envelope is Map && code >= 400 && code < 500 && !_nonQuotable.contains(type)) {
      final parts = <String>[
        if (envelope['message'] != null) envelope['message'].toString(),
        if (envelope['fields'] is Map)
          for (final v in (envelope['fields'] as Map).values)
            if (v != null) v.toString(),
      ].map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().take(3).toList();
      if (parts.isNotEmpty) message = parts.join('\n');
    }
    if (code == 410 && map['errors'] is List && (map['errors'] as List).isNotEmpty) {
      message = (map['errors'] as List).first.toString().split('\n').first;
    }
    // 登录相关的 401（需要动态码、密码错误、需要验证码）带着自己的错误代码，
    // 只有没有代码或代码为 unauthorized 时才是会话失效。
    if (code == 401 && (type == null || type == 'unauthorized')) {
      if (request.headers.containsKey('Authorization') && token != null) onSessionRejected?.call();
      return UnauthorizedException();
    }
    if (code == 401 && message == null && envelope is Map && envelope['message'] != null) {
      message = envelope['message'].toString();
    }
    if (code == 429 && message == null) {
      final wait = int.tryParse(retryAfter ?? '');
      message = wait != null ? '操作太频繁，请 $wait 秒后重试' : '操作太频繁，请稍后再试';
    }
    return ApiException(message ?? _fallbackMessage(code), code, type);
  }

  /// 站点没有给出可读文案时的兜底。只描述用户能做什么，不暴露状态码。
  static String _fallbackMessage(int code) {
    if (code == 401 || code == 403) return '没有权限或登录已失效，请重新登录后再试';
    if (code == 404) return '内容不存在或已被删除';
    if (code == 410) return '这个版本已经停止支持，请更新到最新版本';
    if (code == 429) return '操作太频繁，请稍后再试';
    if (code >= 500) return '服务器开小差了，请稍后再试';
    return '请求失败，请稍后重试';
  }

  ApiException _dioError(DioException e) {
    final response = e.response;
    if (response != null) {
      final code = response.statusCode ?? 500;
      return _fault(code, _decode(response.data), response.headers.value('retry-after'), e.requestOptions);
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return ApiException('网络连接失败，请检查网络');
    }
    // e.message 是 Dio 的英文原文，不能展示；交给 friendlyError 归类。
    return ApiException('网络异常，请稍后重试');
  }

  static String _enc(String s) => Uri.encodeComponent(s);

  static String _device() {
    try {
      return 'Nekoloc ${Platform.operatingSystem}';
    } catch (_) {
      return 'Nekoloc';
    }
  }

  static String randomKey() {
    final rng = Random.secure();
    return List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  // ---------------------------------------------------------------- 人机验证

  /// 管理员会在后台实时切换，所以只缓存几分钟；被拒绝时强制重新读取。
  Future<CaptchaConfig> captchaConfig({bool force = false}) async {
    final fresh = DateTime.now().difference(_captchaAt) < const Duration(minutes: 5);
    if (!force && fresh && _captcha != null) return _captcha!;
    try {
      _captcha = CaptchaConfig.fromJson(await _get('/api/v1/auth/captcha'));
    } catch (_) {
      // 读不到就当作关闭：真需要时写请求本身会说，然后带 force 回到这里。
      _captcha = const CaptchaConfig();
    }
    _captchaAt = DateTime.now();
    return _captcha!;
  }

  Future<String> _solve(CaptchaConfig config, String action) async {
    final solver = captchaSolver;
    if (solver == null) {
      throw CaptchaUnavailableException('需要完成人机验证，当前设备无法显示验证组件，请使用“浏览器登录”');
    }
    final token = await solver(config, action);
    if (token == null || token.isEmpty) throw CaptchaUnavailableException('已取消人机验证');
    return token;
  }

  /// 需要验证码时先拿到 token 再执行 [block]；[upfront] 表示第一次尝试前就验证。
  /// 未预先验证而服务端回答 `captcha_required` / `captcha_invalid` 时，验证一次再重试一次。
  Future<T> _guarded<T>(String action, bool upfront, Future<T> Function(String? captcha) block) async {
    final config = await captchaConfig();
    final first = upfront && config.guards(action) ? await _solve(config, action) : null;
    try {
      return await block(first);
    } on ApiException catch (e) {
      if (e.code != 'captcha_required' && e.code != 'captcha_invalid') rethrow;
      final current = await captchaConfig(force: true);
      if (current.siteKey.isEmpty) rethrow;
      return block(await _solve(current, action));
    }
  }

  // ---------------------------------------------------------------- 会话

  /// 账号密码登录（用户名或邮箱 + 密码，可选动态码或备用码）。
  /// 成功后 [token] 已设置，返回服务端的用户对象。
  Future<Map<String, dynamic>> login({
    required String login,
    required String password,
    String? totp,
  }) async {
    final code = totp?.trim();
    final hasCode = code != null && code.isNotEmpty;
    // 输入动态码时服务端记得上一步已通过验证码（十分钟内），不再重复要求。
    final upfront = !hasCode && (await captchaConfig()).loginUpfront;
    final Map<String, dynamic> d;
    try {
      d = await _guarded(CaptchaAction.login, upfront, (captcha) {
        return _send('POST', '/api/v1/auth/login',
            body: {
              'login': login.trim(),
              'password': password,
              if (hasCode) 'code': code,
              // 需要动态码说明账号开了两步验证；刚通过验证的设备就是要信任的设备。
              'trust_device': hasCode,
              if (captcha != null) 'captcha': captcha,
              'device': _device(),
            },
            headers: {if (trustToken != null) 'X-Nodeloc-Trust': trustToken!});
      });
    } on ApiException catch (e) {
      if (e.code == 'second_factor_required') {
        throw SecondFactorRequiredException(e.message.isNotEmpty ? e.message : '此账号已开启两步验证，请输入动态码');
      }
      rethrow;
    }
    final trust = d['trust_token']?.toString();
    if (trust != null && trust.isNotEmpty) trustToken = trust;
    return _adopt(d);
  }

  Map<String, dynamic> _adopt(Map<String, dynamic> d) {
    final t = d['token']?.toString();
    final user = d['user'];
    if (t == null || t.isEmpty) throw ApiException('登录没有返回会话，请重试');
    if (user is! Map || (user['username']?.toString() ?? '').isEmpty) {
      throw ApiException('登录未完成，请重试');
    }
    token = t;
    _meId = toInt(user['id']);
    _meName = user['username']?.toString();
    return Map<String, dynamic>.from(user);
  }

  /// 浏览器授权登录的回调：用一次性 code（配合 PKCE verifier）换取会话。
  Future<Map<String, dynamic>> exchangeAuthCode(String code, {String? verifier}) async {
    final d = await _send('POST', '/api/v1/auth/app/exchange', body: {
      'code': code,
      if (verifier != null) 'code_verifier': verifier,
      'device': _device(),
    });
    return _adopt(d);
  }

  Future<CurrentUser> currentUser() async {
    if (token == null) throw UnauthorizedException();
    final d = await _get('/api/v1/me');
    final user = d['user'] is Map ? d['user'] as Map : const {};
    var unread = 0;
    try {
      unread = toInt((await _get('/api/v1/notifications', query: {'limit': 1}))['unread']) ?? 0;
    } catch (_) {}
    final me = currentUserFrom(user, unread: unread);
    _meId = me.id;
    _meName = me.username;
    return me;
  }

  /// 注销会话。失败也不影响本地退出：会话会自然过期。
  Future<void> logout() async {
    final t = token;
    if (t == null) return;
    try {
      await _send('POST', '/api/v1/auth/logout', bearer: t);
    } catch (_) {}
    token = null;
    _meId = null;
    _meName = null;
  }

  Future<SiteInfo> siteBasicInfo() async =>
      SiteInfo(title: 'NodeLoc', description: '自由、平等、友好、开放、有趣的互联网交流社区');

  /// 站点支持的第三方登录方式（名称、显示名、入口地址）。
  Future<List<({String name, String label, String url})>> authProviders() async {
    final d = await _get('/api/v1/auth/providers');
    return [
      for (final p in ((d['providers'] as List?) ?? const []).whereType<Map>())
        (
          name: p['name']?.toString() ?? '',
          label: p['label']?.toString() ?? p['name']?.toString() ?? '',
          url: p['url']?.toString() ?? '',
        ),
    ];
  }

  // ---------------------------------------------------------------- 节点目录

  /// 节点目录：每 10 分钟刷新一次，登录后合并“已加入”状态。
  Future<List<Map>> _nodeDirectory({bool force = false}) async {
    final fresh = DateTime.now().difference(_nodesAt) < const Duration(minutes: 10);
    if (!force && fresh && _nodes != null) return _nodes!;
    final d = await _get('/api/v1/nodes');
    final list = ((d['nodes'] as List?) ?? const []).whereType<Map>().map((e) => Map.from(e)).toList();
    if (token != null) {
      try {
        final mine = await _get('/api/v1/me/nodes');
        final joined = {
          for (final n in ((mine['joined'] as List?) ?? const []).whereType<Map>()) n['slug']?.toString(): n,
        };
        _myNodes = {for (final e in joined.entries) if (e.key != null) e.key!: e.value};
        for (final n in list) {
          if (joined.containsKey(n['slug']?.toString())) n['joined'] = true;
        }
      } catch (_) {}
    }
    _nodes = list;
    _nodesAt = DateTime.now();
    return list;
  }

  int? _nodeIdOfSync(String? slug) {
    if (slug == null) return null;
    for (final n in _nodes ?? const <Map>[]) {
      if (n['slug']?.toString() == slug) return toInt(n['id']);
    }
    return null;
  }

  Future<String> _nodeSlug(int id) async {
    for (final n in await _nodeDirectory()) {
      if (toInt(n['id']) == id) return n['slug']?.toString() ?? '';
    }
    for (final n in await _nodeDirectory(force: true)) {
      if (toInt(n['id']) == id) return n['slug']?.toString() ?? '';
    }
    throw ApiException('节点不存在或已被删除', 404, 'not_found');
  }

  /// 确保节点目录已加载，好把话题里的节点别名换成节点 id。失败不影响主流程。
  Future<void> _warmNodes() async {
    if (_nodes != null) return;
    try {
      await _nodeDirectory();
    } catch (_) {}
  }

  // ---------------------------------------------------------------- 话题

  /// 游标分页只能一页一页往后：第 N 页的游标来自第 N-1 页的响应。
  Future<TopicListResult> _topicPage(
    String key,
    String path,
    Map<String, dynamic> query,
    int page, {
    bool offsetPaging = false,
  }) async {
    final params = {...query, 'limit': _page};
    if (offsetPaging) {
      if (page > 0) params['offset'] = page * _page;
    } else if (page > 0) {
      final cursor = _cursors['$key|$page'];
      if (cursor == null) return TopicListResult(topics: const [], users: const {}, hasMore: false);
      params['cursor'] = cursor;
    }
    await _warmNodes();
    final d = await _get(path, query: params);
    final next = d['next_cursor']?.toString();
    if (next != null) _cursors['$key|${page + 1}'] = next;
    return topicListFrom(d, nodeIdOf: _nodeIdOfSync);
  }

  /// filter：latest 最新 / top 热门 / rising 上升中 / featured 精选 / following 我加入的节点。
  Future<TopicListResult> topicList(String filter, {int page = 0}) => switch (filter) {
        'top' || 'hot' => _topicPage('hot', '/api/v1/topics', {'sort': 'hot'}, page, offsetPaging: true),
        'rising' => _topicPage('rising', '/api/v1/topics', {'sort': 'rising'}, page, offsetPaging: true),
        'featured' => _topicPage('featured', '/api/v1/topics', {'featured': 1}, page),
        'following' => _topicPage('following', '/api/v1/topics', {'joined': 1}, page),
        'best' => _topicPage('best', '/api/v1/feed/personal', const {}, page, offsetPaging: true),
        _ => _topicPage('latest', '/api/v1/topics', const {}, page),
      };

  Future<TopicListResult> categoryTopics(int categoryId, {int page = 0}) async {
    final slug = await _nodeSlug(categoryId);
    return _topicPage('node:$slug', '/api/v1/topics', {'node': slug}, page);
  }

  Future<TopicListResult> tagTopics(String tag, {int page = 0}) =>
      _topicPage('tag:$tag', '/api/v1/topics', {'tag': tag}, page);

  Future<List<PostFlagReason>> postFlagReasons({String? username}) async => reportReasons();

  Future<void> flagPost(int postId, PostFlagReason reason, String message) async {
    if (reason.requireMessage && message.trim().isEmpty) {
      throw ArgumentError.value(message, 'message', '此举报理由需要说明');
    }
    await _send('POST', '/api/v1/posts/$postId/reports', body: {
      'reason': reportReasonCodeFor(reason.id),
      if (message.trim().isNotEmpty) 'note': message.trim(),
    });
  }

  /// direction 是目标状态（up / down / none）。返回旧格式的投票结果，界面按它更新。
  Future<Map<String, dynamic>> castPostVote(int postId, String direction) async {
    if (!const {'up', 'down', 'none'}.contains(direction)) {
      throw ArgumentError.value(direction, 'direction');
    }
    final d = await _send('PUT', '/api/v1/posts/$postId/vote', body: {'value': voteValueOf(direction)});
    final up = toInt(d['upvotes']) ?? 0;
    final down = toInt(d['downvotes']) ?? 0;
    final viewer = toInt(d['viewer_vote']) ?? voteValueOf(direction);
    return {
      'id': postId,
      'vote_score': up - down,
      'vote_direction': voteDirectionOf(viewer),
      'can_vote_down': true,
      'like_count': up,
      'acted': viewer > 0,
    };
  }

  /// 节点（含子节点，展平后返回）。
  Future<List<Category>> categories({bool includeSubcategories = true}) async {
    final all = await _nodeDirectory();
    final list = all.map(categoryFrom).toList();
    return includeSubcategories ? list : list.where((c) => c.parentId == null).toList();
  }

  int? _viewerId() => _meId;

  /// 话题第一页，并补上新接口分开提供的数据：投票、一楼的抽奖、话题红包。
  /// [postNumber] 指定要定位的楼层：先取第一页（含一楼），不在其中时再取该楼层往后的一页。
  Future<TopicDetail> topic(int id, {int? postNumber}) async {
    if (postNumber != null && postNumber < 1) {
      throw ArgumentError.value(postNumber, 'postNumber', 'Must be positive');
    }
    await _warmNodes();
    final page = await _get('/api/v1/topics/$id', query: {'limit': _page});
    final moderate = (page['permissions'] is Map) && (page['permissions'] as Map)['moderate'] == true;
    var rawPosts = ((page['posts'] as List?) ?? const []).whereType<Map>().toList();
    var nextAfter = toInt(page['next_after']);
    int? gapAfter;
    int? gapBefore;
    if (postNumber != null && postNumber > 1 && !rawPosts.any((p) => toInt(p['post_number']) == postNumber)) {
      try {
        final later = await _get('/api/v1/topics/$id', query: {'limit': _page, 'after': postNumber - 1});
        final more = ((later['posts'] as List?) ?? const []).whereType<Map>();
        final seen = rawPosts.map((p) => toInt(p['id'])).toSet();
        final firstPageEnd = rawPosts.map((p) => toInt(p['post_number']) ?? 0).fold(0, max);
        rawPosts = [...rawPosts, ...more.where((p) => !seen.contains(toInt(p['id'])))];
        // 中间的楼层记为缺口，阅读器可以按需补齐；继续加载从定位楼层之后接着往下。
        nextAfter = toInt(later['next_after']);
        if (postNumber > firstPageEnd + 1) {
          gapAfter = firstPageEnd;
          gapBefore = postNumber;
        }
      } catch (_) {}
    }
    var posts = rawPosts
        .where((p) => p['kind']?.toString() != 'action')
        .map((p) => postFrom(p, topicId: id, viewerId: _viewerId(), canModerate: moderate))
        .toList();

    TopicRedEnvelope? envelope;
    Map<int, RedEnvelopeClaim> claims = const {};
    PostLottery? lottery;
    final firstId = posts.where((p) => p.postNumber == 1).map((p) => p.id).firstOrNull;
    final pollsByPost = <int, List>{};
    await Future.wait([
      () async {
        try {
          final e = (await _get('/api/v1/topics/$id/red-envelope'))['red_envelope'];
          if (e is Map) {
            envelope = redEnvelopeFrom(e);
            claims = redEnvelopeClaimsFrom(e);
          }
        } catch (_) {}
      }(),
      if (firstId != null)
        () async {
          try {
            final l = (await _get('/api/v1/posts/$firstId/lottery'))['lottery'];
            if (l is Map) lottery = lotteryFrom(l);
          } catch (_) {}
        }(),
      for (final p in posts.where((p) => _pollMarkup.hasMatch(p.cooked)))
        () async {
          try {
            pollsByPost[p.id] = await _pollsFor(p.id);
          } catch (_) {}
        }(),
    ]);
    posts = [
      for (final p in posts)
        Post(
          id: p.id,
          postNumber: p.postNumber,
          topicId: p.topicId,
          username: p.username,
          avatarTemplate: p.avatarTemplate,
          cooked: p.cooked,
          createdAt: p.createdAt,
          likeCount: p.likeCount,
          likedByMe: p.likedByMe,
          canEdit: p.canEdit,
          hidden: p.hidden,
          replyToPostNumber: p.replyToPostNumber,
          bookmarked: p.bookmarked,
          bookmarkId: p.bookmarkId,
          voteScore: p.voteScore,
          voteDirection: p.voteDirection,
          canVoteDown: p.canVoteDown,
          polls: (pollsByPost[p.id] ?? const []).whereType<Map>().map(pollFrom).toList(),
          pollsVotes: pollVotesFrom(pollsByPost[p.id] ?? const []),
          lottery: p.id == firstId ? lottery : null,
          redEnvelopeClaim: claims[p.id],
        ),
    ];
    final topic = page['topic'] is Map ? page['topic'] as Map : const {};
    return topicDetailFrom(
      {...page, 'next_after': nextAfter},
      nodeId: _nodeIdOfSync(topic['node_slug']?.toString()),
      viewerId: _viewerId(),
      posts: posts,
      redEnvelope: envelope,
      gapAfter: gapAfter,
      gapBefore: gapBefore,
    );
  }

  static final _pollMarkup = RegExp(r'''class="[^"]*\bpoll\b''');

  Future<List> _pollsFor(int postId) async {
    final polls = ((await _get('/api/v1/posts/$postId/polls'))['polls'] as List?) ?? const [];
    for (final p in polls.whereType<Map>()) {
      final name = (p['name']?.toString() ?? '').isEmpty ? 'poll' : p['name'].toString();
      final pid = toInt(p['id']);
      if (pid != null) _pollIds['$postId/$name'] = pid;
    }
    return polls;
  }

  /// 继续加载楼层号大于 [after] 的回复。返回这一页的楼层和下一页游标。
  Future<({List<Post> posts, int? nextAfter})> topicPostsAfter(int topicId, int after) async {
    final page = await _get('/api/v1/topics/$topicId', query: {'limit': _page, 'after': after});
    final moderate = (page['permissions'] is Map) && (page['permissions'] as Map)['moderate'] == true;
    final posts = ((page['posts'] as List?) ?? const [])
        .whereType<Map>()
        .where((p) => p['kind']?.toString() != 'action')
        .map((p) => postFrom(p, topicId: topicId, viewerId: _viewerId(), canModerate: moderate))
        .toList();
    return (posts: posts, nextAfter: toInt(page['next_after']));
  }

  /// 按帖子 id 取楼层（收藏、通知跳转用）。新接口没有按 id 取帖子的路径，取前 100 楼过滤。
  Future<List<Post>> topicPosts(int topicId, List<int> postIds) async {
    if (postIds.isEmpty) return [];
    final page = await _get('/api/v1/topics/$topicId', query: {'limit': 100});
    final wanted = postIds.toSet();
    return ((page['posts'] as List?) ?? const [])
        .whereType<Map>()
        .where((p) => wanted.contains(toInt(p['id'])))
        .map((p) => postFrom(p, topicId: topicId, viewerId: _viewerId()))
        .toList();
  }

  /// 编辑前取原始 Markdown；HTML 会丢失格式。
  Future<String> postRaw(int postId) async {
    final raw = (await _get('/api/v1/posts/$postId/raw'))['raw'];
    if (raw is! String) throw ApiException('无法获取原始正文，请在网页版编辑');
    return raw;
  }

  Future<void> updatePost(int postId, String raw) async {
    await _send('PATCH', '/api/v1/posts/$postId', body: {'raw': raw});
  }

  /// 旧级别：0 静音、1 普通、2 跟踪、3 关注。新接口只有 watching / normal / muted。
  Future<void> setTopicNotificationLevel(int topicId, int level) async {
    if (level < 0 || level > 3) throw ArgumentError.value(level, 'level');
    final value = level >= 2 ? 'watching' : (level == 0 ? 'muted' : 'normal');
    await _send('PUT', '/api/v1/topics/$topicId/follow', body: {'level': value});
  }

  /// 创建新话题。新版站点每个话题必须属于一个节点。
  /// 返回旧格式：`id`（一楼帖子 id）、`topic_id`、`post_number`，以及 `held`（进入审核）。
  /// [mobileSource] 已无对应字段，保留参数只为兼容调用方。
  Future<Map<String, dynamic>> createTopic({
    required String title,
    required String raw,
    int? categoryId,
    List<String> tags = const [],
    Map<String, String>? mobileSource,
  }) async {
    if (categoryId == null) throw ApiException('请选择发帖的节点');
    final slug = await _nodeSlug(categoryId);
    final d = await _send('POST', '/api/v1/topics', body: {
      'node': slug,
      'title': title,
      'raw': raw,
      if (tags.isNotEmpty) 'tags': tags,
    });
    final topic = d['topic'] is Map ? d['topic'] as Map : const {};
    final post = d['post'] is Map ? d['post'] as Map : const {};
    return {
      'id': toInt(post['id']),
      'topic_id': toInt(topic['id']),
      'post_number': 1,
      'held': d['held'] == true,
    };
  }

  Future<Map<String, dynamic>> createReply({
    required int topicId,
    required String raw,
    int? replyToPostNumber,
    Map<String, String>? mobileSource,
  }) async {
    final d = await _send('POST', '/api/v1/topics/$topicId/posts', body: {
      'raw': raw,
      if (replyToPostNumber != null) 'reply_to_post_number': replyToPostNumber,
    });
    final post = d['post'] is Map ? d['post'] as Map : const {};
    return {
      'id': toInt(post['id']),
      'topic_id': topicId,
      'post_number': toInt(post['post_number']),
      'held': d['held'] == true,
    };
  }

  // ---------------------------------------------------------------- 点赞（即赞成票）

  Future<void> likePost(int postId) => castPostVote(postId, 'up').then((_) {});

  Future<void> unlikePost(int postId) => castPostVote(postId, 'none').then((_) {});

  /// 新版站点没有表情反应，入口已隐藏。
  Future<Map<String, dynamic>> toggleReaction(int postId, String reactionId) async =>
      throw UnsupportedFeatureException();

  // ---------------------------------------------------------------- 通知

  Future<List<NotificationItem>> notifications() async {
    final d = await _get('/api/v1/notifications', query: {'limit': 50});
    return ((d['notifications'] as List?) ?? const []).whereType<Map>().map(notificationFrom).toList();
  }

  Future<void> markNotificationRead(int id) =>
      _send('POST', '/api/v1/notifications/read', body: {'id': id}).then((_) {});

  Future<void> markAllNotificationsRead() => _send('POST', '/api/v1/notifications/read').then((_) {});

  // ---------------------------------------------------------------- 用户

  Future<UserProfile> userProfile(String username) async =>
      userProfileFrom(await _get('/api/v1/users/${_enc(username)}'), me: _meName);

  Future<void> followUser(String username) =>
      _send('PUT', '/api/v1/users/${_enc(username)}/follow').then((_) {});

  Future<void> unfollowUser(String username) =>
      _send('DELETE', '/api/v1/users/${_enc(username)}/follow').then((_) {});

  Future<void> setUserIgnored(String username, bool ignored) =>
      _send(ignored ? 'PUT' : 'DELETE', '/api/v1/users/${_enc(username)}/block').then((_) {});

  /// 我屏蔽的用户名。
  Future<List<String>> blockedUsernames() async {
    final d = await _get('/api/v1/me/blocks');
    return blockedUsernamesFrom(d.containsKey('_list') ? d['_list'] : d);
  }

  Future<TopicListResult> userTopics(String username, {int page = 0}) =>
      _topicPage('user:$username', '/api/v1/users/${_enc(username)}/topics', const {}, page);

  // ---------------------------------------------------------------- 搜索

  /// 页码从 1 开始。
  /// [newest] 为真时按发布时间倒序（站点的 `sort=new`），否则按相关程度。
  Future<SearchResult> search(String q, {int page = 1, bool newest = false}) async {
    final d = await _get('/api/v1/search', query: {
      'q': q,
      if (newest) 'sort': 'new',
      'offset': (page - 1).clamp(0, 1 << 20) * _page,
      'limit': _page,
    });
    return searchResultFrom(d);
  }

  Future<int> _pollId(int postId, String pollName) async {
    final cached = _pollIds['$postId/$pollName'];
    if (cached != null) return cached;
    await _pollsFor(postId);
    final id = _pollIds['$postId/$pollName'];
    if (id == null) throw ApiException('投票不存在或已被删除', 404, 'not_found');
    return id;
  }

  Future<PollVoteResult> votePoll(int postId, String pollName, List<String> options) async {
    if (options.isEmpty) throw ApiException('请选择投票选项');
    final id = await _pollId(postId, pollName);
    final d = await _send('PUT', '/api/v1/polls/$id/votes', body: {
      'option_ids': [for (final o in options) int.tryParse(o)].whereType<int>().toList(),
    });
    final poll = d['poll'];
    if (poll is! Map) return PollVoteResult(vote: options);
    final chosen = pollVotesFrom([poll]).values.firstOrNull ?? options;
    return PollVoteResult(poll: pollFrom(poll), vote: chosen);
  }

  Future<PollVoteResult> removePollVote(int postId, String pollName) async {
    final id = await _pollId(postId, pollName);
    final d = await _send('PUT', '/api/v1/polls/$id/votes', body: {'option_ids': <int>[]});
    final poll = d['poll'];
    return PollVoteResult(poll: poll is Map ? pollFrom(poll) : null, vote: const []);
  }

  // ---------------------------------------------------------------- 私信（已并入聊天）

  /// 私信话题已不存在：一对一对话在聊天里。保留方法只为兼容，返回空列表。
  Future<TopicListResult> privateMessages(String username, {int page = 0}) async =>
      TopicListResult(topics: const [], users: const {}, hasMore: false);

  /// 私信即聊天消息。标题没有单独的位置，所以放在正文前面。多个收件人逐个发送。
  Future<Map<String, dynamic>> createPrivateMessage({
    required String title,
    required String raw,
    required List<String> targetUsernames,
  }) async {
    final text = [title.trim(), raw.trim()].where((e) => e.isNotEmpty).join('\n\n');
    int? last;
    for (final user in targetUsernames) {
      final d = await _send('POST', '/api/v1/messages/${_enc(user)}', body: {'raw': text});
      final msg = d['message'];
      if (msg is Map) last = toInt(msg['id']);
    }
    return {'id': last};
  }

  // ---------------------------------------------------------------- 收藏

  /// 收藏按帖子记录；返回的“收藏编号”就是帖子 id。
  Future<int> addBookmark(int postId) async {
    await _send('PUT', '/api/v1/posts/$postId/bookmark');
    return postId;
  }

  Future<void> removeBookmark(int bookmarkId) =>
      _send('DELETE', '/api/v1/posts/$bookmarkId/bookmark').then((_) {});

  /// 只能看自己的收藏。
  Future<List<BookmarkItem>> bookmarks(String username, {int page = 0}) async {
    final d = await _get('/api/v1/saved', query: {'offset': page * _page, 'limit': _page});
    return ((d['bookmarks'] as List?) ?? const []).whereType<Map>().map(bookmarkFrom).toList();
  }

  // ---------------------------------------------------------------- 阅读进度

  /// 上报阅读进度：读到的最远楼层和停留秒数。失败静默忽略。
  Future<void> postTimings(int topicId, int totalMs, Map<int, int> postMs) async {
    if (postMs.isEmpty || token == null) return;
    final furthest = postMs.keys.reduce(max);
    try {
      await _send('PUT', '/api/v1/topics/$topicId/read', body: {
        'post_number': furthest,
        'seconds': (totalMs ~/ 1000).clamp(1, 1 << 20),
      });
    } catch (_) {}
  }

  // ---------------------------------------------------------------- 上传

  /// 上传图片，返回旧格式：`id`、`url`、`short_url`（新版没有短地址，为 null）、`original_filename`。
  Future<Map<String, dynamic>> uploadImage({
    required String filePath,
    required String filename,
    void Function(int sent, int total)? onProgress,
  }) async {
    final lower = filename.toLowerCase();
    final isImage = const ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic', '.avif']
        .any(lower.endsWith);
    final form = FormData.fromMap({
      'kind': isImage ? 'image' : 'attachment',
      'file': await MultipartFile.fromFile(filePath, filename: filename),
    });
    try {
      final resp = await _dio.post('/api/v1/uploads', data: form, onSendProgress: onProgress);
      final d = _check(resp);
      final upload = d['upload'] is Map ? d['upload'] as Map : d;
      final id = toInt(upload['id']) ?? 0;
      final url = upload['url']?.toString();
      if (url != null) _uploadUrls[id] = url;
      return {
        'id': id,
        'url': url,
        'short_url': null,
        'original_filename': upload['filename']?.toString() ?? filename,
        'width': toInt(upload['width']),
        'height': toInt(upload['height']),
      };
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw _dioError(e);
    }
  }

  // ---------------------------------------------------------------- 插件：打赏 / 抽奖 / 签到 / 积分 / 节点

  /// 新版站点已取消打赏，入口已隐藏。
  Future<void> giveReward(int postId, int amount, {String? note}) async => throw UnsupportedFeatureException();

  /// 参与抽奖。[postId] 给出时购票后重新读取抽奖，返回最新状态。
  /// 购票带幂等键：网络重试不会重复扣积分。
  Future<PostLottery?> participateInLottery(int lotteryId, int quantity, {bool random = false, int? postId}) async {
    await _send('POST', '/api/v1/lotteries/$lotteryId/tickets',
        body: {'tickets': random ? 0 : quantity, 'random': random},
        headers: {'Idempotency-Key': randomKey()});
    if (postId == null) return null;
    final l = (await _get('/api/v1/posts/$postId/lottery'))['lottery'];
    return l is Map ? lotteryFrom(l) : null;
  }

  /// 今日签到状态（以服务端日期为准）。
  Future<CheckinStatus> checkinStatus() async => checkinStatusFrom(await _get('/api/v1/checkin'));

  /// 每日签到。已签到时服务端返回 4xx 和说明，按“未成功”展示说明。
  Future<CheckinResult> checkin() async {
    try {
      final d = await _send('POST', '/api/v1/checkin');
      return CheckinResult(success: true, points: toInt(d['points']));
    } on ApiException catch (e) {
      final code = e.statusCode ?? 0;
      if (code >= 400 && code < 500 && code != 401 && code != 429) {
        return CheckinResult(success: false, message: e.message);
      }
      rethrow;
    }
  }

  /// 积分余额。
  Future<int> pointsTotal(String username) async => toInt((await _get('/api/v1/points'))['balance']) ?? 0;

  /// 节点目录（全部节点，含子节点）。
  Future<List<Category>> nodes() async => (await _nodeDirectory()).map(categoryFrom).toList();

  // ---------------------------------------------------------------- 账号：资料 / 成就 / 积分明细 / 应用目录

  /// 编辑个人资料。新版没有头衔字段，[title] 被忽略。
  Future<void> updateProfile(
    String username, {
    required String name,
    required String bioRaw,
    required String website,
    required String location,
    required String title,
  }) async {
    await _send('PUT', '/api/v1/me', body: {
      'name': name,
      'bio': bioRaw,
      'website': website,
      'location': location,
    });
  }

  /// 成就（旧版的徽章）。
  Future<List<UserBadge>> userBadges(String username) async {
    final d = await _get('/api/v1/users/${_enc(username)}/achievements');
    final list = ((d['showcase'] as List?) ?? const []).whereType<Map>().toList();
    return [for (var i = 0; i < list.length; i++) badgeFromAchievement(list[i], i)];
  }

  Future<PointsPage> pointsHistory(String username, {int page = 0}) async {
    final query = <String, dynamic>{'limit': _page};
    if (page > 0) {
      final before = _cursors['points|$page'];
      if (before == null) return const PointsPage(entries: [], hasMore: false);
      query['before'] = before;
    }
    final d = await _get('/api/v1/points/history', query: query);
    final next = d['next_before']?.toString();
    if (next != null) _cursors['points|${page + 1}'] = next;
    return PointsPage(
      entries: ((d['entries'] as List?) ?? const []).whereType<Map>().map(pointsEntryFrom).toList(),
      hasMore: next != null,
    );
  }

  /// 应用目录。新版返回 `{"apps": [...]}`，旧版是裸数组，两种都认。
  Future<List<DirectoryApp>> appsDirectory() async {
    final d = await _get('/apps/directory.json');
    final list = (d['apps'] as List?) ?? (d['_list'] as List?) ?? const [];
    return list.whereType<Map>().map(DirectoryApp.fromJson).toList();
  }

  Future<DirectoryApp> app(String slug) async {
    final d = await _get('/apps/${_enc(slug)}.json');
    final inner = d['directory_app'] ?? d['app'];
    return DirectoryApp.fromJson(inner is Map ? inner : d);
  }

  /// 自己资料的原始字段（编辑用）。
  Future<Map<String, String>> ownProfileFields(String username) async {
    final user = (await _get('/api/v1/me'))['user'];
    final m = user is Map ? user : const {};
    String s(String key) => m[key]?.toString() ?? '';
    return {
      'name': s('name'),
      'bio_raw': s('bio_raw'),
      'website': s('website'),
      'location': s('location'),
      'title': s('title'),
    };
  }

  /// 为刚创建的话题挂上红包。必须在话题存在之后调用。
  Future<void> createRedEnvelope(int topicId, {required int totalPoints, required int totalCount}) async {
    await _send('POST', '/api/v1/topics/$topicId/red-envelope', body: {'total': totalPoints, 'count': totalCount});
  }

  /// 为刚创建的楼层挂上抽奖。[payload] 是旧格式（见 plugin_drafts.dart），这里转换字段名。
  Future<void> createLottery(Map<String, dynamic> payload) async {
    final postId = toInt(payload['post_id']);
    if (postId == null) throw ApiException('抽奖缺少楼层');
    await _send('POST', '/api/v1/posts/$postId/lottery', body: {
      'title': payload['title'] ?? '',
      if (payload['draw_at'] != null) 'draw_at': payload['draw_at'],
      if (payload['min_tickets_per_user'] != null) 'min_tickets': payload['min_tickets_per_user'],
      if (payload['max_tickets_per_user'] != null) 'max_tickets': payload['max_tickets_per_user'],
      if (payload['min_participants'] != null) 'min_participants': payload['min_participants'],
      if (payload['max_participants'] != null) 'max_participants': payload['max_participants'],
      if (payload['min_trust_level'] != null) 'min_trust_level': payload['min_trust_level'],
      'prizes': payload['levels'] ?? const [],
    });
  }

  Future<({bool available, String? message})> checkNodeSlug(String slug) async {
    final d = await _get('/api/v1/nodes/slug-available', query: {'slug': slug});
    return (
      available: d['available'] == true || d['available']?.toString() == 'true',
      message: (d['message'] ?? d['slug_message'])?.toString(),
    );
  }

  Future<void> createNode({
    required String name,
    required String slug,
    required String description,
    required int parentCategoryId,
    String? colorHex,
  }) async {
    await _send('POST', '/api/v1/nodes', body: {
      'parent': await _nodeSlug(parentCategoryId),
      'slug': slug,
      'name': name,
      'description': description,
      if (colorHex != null && colorHex.isNotEmpty) 'color': colorHex.replaceAll('#', '').toLowerCase(),
    });
    _nodesAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ---------------------------------------------------------------- 聊天

  /// 公开频道、群聊、私聊。私聊按用户名寻址，这里记下会话 id 对应的用户名。
  Future<List<ChatChannel>> chatChannels() async {
    final d = await _get('/api/v1/chat');
    final list = chatChannelsFrom(d, me: _meName);
    for (final c in list) {
      if (c.directUsername != null) _directUsers[c.id] = c.directUsername!;
    }
    return list;
  }

  /// 打开与某人的私聊（还没聊过也可以：发第一条消息时才建立会话）。
  Future<ChatChannel> openDirectChat(String username) async {
    final d = await _get('/api/v1/messages/${_enc(username)}', query: {'limit': 1, 'read': 0});
    final id = toInt(d['conversation_id']) ?? -syntheticUserId(username);
    _directUsers[id] = username;
    return ChatChannel(id: id, title: username, isDirect: true, directUsername: username);
  }

  String _chatPath(int channelId) {
    final user = _directUsers[channelId];
    return user != null ? '/api/v1/messages/${_enc(user)}' : '/api/v1/chat/channels/$channelId/messages';
  }

  /// 新接口按时间倒序返回；会话页自己按 id 排序。
  Future<List<ChatMessage>> chatMessages(int channelId, {int pageSize = 50}) async {
    final d = await _get(_chatPath(channelId), query: {'limit': pageSize.clamp(1, 100), 'read': 0});
    final conversation = toInt(d['conversation_id']);
    final user = _directUsers[channelId];
    if (conversation != null && user != null) _directUsers[conversation] = user;
    return ((d['messages'] as List?) ?? const []).whereType<Map>().map(chatMessageFrom).toList();
  }

  /// 发送聊天消息。图片附件以 Markdown 写进正文（上传时记下了地址）。
  Future<int?> sendChatMessage(int channelId, String message,
      {List<int> uploadIds = const [], int? threadId}) async {
    final images = [for (final id in uploadIds) if (_uploadUrls[id] != null) '![](${_uploadUrls[id]})'];
    final raw = [if (message.trim().isNotEmpty) message.trim(), ...images].join('\n');
    final d = await _send('POST', _chatPath(channelId), body: {'raw': raw});
    final msg = d['message'];
    return msg is Map ? toInt(msg['id']) : null;
  }

  /// 新版站点不能编辑已发送的聊天消息，入口已隐藏。
  Future<void> editChatMessage(int channelId, int messageId, String text) async =>
      throw UnsupportedFeatureException();

  Future<void> deleteChatMessage(int channelId, int messageId) async {
    await _send('DELETE', '/api/v1/chat/messages/$messageId');
  }

  /// 只有群聊有成员列表；公开频道和私聊返回空。
  Future<List<ChatUser>> chatMembers(int channelId) async {
    if (_directUsers.containsKey(channelId)) return const [];
    try {
      final d = await _get('/api/v1/chat/groups/$channelId/members');
      return ((d['members'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => ChatUser(
                id: syntheticUserId(m['username']?.toString()),
                username: m['username']?.toString() ?? '',
              ))
          .toList();
    } on ApiException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }

  Future<void> leaveChatChannel(int channelId) async {
    if (_directUsers.containsKey(channelId)) throw UnsupportedFeatureException('私聊不能离开');
    await _send('DELETE', '/api/v1/chat/channels/$channelId/membership');
  }

  /// 标记会话已读到某条消息。
  Future<void> markChatRead(int channelId, int messageId) async {
    if (channelId < 0) return;
    try {
      await _send('PUT', '/api/v1/chat/conversations/$channelId/read', body: {'message_id': messageId});
    } catch (_) {}
  }

  /// 新版只有静音与否：never 即静音，其余取消静音。
  Future<void> setChatNotificationLevel(int channelId, String level) async {
    if (channelId < 0) return;
    await _send(level == 'never' ? 'PUT' : 'DELETE', '/api/v1/chat/conversations/$channelId/mute');
  }

  /// 新版站点没有聊天线程，入口已隐藏。
  Future<List<ChatThread>> chatThreads(int channelId) async => const [];

  Future<List<ChatMessage>> chatThreadMessages(int channelId, int threadId) async => const [];

  // ---------------------------------------------------------------- 账号设置

  /// `GET /me/settings`：通知、隐私、邮件等设置的完整集合。
  Future<Map<String, dynamic>> accountSettings() => _get('/api/v1/me/settings');

  /// 部分写入：没有给出的键保持不变。返回写入后的完整集合。
  Future<Map<String, dynamic>> updateAccountSettings(Map<String, dynamic> patch) =>
      _send('PUT', '/api/v1/me/settings', body: patch);

  /// 关联账号与登录设备（仅本人可见）。
  Future<({List<AssociatedAccount> accounts, List<AuthSession> sessions})> ownAccountDetail(
      String username) async {
    final results = await Future.wait([
      _get('/api/v1/me/identities').catchError((_) => <String, dynamic>{}),
      _get('/api/v1/me/sessions').catchError((_) => <String, dynamic>{}),
    ]);
    return (accounts: associatedAccountsFrom(results[0]), sessions: sessionsFrom(results[1]));
  }

  Future<void> revokeAssociatedAccount(String username, String provider) =>
      _send('DELETE', '/api/v1/me/identities/${_enc(provider)}').then((_) {});

  /// 撤销一个登录设备；[tokenId] 为 null 时撤销除当前设备外的所有设备。
  Future<void> revokeAuthToken(String username, {int? tokenId}) =>
      _send('DELETE', tokenId == null ? '/api/v1/me/sessions' : '/api/v1/me/sessions/$tokenId').then((_) {});

  /// 子节点列表（来自节点目录，按成员数排序后分页）。
  Future<({List<Category> nodes, bool hasMore})> nodeBrowse(int parentId, {int page = 0, int perPage = 30}) async {
    final children = (await _nodeDirectory()).where((n) => toInt(n['parent_id']) == parentId).toList()
      ..sort((a, b) => (toInt(b['member_count']) ?? 0).compareTo(toInt(a['member_count']) ?? 0));
    final slice = children.skip(page * perPage).take(perPage).map(categoryFrom).toList();
    return (nodes: slice, hasMore: (page + 1) * perPage < children.length);
  }

  /// 加入或退出节点。
  Future<bool> setNodeJoined(int categoryId, bool joined) async {
    final slug = await _nodeSlug(categoryId);
    await _send(joined ? 'PUT' : 'DELETE', '/api/v1/nodes/${_enc(slug)}/membership');
    _nodesAt = DateTime.fromMillisecondsSinceEpoch(0);
    return joined;
  }

  /// 在节点目录里按名称或别名搜索子节点。
  Future<List<Category>> searchNodes(String term) async {
    final needle = term.trim().toLowerCase();
    final found = (await _nodeDirectory()).where((n) {
      if (needle.isEmpty) return true;
      return (n['name']?.toString().toLowerCase().contains(needle) ?? false) ||
          (n['slug']?.toString().toLowerCase().contains(needle) ?? false);
    }).toList()
      ..sort((a, b) => (toInt(b['member_count']) ?? 0).compareTo(toInt(a['member_count']) ?? 0));
    return found.take(25).map(categoryFrom).toList();
  }

  // ---------------------------------------------------------------- 注册 / 找回密码

  /// 注册。返回（是否已直接登录，站点说明）。直接登录时 [token] 已设置。
  /// 新版没有自定义注册字段，[userFields] 被忽略。
  Future<({bool active, String? message})> signup({
    required String username,
    required String name,
    required String email,
    required String password,
    Map<int, String> userFields = const {},
    String? inviteCode,
  }) async {
    final d = await _guarded(CaptchaAction.register, true, (captcha) {
      return _send('POST', '/api/v1/auth/register', body: {
        'username': username.trim(),
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        if (inviteCode != null && inviteCode.trim().isNotEmpty) 'invite_code': inviteCode.trim(),
        if (captcha != null) 'captcha': captcha,
        'device': _device(),
      });
    });
    final loggedIn = d['logged_in'] == true || d['logged_in']?.toString() == 'true';
    if (loggedIn && d['token'] != null) {
      _adopt(d);
      return (active: true, message: d['message']?.toString());
    }
    return (active: false, message: d['message']?.toString());
  }

  /// 发送找回密码邮件。站点无论账号是否存在都给出相同说明，以免泄露账号信息。
  Future<String?> requestPasswordReset(String login) async {
    final d = await _guarded(CaptchaAction.passwordReset, true, (captcha) {
      return _send('POST', '/api/v1/auth/password-reset', body: {
        'email': login.trim(),
        if (captcha != null) 'captcha': captcha,
      });
    });
    return d['message']?.toString();
  }

  /// 新版没有自定义注册字段。
  Future<List<SignupField>> signupUserFields() async => const [];

  // ---------------------------------------------------------------- 嵌套视图

  static String _replySort(String sort) => switch (sort) {
        'top' => 'best',
        'new' => 'new',
        _ => 'old',
      };

  /// 嵌套视图的根回复（`/topics/{id}/thread`，按偏移分页）。
  /// 返回旧的嵌套 JSON 形状，嵌套页面的解析不用改。
  Future<({Map<String, dynamic> raw, List<Map> roots, bool hasMore})> nestedTopic(
      int topicId, {String slug = 'topic', String sort = 'top', int page = 0}) async {
    final d = await _get('/api/v1/topics/$topicId/thread', query: {
      'sort': _replySort(sort),
      'offset': page * _threadPage,
      'limit': _threadPage,
    });
    final roots = threadTree((d['posts'] as List?) ?? const []);
    return (raw: d, roots: roots.cast<Map>(), hasMore: d['next_offset'] != null || d['has_more'] == true);
  }

  /// 某楼层的直接回复（`/topics/{id}/thread?parent=`，按 after 游标分页）。
  Future<({List<Map> children, bool hasMore})> nestedChildren(
      int topicId, int postNumber, {String slug = 'topic', String sort = 'top', int page = 0}) async {
    final key = 'thread:$topicId:$postNumber:$sort';
    final after = page == 0 ? '0' : _cursors['$key|$page'];
    if (after == null) return (children: <Map>[], hasMore: false);
    final d = await _get('/api/v1/topics/$topicId/thread', query: {
      'parent': postNumber,
      'after': after,
      'limit': _threadPage,
    });
    final next = d['next_after']?.toString();
    if (next != null) _cursors['$key|${page + 1}'] = next;
    final posts = ((d['posts'] as List?) ?? const []).whereType<Map>().toList();
    // 只取直接回复：深度最浅的那一层。
    final depths = posts.map((p) => toInt(p['depth']) ?? 1);
    final shallowest = depths.isEmpty ? 1 : depths.reduce(min);
    final direct = threadTree(posts.where((p) => (toInt(p['depth']) ?? shallowest) >= shallowest).toList());
    return (children: direct.cast<Map>(), hasMore: next != null);
  }

  // ---------------------------------------------------------------- 账号：等级 / 两步验证

  Future<UpgradeProgress> upgradeProgress(String username) async =>
      upgradeProgressFrom(await _get('/api/v1/me/reputation'));

  /// 新版只有一个验证器：开启时返回一项。
  Future<List<TotpDevice>> totpDevices() async {
    final d = await _get('/api/v1/me/two-factor');
    return d['enabled'] == true ? const [TotpDevice(id: 1, name: '验证器')] : const [];
  }

  /// 生成 TOTP 密钥。返回（密钥，otpauth 地址）。
  Future<({String key, String? qr})> createTotp() async {
    final d = await _send('POST', '/api/v1/me/two-factor');
    final key = d['secret']?.toString();
    if (key == null || key.isEmpty) throw ApiException('无法生成验证密钥，请稍后重试');
    return (key: key, qr: d['uri']?.toString());
  }

  Future<void> enableTotp(String token, String name) =>
      _send('PUT', '/api/v1/me/two-factor', body: {'code': token}).then((_) {});

  Future<void> disableSecondFactor() => _send('DELETE', '/api/v1/me/two-factor').then((_) {});

  Future<List<String>> generateBackupCodes() async {
    final d = await _send('POST', '/api/v1/me/two-factor/backup-codes');
    final codes = d['backup_codes'];
    if (codes is! List || codes.isEmpty) throw ApiException('备用码生成失败，请稍后重试');
    return codes.map((c) => c.toString()).toList();
  }

  // ---------------------------------------------------------------- 实时推送

  /// 服务端事件流（SSE）。调用方逐行读取，见 lib/message_bus.dart。
  Future<Stream<List<int>>> openEventStream({CancelToken? cancelToken}) async {
    final resp = await _dio.get<ResponseBody>(
      '/api/v1/notifications/stream',
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
        // 服务端约 25 秒发一次心跳；读超时必须比它长。
        receiveTimeout: const Duration(seconds: 70),
      ),
    );
    final code = resp.statusCode ?? 500;
    if (code == 401) {
      if (token != null) onSessionRejected?.call();
      throw UnauthorizedException();
    }
    if (code < 200 || code >= 300 || resp.data == null) throw ApiException(_fallbackMessage(code), code);
    return resp.data!.stream.cast<List<int>>();
  }

  // ---------------------------------------------------------------- 工具

  /// 头像地址：新版直接给完整地址或站内路径；旧模板里的 {size} 一并处理。
  String? resolveAvatarUrl(String? template, {int size = 96}) {
    if (template == null || template.isEmpty) return null;
    final url = template.replaceAll('{size}', size.toString());
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    return '$base${url.startsWith('/') ? '' : '/'}$url';
  }
}
