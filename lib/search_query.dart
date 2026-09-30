String buildSearchQuery(String text, {bool titleOnly = false,
    String? username, String? tag, String? order}) {
  final terms = [text.trim()];
  if (titleOnly) terms.add('in:title');
  // A filter value is one token; whitespace must not inject more operators.
  if (username != null && username.trim().isNotEmpty) {
    terms.add('@${username.trim().replaceAll(RegExp(r"\s+"), "")}');
  }
  if (tag != null && tag.trim().isNotEmpty) {
    terms.add('tags:${tag.trim().replaceAll(RegExp(r"\s+"), "")}');
  }
  if (order == 'latest' || order == 'likes') terms.add('order:$order');
  return terms.where((term) => term.isNotEmpty).join(' ');
}
