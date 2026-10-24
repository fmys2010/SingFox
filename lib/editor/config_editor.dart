import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';

import '../core/paths.dart';
import '../core/profiles.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../ui/widgets.dart';
import 'schema.dart';

const _codeTheme = <String, TextStyle>{
  'root': TextStyle(color: Color(0xFFD4D4D8)),
  'attr': TextStyle(color: Color(0xFF9CBFEA)),
  'string': TextStyle(color: Color(0xFFE3B587)),
  'number': TextStyle(color: Color(0xFFA8D5A2)),
  'literal': TextStyle(color: Color(0xFFD4A5E0)),
  'keyword': TextStyle(color: Color(0xFFD4A5E0)),
  'punctuation': TextStyle(color: Color(0xFF8B8B94)),
  'comment': TextStyle(color: Color(0xFF71717A)),
};

/// Prompt carrying a sing-box field or value.
class _SchemaPrompt extends CodePrompt {
  const _SchemaPrompt(this.s) : super(word: '');
  final Suggestion s;

  @override
  String get word => s.word;

  @override
  CodeAutocompleteResult get autocomplete => CodeAutocompleteResult.fromWord(s.word);

  @override
  bool match(String input) => s.word.startsWith(input);
}

class _SchemaPromptsBuilder implements CodeAutocompletePromptsBuilder {
  _SchemaPromptsBuilder(this.controller, this.schema);
  final CodeLineEditingController controller;
  final ConfigSchema? schema;

  @override
  CodeAutocompleteEditingValue? build(BuildContext context, CodeLine codeLine, CodeLineSelection selection) {
    final sc = schema;
    if (sc == null) return null;
    final lines = controller.codeLines;
    var offset = 0;
    for (var i = 0; i < selection.extentIndex; i++) {
      offset += lines[i].text.length + 1;
    }
    offset += selection.extentOffset;
    final r = sc.complete(controller.text, offset);
    if (r == null) return null;
    final (input, list) = r;
    return CodeAutocompleteEditingValue(input: input, prompts: [for (final s in list.take(60)) _SchemaPrompt(s)], index: 0);
  }
}

/// Types the closing half of `{}`, `[]`, `()` and `""` with the opening one,
/// and steps over a closer when the next keystroke repeats it. re_editor's
/// own pairing only fires on balanced lines; when it does fire it inserts
/// both halves at once, which this listener leaves alone.
class _AutoPair {
  _AutoPair._(this.c) {
    _snap();
    c.addListener(_onChange);
  }

  // One per controller, however many editors show it.
  static final _attached = Expando<_AutoPair>();
  static void attach(CodeLineEditingController c) => _attached[c] ??= _AutoPair._(c);

  static const _pairs = {'{': '}', '[': ']', '(': ')', '"': '"'};
  static const _closers = {'}', ']', ')', '"'};
  static final _pairBefore = RegExp(r'[\s,:}\])]');

  final CodeLineEditingController c;
  int _line = -1, _offset = -1;
  String _text = '';
  bool _busy = false;

  void _snap() {
    final s = c.selection;
    _line = s.extentIndex;
    _offset = s.extentOffset;
    _text = s.extentIndex < c.codeLines.length ? c.codeLines[s.extentIndex].text : '';
  }

  void _onChange() {
    if (_busy) return;
    final (line, offset, prev) = (_line, _offset, _text);
    _snap();
    final s = c.selection;
    // Only a single character typed at the caret counts.
    if (!s.isCollapsed || _line != line || _offset != offset + 1 || _text.length != prev.length + 1) return;
    if (!_text.startsWith(prev.substring(0, offset)) || _text.substring(_offset) != prev.substring(offset)) return;
    final ch = _text[offset];
    final next = _offset < _text.length ? _text[_offset] : '';
    if (_closers.contains(ch) && next == ch) return _run(c.deleteForward);
    final close = _pairs[ch];
    if (close == null || (next.isNotEmpty && !_pairBefore.hasMatch(next))) return;
    if (ch == '"' && '"'.allMatches(prev.substring(0, offset)).length.isOdd) return;
    final at = CodeLineSelection.collapsed(index: _line, offset: _offset);
    _run(() {
      c.replaceSelection(close);
      c.selection = at;
    });
  }

  // Edits made from inside a listener land after the current update.
  void _run(VoidCallback edit) => scheduleMicrotask(() {
        _busy = true;
        try {
          edit();
        } finally {
          _busy = false;
          _snap();
        }
      });
}

/// JSON editor with sing-box schema completion. [onExpand] shows the
/// expand button; [fill] lets it grow to its parent.
class ConfigCodeEditor extends StatefulWidget {
  const ConfigCodeEditor({super.key, required this.controller, this.fontSize = 12.5, this.minimap = false});
  final CodeLineEditingController controller;
  final double fontSize;
  final bool minimap;

