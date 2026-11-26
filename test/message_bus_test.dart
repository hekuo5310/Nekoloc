import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/message_bus.dart';

List<SseEvent> parse(List<String> lines) {
  final parser = SseParser();
  return [for (final l in lines) parser.addLine(l)].whereType<SseEvent>().toList();
}

void main() {
  test('按空行切分事件，心跳注释忽略', () {
    final events = parse([
      ': heartbeat',
      'event: unread',
      'data: {"unread":3}',
      '',
      'event: chat',
      'data: {"type":"new",',
      'data: "conversation":4}',
      '',
    ]);
    expect(events.map((e) => e.event), ['unread', 'chat']);
    expect(events.last.data, '{"type":"new",\n"conversation":4}');
  });

  test('unread 触发所有通知频道', () {
    final fired = channelsFor('unread', '{"unread":1}', {'/notification/3', '/chat/4'});
    expect(fired, {'/notification/3'});
  });

  test('chat 触发对应会话和会话列表，未订阅的不触发', () {
    final fired = channelsFor('chat', '{"type":"new","conversation":4}', {'/chat/4', '/chat/5', '/chat/list'});
    expect(fired, {'/chat/4', '/chat/list'});
  });

  test('resync 让所有订阅者刷新', () {
    final subscribed = {'/chat/4', '/notification/3'};
    expect(channelsFor('chat', '{"type":"resync"}', subscribed), subscribed);
  });

  test('无法解析的数据不触发任何频道', () {
    expect(channelsFor('chat', 'not json', {'/chat/4'}), isEmpty);
    expect(channelsFor('review', '{"pending":2}', {'/chat/4'}), isEmpty);
  });

  test('取消订阅后不再保留监听器', () {
    final client = MessageBusClient();
    final cancel = client.subscribe('/notification/3', () {});
    cancel();
    var calls = 0;
    client.subscribe('/notification/3', () => calls++);
    expect(calls, 0);
  });
}
