import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/friendly_error.dart';
import '../gif_search.dart';

/// 选择一张 GIF，返回它的完整地址；取消返回 null。
Future<String?> showGifPicker(BuildContext context, String apiKey) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _GifPickerSheet(apiKey: apiKey),
  );
}

class _GifPickerSheet extends StatefulWidget {
  final String apiKey;

  const _GifPickerSheet({required this.apiKey});

  @override
  State<_GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<_GifPickerSheet> {
  final _query = TextEditingController();
  final _client = GifSearchClient();
  List<GifItem> _items = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = await _client.search(widget.apiKey, q);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: '搜索 GIF',
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _busy ? null : _search,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              Expanded(
                child: _busy
                    ? const Center(child: CircularProgressIndicator())
                    : _items.isEmpty
                        ? const Center(child: Text('输入关键词开始搜索'))
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                            ),
                            itemCount: _items.length,
                            itemBuilder: (context, i) {
                              final g = _items[i];
                              return InkWell(
                                onTap: () => Navigator.pop(context, g.url),
                                child: CachedNetworkImage(
                                  imageUrl: g.previewUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) =>
                                      const ColoredBox(color: Color(0x11000000)),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