  @override
  State<ConfigCodeEditor> createState() => _ConfigCodeEditorState();
}

class _ConfigCodeEditorState extends State<ConfigCodeEditor> {
  ConfigSchema? _schema;
  final _scroll = CodeScrollController();

  @override
  void initState() {
    super.initState();
    _AutoPair.attach(widget.controller);
    ConfigSchema.load().then((s) {
      if (mounted) setState(() => _schema = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final editor = CodeAutocomplete(
      viewBuilder: (context, notifier, onSelected) => _PromptList(notifier: notifier, onSelected: onSelected),
      promptsBuilder: _SchemaPromptsBuilder(widget.controller, _schema),
      child: CodeEditor(
        controller: widget.controller,
        hint: '粘贴或输入 sing-box 配置（JSON）',
        scrollController: _scroll,
        wordWrap: false,
        style: CodeEditorStyle(
          fontSize: widget.fontSize,
          fontFamily: SF.mono,
          fontFamilyFallback: SF.monoFallback,
          fontHeight: 1.55,
          textColor: const Color(0xFFD4D4D8),
          backgroundColor: Colors.transparent,
          selectionColor: SF.accent.withValues(alpha: .25),
          cursorColor: SF.accent,
          cursorWidth: 2,
          cursorLineColor: const Color(0xFF151518),
          chunkIndicatorColor: SF.faint,
          codeTheme: CodeHighlightTheme(languages: {'json': CodeHighlightThemeMode(mode: langJson)}, theme: _codeTheme),
        ),
        indicatorBuilder: (context, editing, chunk, notifier) => Row(children: [
          DefaultCodeLineNumber(
            controller: editing,
            notifier: notifier,
            textStyle: SF.m(widget.fontSize - .5, color: SF.faint),
            focusedTextStyle: SF.m(widget.fontSize - .5, color: SF.text),
          ),
          DefaultCodeChunkIndicator(width: 16, controller: chunk, notifier: notifier),
        ]),
      ),
    );
    if (!widget.minimap) return editor;
    return Row(children: [
      Expanded(child: editor),
      Container(width: 1, color: SF.lineSoft),
      SizedBox(width: 76, child: _Minimap(controller: widget.controller, scroll: _scroll)),
    ]);
  }
}

class _PromptList extends StatefulWidget implements PreferredSizeWidget {
  const _PromptList({required this.notifier, required this.onSelected});
  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  static const itemH = 26.0;

  @override
  Size get preferredSize => Size(340, min(itemH * notifier.value.prompts.length, itemH * 9) + 38);

  @override
  State<_PromptList> createState() => _PromptListState();
}

class _PromptListState extends State<_PromptList> {
  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_changed);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    setState(() {});
    final i = widget.notifier.value.index;
    if (_sc.hasClients) {
      final top = i * _PromptList.itemH, view = _sc.position.viewportDimension;
      if (top < _sc.offset) _sc.jumpTo(top);
      if (top + _PromptList.itemH > _sc.offset + view) _sc.jumpTo(top + _PromptList.itemH - view);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.notifier.value;
    return Container(
      constraints: BoxConstraints.loose(widget.preferredSize),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        border: Border.all(color: const Color(0xFF2E2E33)),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 36, offset: Offset(0, 14))],
      ),
      padding: const EdgeInsets.all(4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: ListView.builder(
            controller: _sc,
            shrinkWrap: true,
            itemCount: v.prompts.length,
            itemExtent: _PromptList.itemH,
            itemBuilder: (context, i) {
              final s = (v.prompts[i] as _SchemaPrompt).s;
              final on = i == v.index;
              return GestureDetector(
                onTap: () => widget.onSelected(v.copyWith(index: i).autocomplete),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(color: on ? const Color(0xFF26262C) : null, borderRadius: BorderRadius.circular(6)),
                  child: Row(children: [
                    Container(
                      width: 18,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFF3A3A40)), borderRadius: BorderRadius.circular(4)),
                      child: Text(s.isKey ? (s.type == 'object' || s.type.endsWith(']') ? '{}' : 'k') : 'v',
                          style: SF.m(9, color: s.isKey ? const Color(0xFF9CBFEA) : const Color(0xFFE3B587))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: s.word.substring(0, min(v.input.length, s.word.length)), style: SF.m(12.5, color: SF.accent)),
                          TextSpan(text: s.word.substring(min(v.input.length, s.word.length)), style: SF.m(12.5)),
                        ]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(s.type, style: SF.m(11, color: SF.text3), overflow: TextOverflow.ellipsis),
                  ]),
                ),
              );
            },
          ),
        ),
        Container(
          height: 28,
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF222226)))),
          child: Text('↑↓ 选择 · Enter 插入 · Esc 关闭 · 来自 sing-box schema', style: SF.t(11, color: SF.text3)),
        ),
      ]),
    );
  }
}

