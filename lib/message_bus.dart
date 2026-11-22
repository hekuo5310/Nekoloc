import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'api/discourse_api.dart';

/// Discourse MessageBus 的长轮询客户端：聊天消息与新通知的实时推送。
///
/// 协议要点（与参考客户端 MessageBus.kt 一致）：
/// - 请求带上每个频道的最新位置（position），服务端在有新事件时立即返回；
/// - 响应是 JSON 数组，多段时以 `|` 分隔；`/__status` 事件给出各频道当前位置，
///   新订阅的频道从“现在”开始，而不是回放历史；
/// - 请求头 `Dont-Chunk: true` 让响应一次性返回，而不是流式分块。

class BusEvent {
  final String channel;
  final int messageId;
  final dynamic data;

  const BusEvent({required this.channel, required this.messageId, this.data});
}

/// 把响应体拆成事件列表。无法解析的段落会被忽略，不影响其他段落。
List<BusEvent> parseBusBody(String body) {
  final events = <BusEvent>[];
  for (final part in body.split('|')) {
    final text = part.trim();
    if (!text.startsWith('[')) continue;
    final decoded = jsonDecode(text);
    if (decoded is! List) continue;
    for (final e in decoded) {
      if (e is! Map) continue;
      final channel = e['channel']?.toString() ?? '';
      if (channel.isEmpty) continue;
      events.add(BusEvent(
        channel: channel,
        messageId: e['message_id'] is num ? (e['message_id'] as num).toInt() : -1,
        data: e['data'],
      ));
    }
  }
  return events;
}

/// 应用一批事件到位置表，返回本批中有新消息的频道（去重）。
/// 只更新已订阅的频道（positions 中存在的键）。
Set<String> applyBusEvents(Map<String, int> positions, List<BusEvent> events) {
  final fired = <String>{};
  for (final e in events) {
    if (e.channel == '/__status') {
      final statuses = e.data;
      if (statuses is Map) {
        for (final entry in statuses.entries) {
          final name = entry.key.toString();
          if (positions.containsKey(name) && entry.value is num) {
            positions[name] = (entry.value as num).toInt();
          }
        }
      }
      continue;
    }
    if (!positions.containsKey(e.channel)) continue;
    positions[e.channel] = e.messageId;
    fired.add(e.channel);
  }
  return fired;
}

class MessageBusClient {
  final Map<String, int> _positions = {};
  final Map<String, List<void Function()>> _listeners = {};
  final String _clientId = _randomId();
  int _seq = 0;
  int _failures = 0;
  bool _running = false;

  static String _randomId() {
    final rng = Random.secure();
    return List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// 订阅一个频道，返回取消订阅的函数。
  void Function() subscribe(String channel, void Function() onEvent) {
    _positions.putIfAbsent(channel, () => -1);
    _listeners.putIfAbsent(channel, () => []).add(onEvent);
    return () {
      final list = _listeners[channel];
      list?.remove(onEvent);
      if (list != null && list.isEmpty) {
        _listeners.remove(channel);
        _positions.remove(channel);
      }
    };
  }

  bool get running => _running;

  void start(DiscourseApi api) {
    if (_running) return;
    _running = true;
    unawaited(_loop(api));
  }

  void stop() {
    _running = false;
  }

  Future<void> _loop(DiscourseApi api) async {
    while (_running) {
      if (_positions.isEmpty) {
        // 还没有订阅：等待，不发请求。
        await Future<void>.delayed(const Duration(seconds: 1));
        continue;
      }
      try {
        final body = await api.messageBusPoll(
          _clientId,
          Map<String, int>.of(_positions),
          _seq++,
        );
        _failures = 0;
        final fired = applyBusEvents(_positions, parseBusBody(body));
        for (final channel in fired) {
          for (final listener in List<void Function()>.of(_listeners[channel] ?? const [])) {
            listener();
          }
        }
      } catch (_) {
        // 失败时指数退避，避免会话过期后不停地请求站点。
        _failures = min(_failures + 1, 6);
        await Future<void>.delayed(Duration(seconds: 2 << (_failures - 1)));
      }
    }
  }
}
