import 'models.dart';

/// 嵌套回复树的节点。站点在嵌套视图中把直接回复内联在 children 中，
/// 更深的回复通过 children 接口按需展开，[moreCount] 表示尚未加载的直接回复数。
class NestedNode {
  final Post post;
  final int depth;
  final List<NestedNode> children;
  int moreCount;

  NestedNode({
    required this.post,
    required this.depth,
    List<NestedNode>? children,
    this.moreCount = 0,
  }) : children = children ?? <NestedNode>[];

  /// 从接口 JSON 构建整棵子树。
  factory NestedNode.fromJson(Map json, {int depth = 0}) {
    final post = Post.fromJson(json);
    final kids = ((json['children'] as List?) ?? const [])
        .whereType<Map>()
        .map((c) => NestedNode.fromJson(c, depth: depth + 1))
        .toList();
    final direct = json['direct_reply_count'] is num ? (json['direct_reply_count'] as num).toInt() : 0;
    final more = direct - kids.length;
    return NestedNode(
      post: post,
      depth: depth,
      children: kids,
      moreCount: more < 0 ? 0 : more,
    );
  }
}

/// 按阅读顺序展开为一维列表（先父后子），用于 ListView 渲染。
List<NestedNode> flattenNested(List<NestedNode> roots) {
  final out = <NestedNode>[];
  void walk(NestedNode n) {
    out.add(n);
    for (final c in n.children) {
      walk(c);
    }
  }

  for (final r in roots) {
    walk(r);
  }
  return out;
}

/// 缩进宽度：超过一定深度后不再继续右移，避免窄屏上内容被挤没。
double indentFor(int depth, {double step = 12, int maxDepth = 5}) =>
    (depth > maxDepth ? maxDepth : depth) * step;