class _Minimap extends StatelessWidget {
  const _Minimap({required this.controller, required this.scroll});
  final CodeLineEditingController controller;
  final CodeScrollController scroll;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([controller, scroll.verticalScroller]),
        builder: (context, _) => CustomPaint(painter: _MinimapPainter(controller, scroll.verticalScroller), size: Size.infinite),
      );
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter(this.c, this.v);
  final CodeLineEditingController c;
  final ScrollController v;

  @override
  void paint(Canvas canvas, Size size) {
    final lines = c.codeLines;
    final cur = c.selection.extentIndex;
    const rowH = 3.5;
    final p = Paint();
    for (var i = 0; i < lines.length && i * rowH < size.height; i++) {
      final t = lines[i].text;
      final indent = t.length - t.trimLeft().length;
      p.color = i == cur ? SF.accent : const Color(0xFF3A3A40);
      canvas.drawRRect(
        RRect.fromLTRBR(10 + indent * .5, 10 + i * rowH, 10 + indent * .5 + min(52.0, max(2.0, t.trim().length * .5)), 12 + i * rowH, const Radius.circular(1)),
        p,
      );
    }
    if (v.hasClients && v.position.hasContentDimensions) {
      final pos = v.position;
      final total = pos.maxScrollExtent + pos.viewportDimension;
      final h = lines.length * rowH;
      final top = 10 + h * pos.pixels / total, bh = h * pos.viewportDimension / total;
      canvas.drawRRect(RRect.fromLTRBR(4, top, size.width - 4, top + bh, const Radius.circular(3)), Paint()..color = const Color(0x0DFFFFFF));
      canvas.drawRRect(
          RRect.fromLTRBR(4, top, size.width - 4, top + bh, const Radius.circular(3)),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0xFF2A2A2E));
    }
  }

  @override
  bool shouldRepaint(_MinimapPainter old) => true;
}

/// Validates [text] with the real core (`sing-box check`).
Future<String?> checkWithCore(String text) async {
  try {
    ProfileStore.validate(text);
  } on FormatException catch (e) {
    return e.message;
  }
  final core = AppState.I.coreBinary;
  if (core == null) return null;
  final tmp = File('${Paths.I.work.path}${Platform.pathSeparator}check.json');
  await tmp.writeAsString(text);
  final r = await Process.run(core, ['check', '-c', tmp.path, '--disable-color']);
  if (r.exitCode == 0) return null;
  final err = '${r.stderr}${r.stdout}'.trim().split('\n').where((l) => l.trim().isNotEmpty);
  return err.isEmpty ? '校验失败' : err.last.replaceFirst(RegExp(r'^FATAL\[\d+\]\s*'), '');
}

/// Near-fullscreen editor: outline, completion, minimap, status bar.
class BigEditorDialog extends StatefulWidget {
  const BigEditorDialog({super.key, required this.controller, required this.title});
  final CodeLineEditingController controller;
  final String title;

  static Future<void> open(BuildContext context, CodeLineEditingController c, String title) => showGeneralDialog(
        context: context,
        barrierColor: const Color(0x8C000000),
        barrierDismissible: false,
        pageBuilder: (_, _, _) => BigEditorDialog(controller: c, title: title),
      );

  @override
  State<BigEditorDialog> createState() => _BigEditorDialogState();
}

class _BigEditorDialogState extends State<BigEditorDialog> {
  String? _problem;
  bool _checked = false, _checking = false;

