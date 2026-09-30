import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:markdown/markdown.dart' as md;

import '../app_state.dart';
import '../models.dart';
import '../composer_tools.dart';
import 'topic_detail_screen.dart';

/// 发帖 / 回复 / 私信编辑器
class ComposerScreen extends StatefulWidget {
  final bool isNewTopic;
  final bool isPrivateMessage;
  final int? topicId;
  final int? replyToPostNumber;
  final String? hint;
  final int? editPostId;
  final String? initialRaw;
  final String? initialRecipients;

  const ComposerScreen({
    super.key,
    this.isNewTopic = false,
    this.isPrivateMessage = false,
    this.topicId,
    this.replyToPostNumber,
    this.hint,
    this.editPostId,
    this.initialRaw,
    this.initialRecipients,
  });

  @override
  State<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends State<ComposerScreen> {
  late final AppState _app;
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _contentFocus = FocusNode();
  final _recipientsCtrl = TextEditingController();

  List<Category>? _categories;
  Map<int, String>? _parentNames;
  int? _selectedCategory;
  bool _busy = false;
  bool _uploading = false;
  String? _error;
  String? _draftKey;
  Timer? _draftTimer;
  bool _submitted = false;
  bool _preview = false;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _contentCtrl.text = widget.initialRaw ?? '';
    _recipientsCtrl.text = widget.initialRecipients ?? '';
    if (widget.editPostId == null) {
      final userId = _app.user?.id;
      if (userId != null) {
        final contextKey = widget.isPrivateMessage
            ? 'message_${widget.initialRecipients ?? 'new'}'
            : widget.isNewTopic
                ? 'topic'
                : 'reply_${widget.topicId}_${widget.replyToPostNumber ?? 0}';
        _draftKey = 'composer_draft_${userId}_$contextKey';
        _restoreDraft(_app);
        _titleCtrl.addListener(_scheduleDraft);
        _contentCtrl.addListener(_scheduleDraft);
        _recipientsCtrl.addListener(_scheduleDraft);
      }
    }
    if (widget.isNewTopic) {
      _loadCategories();
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _saveDraft();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _contentFocus.dispose();
    _recipientsCtrl.dispose();
    super.dispose();
  }

  void _restoreDraft(AppState app) {
    final stored = app.prefs.getString(_draftKey!);
    if (stored == null) return;
    try {
      final draft = jsonDecode(stored);
      if (draft is! Map) return;
      _titleCtrl.text = draft['title']?.toString() ?? '';
      _contentCtrl.text = draft['raw']?.toString() ?? '';
      _recipientsCtrl.text = draft['recipients']?.toString() ??
          widget.initialRecipients ?? '';
      _selectedCategory = toInt(draft['category']);
    } catch (_) {
      // An old or corrupted local draft must not block the composer.
    }
  }

  void _scheduleDraft() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), _saveDraft);
  }

  void _saveDraft() {
    final key = _draftKey;
    if (key == null || _submitted) return;
    final prefs = _app.prefs;
    if (_titleCtrl.text.trim().isEmpty && _contentCtrl.text.trim().isEmpty &&
        _recipientsCtrl.text.trim().isEmpty) {
      prefs.remove(key);
    } else {
      prefs.setString(key, jsonEncode({
        'title': _titleCtrl.text,
        'raw': _contentCtrl.text,
        'recipients': _recipientsCtrl.text,
        'category': _selectedCategory,
      }));
    }
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await context.read<AppState>().api.categories();
      final parents = <int, String>{};
      for (final c in cats) {
        if (c.parentId == null) parents[c.id] = c.name;
      }
      final usable = cats
          .where((c) => c.parentId != null && !c.readRestricted)
          .toList()
        ..sort((a, b) => (a.position ?? 99).compareTo(b.position ?? 99));
      if (!mounted) return;
      setState(() {
        _categories = usable;
        _parentNames = parents;
        if (!usable.any((c) => c.id == _selectedCategory)) _selectedCategory = null;
      });
    } catch (_) {}
  }

  /// 选择并上传图片，成功后把 Markdown 插入正文光标处
  Future<void> _pickAndUploadImage() async {
    if (_uploading) return;
    final app = context.read<AppState>();
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final file = files.isNotEmpty ? files.single : null;
      final path = file?.path;
      if (!mounted || file == null || path == null) return;

      setState(() => _uploading = true);
      final resp = await app.api.uploadImage(
        filePath: path,
        filename: file.name,
        onProgress: (sent, total) {
          // 进度由 _uploading 状态与 snackbar 提示
        },
      );
      if (!mounted) return;
      final shortUrl = resp['short_url']?.toString();
      final url = resp['url']?.toString();
      if (shortUrl == null && url == null) {
        throw '上传失败：响应缺少图片地址';
      }
      final markdown =
          '![${file.name}](${shortUrl ?? url})';
      final sel = _contentCtrl.selection;
      final text = _contentCtrl.text;
      final insertPos = sel.isValid ? sel.baseOffset : text.length;
      final newText = text.replaceRange(
          insertPos.clamp(0, text.length), insertPos.clamp(0, text.length), markdown);
      _contentCtrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
            offset: (insertPos + markdown.length).clamp(0, newText.length)),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('图片已上传并插入正文')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('图片上传失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _format(String before, String after, {String placeholder = '文字'}) {
    _contentCtrl.value = wrapSelection(_contentCtrl.value, before, after,
        placeholder: placeholder);
    setState(() => _preview = false);
    _contentFocus.requestFocus();
  }

  void _prefix(String prefix) {
    _contentCtrl.value = prefixLines(_contentCtrl.value, prefix);
    setState(() => _preview = false);
    _contentFocus.requestFocus();
  }

  Future<void> _insertPoll() async {
    final options = await showDialog<({List<String> options, bool multiple})>(
      context: context, builder: (_) => const _PollBuilderDialog());
    if (options == null || !mounted) return;
    try {
      final markup = buildPollMarkup(_contentCtrl.text, options.options,
          multiple: options.multiple);
      _format(markup, '', placeholder: '');
    } on FormatException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _submit() async {
    if (_busy || _uploading) return;
    final title = _titleCtrl.text.trim();
    // Editing must preserve Markdown indentation and trailing newlines.
    final raw = widget.editPostId == null
        ? _contentCtrl.text.trim()
        : _contentCtrl.text;
    if (widget.isPrivateMessage) {
      final targets = _recipientsCtrl.text
          .split(RegExp(r'[,，\s]+'))
          .where((s) => s.trim().isNotEmpty)
          .map((s) => s.trim())
          .toList();
      if (targets.isEmpty) {
        setState(() => _error = '请输入收件人用户名（多个用逗号分隔）');
        return;
      }
      if (title.isEmpty) {
        setState(() => _error = '请输入私信标题');
        return;
      }
      if (raw.isEmpty) {
        setState(() => _error = '请输入私信内容（支持 Markdown）');
        return;
      }
      await _doSubmit(title: title, raw: raw, targets: targets);
      return;
    }
    if (widget.isNewTopic && title.isEmpty) {
      setState(() => _error = '请输入标题');
      return;
    }
    if (raw.trim().isEmpty) {
      setState(() => _error = '请输入内容（支持 Markdown）');
      return;
    }
    await _doSubmit(title: title, raw: raw);
  }

  Future<void> _doSubmit({
    required String title,
    required String raw,
    List<String>? targets,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppState>();
    try {
      // 发帖设备信息：新话题与回复携带，私信不携带
      final mobileSource = widget.isPrivateMessage || widget.editPostId != null
          ? null
          : await app.mobileSourceFields();
      Map<String, dynamic> result;
      if (widget.editPostId != null) {
        await app.api.updatePost(widget.editPostId!, raw);
        result = const {};
      } else if (widget.isPrivateMessage) {
        result = await app.api.createPrivateMessage(
          title: title,
          raw: raw,
          targetUsernames: targets!,
        );
      } else if (widget.isNewTopic) {
        result = await app.api.createTopic(
          title: title,
          raw: raw,
          categoryId: _selectedCategory,
          mobileSource: mobileSource,
        );
      } else {
        result = await app.api.createReply(
          topicId: widget.topicId!,
          raw: raw,
          replyToPostNumber: widget.replyToPostNumber,
          mobileSource: mobileSource,
        );
      }
      if (!mounted) return;
      _submitted = true;
      _draftTimer?.cancel();
      if (_draftKey != null) await app.prefs.remove(_draftKey!);
      if (!mounted) return;
      Navigator.pop(context, true);
      final topicId = int.tryParse('${result['topic_id'] ?? widget.topicId}');
      if ((widget.isNewTopic || widget.isPrivateMessage) &&
          topicId != null &&
          topicId > 0) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TopicDetailScreen(topicId: topicId),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = widget.isPrivateMessage
        ? '写私信'
        : widget.editPostId != null
            ? '编辑帖子'
        : widget.isNewTopic
            ? '发起新话题'
            : '回复话题';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _busy || _uploading ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(widget.editPostId != null ? '保存' : '发送'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.hint != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(widget.hint!,
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.primary)),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.isPrivateMessage) ...[
                  TextField(
                    controller: _recipientsCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: '收件人用户名（多个用逗号分隔）',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.isNewTopic || widget.isPrivateMessage) ...[
                  TextField(
                    controller: _titleCtrl,
                    textInputAction: TextInputAction.next,
                    maxLength: 120,
                    decoration: const InputDecoration(hintText: '标题'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.isNewTopic) ...[
                  if (_categories != null)
                    DropdownButtonFormField<int>(
                      value: _selectedCategory,
                      decoration: const InputDecoration(hintText: '选择分类（可选）'),
                      items: [
                        for (final c in _categories!)
                          DropdownMenuItem(
                            value: c.id,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: c.color,
                                    borderRadius: BorderRadius.circular(2.5),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '${_parentNames?[c.parentId] ?? ''} / ${c.name}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() => _selectedCategory = v);
                        _scheduleDraft();
                      },
                    ),
                  const SizedBox(height: 12),
                ],
                Wrap(spacing: 2, children: [
                  IconButton(tooltip: '粗体', onPressed: _busy ? null : () => _format('**', '**'), icon: const Icon(Icons.format_bold)),
                  IconButton(tooltip: '斜体', onPressed: _busy ? null : () => _format('*', '*'), icon: const Icon(Icons.format_italic)),
                  IconButton(tooltip: '删除线', onPressed: _busy ? null : () => _format('~~', '~~'), icon: const Icon(Icons.format_strikethrough)),
                  IconButton(tooltip: '标题', onPressed: _busy ? null : () => _prefix('## '), icon: const Icon(Icons.title)),
                  IconButton(tooltip: '引用', onPressed: _busy ? null : () => _prefix('> '), icon: const Icon(Icons.format_quote)),
                  IconButton(tooltip: '列表', onPressed: _busy ? null : () => _prefix('- '), icon: const Icon(Icons.format_list_bulleted)),
                  IconButton(tooltip: '代码块', onPressed: _busy ? null : () => _format('\n```\n', '\n```\n', placeholder: '代码'), icon: const Icon(Icons.code)),
                  IconButton(tooltip: '链接', onPressed: _busy ? null : () => _format('[', '](https://)', placeholder: '链接文字'), icon: const Icon(Icons.link)),
                  IconButton(tooltip: '插入投票', onPressed: _busy ? null : _insertPoll, icon: const Icon(Icons.poll_outlined)),
                  TextButton.icon(onPressed: () => setState(() => _preview = !_preview),
                    icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined),
                    label: Text(_preview ? '继续编辑' : '预览')),
                ]),
                if (_preview)
                  Container(padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(minHeight: 220),
                    decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Markdown 预览（投票等站点插件以发布后效果为准）',
                        style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      HtmlWidget(md.markdownToHtml(_contentCtrl.text,
                        extensionSet: md.ExtensionSet.gitHubFlavored),
                        onTapUrl: (_) async => true),
                    ]),
                  )
                else
                TextField(
                  controller: _contentCtrl,
                  focusNode: _contentFocus,
                  maxLines: null,
                  minLines: 10,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    hintText: '正文内容，支持 Markdown 语法…',
                  ),
                  style: const TextStyle(fontSize: 14.5, height: 1.5),
                ),
                const SizedBox(height: 10),
                if (_draftKey != null)
                  Text('草稿自动保存在本机',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy || _uploading ? null : _pickAndUploadImage,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.image_outlined, size: 19),
                      label: Text(_uploading ? '上传中…' : '插入图片'),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '上传后自动以 Markdown 插入',
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_error!,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onErrorContainer)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PollBuilderDialog extends StatefulWidget {
  const _PollBuilderDialog();
  @override
  State<_PollBuilderDialog> createState() => _PollBuilderDialogState();
}
class _PollBuilderDialogState extends State<_PollBuilderDialog> {
  final _options = TextEditingController();
  bool _multiple = false;
  String? _error;
  @override
  void dispose() { _options.dispose(); super.dispose(); }
  void _insert() {
    final options = _options.text.split('\n').map((o) => o.trim()).where((o) => o.isNotEmpty).toList();
    try {
      buildPollMarkup('', options, multiple: _multiple);
      Navigator.pop(context, (options: options, multiple: _multiple));
    } on FormatException catch (e) { setState(() => _error = e.message); }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('插入投票'),
    content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _options, minLines: 4, maxLines: 8,
          decoration: const InputDecoration(labelText: '每行一个选项（2–20 项）')),
        CheckboxListTile(value: _multiple, title: const Text('允许多选'),
          onChanged: (v) => setState(() => _multiple = v ?? false)),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    ))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: _insert, child: const Text('插入正文')),
    ],
  );
}
