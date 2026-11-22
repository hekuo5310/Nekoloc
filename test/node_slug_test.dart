import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/node_slug.dart';

void main() {
  test('名称生成别名', () {
    expect(slugifyNodeName('  AI  Tools '), 'ai-tools');
    expect(slugifyNodeName('hello_world'), 'hello-world');
    expect(slugifyNodeName('--a!!b--'), 'a-b');
    expect(slugifyNodeName('中文 节点'), '中文-节点');
    expect(slugifyNodeName('!!!'), '');
  });
}