  CodeLineEditingController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    _onChange();
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    super.dispose();
  }

  String? _lastText;

  void _onChange() {
    if (c.text == _lastText) {
      setState(() {});
      return;
    }
    _lastText = c.text;
    try {
      ProfileStore.validate(c.text);
      _problem = null;
    } on FormatException catch (e) {
      _problem = e.message;
    }
    _checked = false;
    setState(() {});
  }

  void _format() {
    try {
      c.text = const JsonEncoder.withIndent('  ').convert(jsonDecode(c.text));
    } catch (_) {
      toast(context, '当前内容不是有效 JSON，无法格式化', error: true);
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final err = await checkWithCore(c.text);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checked = err == null;
      _problem = err;
    });
  }

  List<(String, String, int, int)> _outline() {
    // (label, symbol, depth, line)
    final out = <(String, String, int, int)>[];
    final lines = c.text.split('\n');
    int lineOf(Pattern p, [int from = 0]) {
      for (var i = from; i < lines.length; i++) {
        if (lines[i].contains(p)) return i;
      }
      return -1;
    }

    Map<String, dynamic>? j;
    try {
      j = jsonDecode(c.text) as Map<String, dynamic>;
    } catch (_) {}
    if (j == null) return out;
    for (final k in j.keys) {
      final v = j[k];
      final l = lineOf('"$k"');
      out.add((k, v is List ? '[]' : '{}', 0, l));
      if (v is List) {
        for (final e in v) {
          if (e is Map && e['tag'] != null) {
            out.add(('${e['tag']}', (e['type'] ?? '').toString().padRight(2).substring(0, 2), 1, lineOf('"${e['tag']}"', max(l, 0))));
          }
        }
      } else if (v is Map) {
        for (final sk in v.keys) {
          if (v[sk] is List || v[sk] is Map) {
            out.add((sk, v[sk] is List ? '[]' : '{}', 1, lineOf('"$sk"', max(l, 0))));
          }
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final sel = c.selection;
    final ok = _problem == null;
    return Center(
      child: Container(
        width: min(MediaQuery.of(context).size.width - 64, 1400),
        height: MediaQuery.of(context).size.height - 64,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0C0C0E),
          border: Border.all(color: const Color(0xFF2A2A2E)),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 80, offset: Offset(0, 30))],
        ),
        child: Material(
          color: Colors.transparent,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyF, shift: true, alt: true): _format,
              const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
            },
            child: Column(children: [
            Container(
              height: 48,
              padding: const EdgeInsets.only(left: 18, right: 10),
              decoration: const BoxDecoration(color: SF.surface, border: Border(bottom: BorderSide(color: SF.lineInner))),
              child: Row(children: [
                const Icon(Icons.data_object_rounded, size: 16, color: SF.text2),
                const SizedBox(width: 10),
                Text(widget.title, style: SF.t(13.5, weight: FontWeight.w600)),
                const SizedBox(width: 10),
                OutlineTag('sing-box ${AppState.I.coreVersion.isEmpty ? '' : AppState.I.coreVersion} schema'),
                const Spacer(),
                SFButton('格式化', height: 30, onTap: _format, trailing: Text('Shift+Alt+F', style: SF.m(11, color: SF.text3))),
                const SizedBox(width: 6),
                SFButton(_checking ? '校验中…' : '用内核校验', height: 30, onTap: _checking ? null : _check),
                const SizedBox(width: 6),
                SFButton('完成', kind: BtnKind.primary, height: 30, onTap: () => Navigator.pop(context)),
                const SizedBox(width: 4),
                SFIconButton(Icons.close_fullscreen_rounded, tooltip: '收起', bordered: false, size: 30, onTap: () => Navigator.pop(context)),
              ]),
            ),
            Expanded(
              child: Row(children: [
                Container(
                  width: 208,
                  color: const Color(0xFF0E0E10),
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Text('大纲', style: SF.t(11.5, color: SF.text3))),
                    Expanded(
                      child: ListView(children: [
                        for (final (label, sym, depth, line) in _outline())
                          Tap(
                            radius: 6,
                            onTap: line < 0 ? null : () => c.selection = CodeLineSelection.collapsed(index: line, offset: 0),
                            child: Container(
                              height: 26,
                              padding: EdgeInsets.only(left: 8.0 + depth * 14, right: 8),
                              decoration: BoxDecoration(
                                color: line >= 0 && line <= sel.extentIndex && depth == 1 && _isCurrent(line) ? const Color(0xFF1A1A1E) : null,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(children: [
                                SizedBox(width: 18, child: Text(sym, style: SF.m(10.5, color: SF.text3))),
                                const SizedBox(width: 4),
                                Expanded(child: Text(label, style: SF.t(12.5, color: SF.text2), overflow: TextOverflow.ellipsis)),
                              ]),
                            ),
                          ),
                      ]),
                    ),
                  ]),
                ),
                Container(width: 1, color: SF.lineInner),
                Expanded(child: Padding(padding: const EdgeInsets.only(top: 8), child: ConfigCodeEditor(controller: c, fontSize: 13, minimap: true))),
              ]),
            ),
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(color: SF.surface, border: Border(top: BorderSide(color: SF.lineInner))),
              child: Row(children: [
                Icon(ok ? Icons.check_rounded : Icons.error_outline_rounded, size: 13, color: ok ? SF.ok : SF.bad),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    ok ? (_checked ? '内核校验通过' : 'JSON 结构正常') : _problem!,
                    style: SF.t(11.5, color: ok ? SF.ok : SF.bad),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 24),
                Text('行 ${sel.extentIndex + 1}，列 ${sel.extentOffset + 1}   空格: 2   UTF-8   JSON · sing-box', style: SF.m(11.5, color: SF.text3)),
              ]),
            ),
          ]),
          ),
        ),
      ),
    );
  }

  bool _isCurrent(int line) {
    final outline = _outline().where((e) => e.$3 == 1 && e.$4 >= 0).map((e) => e.$4).toList()..sort();
    final cur = c.selection.extentIndex;
    int? best;
    for (final l in outline) {
      if (l <= cur) best = l;
    }
    return best == line;
  }
}
