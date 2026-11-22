import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../image_edit.dart';

/// 上传前的图片编辑：旋转、翻转、按比例裁剪。
/// 完成时把结果写入临时 JPEG 并返回路径；选择“使用原图”返回原路径；返回键取消为 null。
class ImageEditorScreen extends StatefulWidget {
  final String path;

  const ImageEditorScreen({super.key, required this.path});

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  static const _maxSide = 2048;

  img.Image? _original;
  img.Image? _current;
  double? _ratio;
  bool _busy = false;
  String? _error;

  static const _ratios = <String, double?>{
    '原比例': null,
    '1:1': 1,
    '4:3': 4 / 3,
    '16:9': 16 / 9,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw const FormatException('unsupported');
      final limited = limitLongSide(decoded, _maxSide);
      if (!mounted) return;
      setState(() {
        _original = limited;
        _current = limited;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取这张图片，请换一张试试');
    }
  }

  void _apply(img.Image Function(img.Image) edit) {
    final current = _current;
    if (current == null) return;
    setState(() => _current = edit(current));
  }

  void _setRatio(double? ratio) {
    setState(() => _ratio = ratio);
    _apply((src) => cropToRatio(src, ratio));
  }

  Future<void> _done({required bool original}) async {
    if (original) {
      Navigator.pop(context, widget.path);
      return;
    }
    final current = _current;
    if (current == null || _busy) return;
    setState(() => _busy = true);
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/edit_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(encodeForUpload(current));
      if (mounted) Navigator.pop(context, file.path);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑图片'),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => _done(original: true),
            child: const Text('原图'),
          ),
          TextButton(
            onPressed: (_busy || current == null) ? null : () => _done(original: false),
            child: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('完成'),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : current == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Image.memory(encodeForUpload(current), fit: BoxFit.contain),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(8),
                      child: Row(children: [
                        IconButton(
                          tooltip: '逆时针旋转',
                          onPressed: () => _apply(rotateCounterClockwise),
                          icon: const Icon(Icons.rotate_left),
                        ),
                        IconButton(
                          tooltip: '顺时针旋转',
                          onPressed: () => _apply(rotateClockwise),
                          icon: const Icon(Icons.rotate_right),
                        ),
                        IconButton(
                          tooltip: '水平翻转',
                          onPressed: () => _apply(flipHorizontal),
                          icon: const Icon(Icons.flip),
                        ),
                        const SizedBox(width: 8),
                        for (final entry in _ratios.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(entry.key),
                              selected: _ratio == entry.value,
                              onSelected: (_) => _setRatio(entry.value),
                            ),
                          ),
                      ]),
                    ),
                  ],
                ),
    );
  }
}
