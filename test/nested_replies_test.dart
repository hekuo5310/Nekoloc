import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/nested_replies.dart';

void main() {
  test('子树展开顺序为先父后子，深度正确', () {
    final root = NestedNode.fromJson({
      'id': 1, 'post_number': 1, 'username': 'a', 'cooked': '', 'like_count': 0,
      'direct_reply_count': 2,
      'children': [
        {
          'id': 2, 'post_number': 2, 'username': 'b', 'cooked': '', 'like_count': 0,
          'direct_reply_count': 1,
          'children': [
            {'id': 3, 'post_number': 3, 'username': 'c', 'cooked': '', 'like_count': 0},
          ],
        },
        {'id': 4, 'post_number': 4, 'username': 'd', 'cooked': '', 'like_count': 0},
      ],
    });
    final flat = flattenNested([root]);
    expect(flat.map((n) => n.post.id), [1, 2, 3, 4]);
    expect(flat.map((n) => n.depth), [0, 1, 2, 1]);
  });

  test('未加载的直接回复数记入 moreCount', () {
    final n = NestedNode.fromJson({
      'id': 1, 'username': 'a', 'cooked': '', 'like_count': 0,
      'direct_reply_count': 5,
      'children': [
        {'id': 2, 'username': 'b', 'cooked': '', 'like_count': 0},
      ],
    });
    expect(n.moreCount, 4);
    expect(n.children.length, 1);
  });

  test('缩进在超过最大深度后停止增长', () {
    expect(indentFor(0), 0);
    expect(indentFor(2), 24);
    expect(indentFor(9), indentFor(5));
  });
}
