import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/message_bus.dart';

void main() {
  test('拆分多段响应体', () {
    final events = parseBusBody(
      '[{"channel":"/chat/1","message_id":5,"data":{}}]|[{"channel":"/__status","data":{"/chat/1":7}}]',
    );
    expect(events.length, 2);
    expect(events.first.channel, '/chat/1');
    expect(events.first.messageId, 5);
    expect(events[1].channel, '/__status');
  });

  test('无法解析的段落被忽略', () {
    final events = parseBusBody('not json|[{"channel":"/a","message_id":1}]');
    expect(events.map((e) => e.channel), ['/a']);
  });

  test('状态事件设置起始位置，不回放历史', () {
    final positions = {'/chat/1': -1};
    final fired = applyBusEvents(positions, parseBusBody(
      '[{"channel":"/__status","data":{"/chat/1":42}}]',
    ));
    expect(positions['/chat/1'], 42);
    expect(fired, isEmpty);
  });

  test('已订阅频道有新事件时记录位置并标记触发，未订阅的忽略', () {
    final positions = {'/chat/1': 10};
    final fired = applyBusEvents(positions, parseBusBody(
      '[{"channel":"/chat/1","message_id":11},{"channel":"/chat/2","message_id":3},{"channel":"/chat/1","message_id":12}]',
    ));
    expect(positions.containsKey('/chat/2'), isFalse);
    expect(positions['/chat/1'], 12);
    expect(fired, {'/chat/1'});
  });

  test('取消最后一个订阅会释放频道', () {
    final client = MessageBusClient();
    final cancel = client.subscribe('/notification/3', () {});
    cancel();
    // 再次订阅同一频道不应残留旧的监听器。
    var calls = 0;
    client.subscribe('/notification/3', () => calls++);
    expect(calls, 0);
  });
}
