/// 节点别名（slug）由名称生成，口径与参考客户端 slugifyNodeName 一致：
/// 小写、空白和下划线变为连字符、去掉非字母数字字符、合并连续连字符、去掉首尾连字符。
String slugifyNodeName(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s_]+'), '-')
    .replaceAll(RegExp(r'[^\p{L}\p{N}-]', unicode: true), '')
    .replaceAll(RegExp(r'-+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');
