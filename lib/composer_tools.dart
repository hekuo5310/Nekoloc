import 'package:flutter/services.dart';

TextEditingValue wrapSelection(TextEditingValue value, String before,
    String after, {String placeholder = '文字'}) {
  final selection = value.selection;
  final start = selection.isValid ? selection.start.clamp(0, value.text.length) : value.text.length;
  final end = selection.isValid ? selection.end.clamp(start, value.text.length) : start;
  final selected = value.text.substring(start, end);
  final content = selected.isEmpty ? placeholder : selected;
  final text = value.text.replaceRange(start, end, '$before$content$after');
  return TextEditingValue(text: text, selection: TextSelection(
    baseOffset: start + before.length, extentOffset: start + before.length + content.length));
}

TextEditingValue prefixLines(TextEditingValue value, String prefix) {
  final selection = value.selection;
  final start = selection.isValid ? selection.start.clamp(0, value.text.length) : value.text.length;
  final end = selection.isValid ? selection.end.clamp(start, value.text.length) : start;
  final lineStart = start == 0 ? 0 : value.text.lastIndexOf('\n', start - 1) + 1;
  final content = value.text.substring(lineStart, end);
  final replacement = content.split('\n').map((line) => '$prefix$line').join('\n');
  return TextEditingValue(text: value.text.replaceRange(lineStart, end, replacement),
    selection: TextSelection.collapsed(offset: lineStart + replacement.length));
}

String buildPollMarkup(String existing, List<String> options, {bool multiple = false}) {
  final lines = options.map((o) => o.trim()).where((o) => o.isNotEmpty).toList();
  if (lines.length < 2 || lines.length > 20) throw const FormatException('请填写 2–20 个选项');
  if (lines.toSet().length != lines.length) throw const FormatException('投票选项不能重复');
  if (lines.any((line) => line.contains('\n') || RegExp(r'\[/?poll\b', caseSensitive: false).hasMatch(line))) {
    throw const FormatException('选项不能包含投票区块标记');
  }
  final used = RegExp(r'\bname=(poll\d+)\b').allMatches(existing).map((m) => m.group(1)).toSet();
  var number = 1;
  while (used.contains('poll$number')) { number++; }
  final type = multiple ? 'multiple min=1 max=${lines.length}' : 'regular';
  return '\n[poll name=poll$number type=$type]\n${lines.map((line) => '* $line').join('\n')}\n[/poll]\n';
}
