import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'category_topics_screen.dart';
import '../api/friendly_error.dart';

/// 分类浏览
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => CategoriesScreenState();
}

class CategoriesScreenState extends State<CategoriesScreen>
    with AutomaticKeepAliveClientMixin {
  List<Category>? _categories;
  String? _error;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cats = await context.read<AppState>().api.categories();
      cats.sort((a, b) => (a.position ?? 99).compareTo(b.position ?? 99));
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('分类')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _categories == null || _categories!.isEmpty
                  ? const EmptyView(text: '暂无分类')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        children: [
                          for (final cat in _categories!
                              .where((c) => c.parentId == null))
                            _buildCard(context, cat, scheme),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildCard(BuildContext context, Category cat, ColorScheme scheme) {
    final children =
        _categories!.where((c) => c.parentId == cat.id).toList();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(cat),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: cat.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      cat.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (cat.readRestricted)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.shield_outlined,
                          size: 15, color: scheme.onSurfaceVariant),
                    ),
                  Text(
                    '${cat.topicCount} 话题',
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (cat.descriptionExcerpt.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  cat.descriptionExcerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, height: 1.45, color: scheme.onSurfaceVariant),
                ),
              ],
              if (children.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final sub in children)
                      ActionChip(
                        backgroundColor:
                            scheme.surfaceContainerHighest.withOpacity(0.6),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: sub.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(sub.name,
                                style: const TextStyle(fontSize: 12.5)),
                          ],
                        ),
                        onPressed: () => _open(sub),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _open(Category cat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryTopicsScreen(
          categoryId: cat.id,
          categoryName: cat.name,
        ),
      ),
    );
  }
}
