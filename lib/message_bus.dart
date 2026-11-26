import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import 'api/discourse_api.dart';

/// 实时推送：读取站点的事件流（SSE，`/api/v1/notifications/stream`），
/// 翻译成界面一直使用的频道名再通知订阅者。
///
/// 只传信号：事件表示“这里有变化”，订阅者自己重新拉取。事件流里与界面有关的两类：
/// - `unread`：通知数变化 → 触发所有 `/notification/…` 频道；
/// - `chat`：`{type, conversation, …}` → 触发 `/chat/{conversation}`；`resync` 触发全部。
/// 对齐参考客户端 NodeLoc Android 的 MessageBusClient。

/// 一个 SSE 事件。
class SseEvent {
  final String event;
  final String data;
  const SseEvent(this.event, this.data);
}

/// 逐行解析 SSE。按行喂入，遇到空行时产出一个事件；注释行（以冒号开头，即心跳）忽略。
class SseParser {
  String _event = 'message';
  final StringBuffer _data = StringBuffer();

  SseEvent? addLine(String line) {
    if (line.isEmpty) {
      if (_data.isEmpty && _event == 'message') return null;
      final out = SseEvent(_event, _data.toString());
      _event = 'message';
      _data.clear();
      return out;
    }
    if (line.startsWith(':')) return null;
    if (line.startsWith('event:')) {
      _event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      if (_data.isNotEmpty) _data.write('\n');
      _data.write(line.substring(5).trim());
    }
    return null;
  }
}

/// 一个事件会触发哪些已订阅的频道。纯函数，便于测试。
Set<String> channelsFor(String event, String data, Set<String> subscribed) {
  final out = <String>{};
  switch (event) {
    case 'unread':
      out.addAll(subscribed.where((c) => c.startsWith('/notification/')));
    case 'chat':
      Map? payload;
      try {
        final parsed = jsonDecode(data);
        if (parsed is Map) payload = parsed;
      } catch (_) {}
      if (payload == null) return out;
      if (payload['type']?.toString() == 'resync') return {...subscribed};
      final conversation = payload['conversation'];
      final id = conversation is num ? conversation.toInt() : int.tryParse('$conversation') ?? 0;
      if (id != 0) out.add('/chat/$id');
      // 任何聊天变化都会改变会话列表的未读数。
      out.addAll(subscribed.where((c) => c.startsWith('/chat/list')));
  }
  return out.where(subscribed.contains).toSet();
}

class MessageBusClient {
  final Map<String, List<void Function()>> _listeners = {};
  bool _running = false;
  int _failures = 0;
  CancelToken? _cancel;

  /// 订阅一个频道，返回取消订阅的函数。
  void Function() subscribe(String channel, void Function() onEvent) {
    _listeners.putIfAbsent(channel, () => []).add(onEvent);
    return () {
      final list = _listeners[channel];
      list?.remove(onEvent);
      if (list != null && list.isEmpty) _listeners.remove(channel);
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
    _cancel?.cancel();
    _cancel = null;
  }

  void _dispatch(Set<String> channels) {
    for (final channel in channels) {
      for (final listener in List<void Function()>.of(_listeners[channel] ?? const [])) {
        listener();
      }
    }
  }

  /// 断线期间可能错过变化，所以每次连上都让所有订阅者刷新一次。
  void _fireAll() => _dispatch(_listeners.keys.toSet());

  Future<void> _loop(DiscourseApi api) async {
    while (_running) {
      if (_listeners.isEmpty || !api.isLoggedIn) {
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }
      final started = DateTime.now();
      var healthy = false;
      try {
        _cancel = CancelToken();
        final stream = await api.openEventStream(cancelToken: _cancel);
        _fireAll();
        final parser = SseParser();
        await for (final line in stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (!_running) break;
          final event = parser.addLine(line);
          if (event != null) _dispatch(channelsFor(event.event, event.data, _listeners.keys.toSet()));
        }
        // 服务端每半小时主动断开一次，属于正常结束。
        healthy = DateTime.now().difference(started) > const Duration(seconds: 30);
      } catch (_) {
        healthy = false;
      }
      if (!_running) break;
      if (healthy) {
        _failures = 0;
        await Future<void>.delayed(const Duration(seconds: 1));
      } else {
        // 指数退避：会话失效或服务端故障时不要变成重连风暴（4、8、16、32 秒）。
        _failures = min(_failures + 1, 4);
        await Future<void>.delayed(Duration(seconds: 2 << _failures));
      }
    }
  }
}
