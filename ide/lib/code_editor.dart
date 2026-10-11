// The editor: syntax colours from the compiler's highlighter, a wavy underline under errors, and a
// gutter with line numbers and each line's cycle cost (mean per evaluation, from the emulator).
import 'dart:math';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

class CodeController extends TextEditingController {
  CodeController({super.text});

  List<Diagnostic> _diags = const [];
  set diagnostics(List<Diagnostic> d) {
    _diags = d;
    notifyListeners();
  }

  /// [start, end) of the source a positioned diagnostic points at: the token at its column, or
  /// the whole line when it has no column.
  static (int, int)? errorRange(String src, Diagnostic d) {
    if (d.line == null) return null;
    final lines = src.split('\n');
    if (d.line! < 1 || d.line! > lines.length) return null;
    var start = 0;
    for (var i = 0; i < d.line! - 1; i++) {
      start += lines[i].length + 1;
    }
    final line = lines[d.line! - 1];
    if (d.column == null || d.column! < 1 || d.column! > line.length) {
      final lead = line.length - line.trimLeft().length;
      return (start + lead, start + max(lead + 1, line.trimRight().length));
    }
    final c = d.column! - 1;
    var e = c + 1;
    final word = RegExp(r'[A-Za-z0-9_.]');
    if (word.hasMatch(line[c])) {
      while (e < line.length && word.hasMatch(line[e])) {
        e++;
      }
    }
    return (start + c, start + e);
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    final src = text;
    final kinds = List<TokenKind?>.filled(src.length, null);
    for (final h in highlight(src)) {
      for (var i = h.start; i < h.end && i < src.length; i++) {
        kinds[i] = h.kind;
      }
    }
    final err = List<bool>.filled(src.length, false);
    for (final d in _diags.where((d) => d.isError)) {
      final r = errorRange(src, d);
      if (r == null) continue;
      for (var i = r.$1; i < r.$2 && i < src.length; i++) {
        err[i] = true;
      }
    }
    final spans = <TextSpan>[];
    var i = 0;
    while (i < src.length) {
      final k = kinds[i], e = err[i];
      var j = i + 1;
      while (j < src.length && kinds[j] == k && err[j] == e) {
        j++;
      }
      spans.add(TextSpan(
        text: src.substring(i, j),
        style: TextStyle(
          color: k == null ? Sc.body : Sc.token(k),
          fontStyle:
              k == TokenKind.comment ? FontStyle.italic : FontStyle.normal,
          decoration: e ? TextDecoration.underline : null,
          decorationStyle: TextDecorationStyle.wavy,
          decorationColor: Sc.red,
          decorationThickness: 1.6,
        ),
      ));
      i = j;
    }
    return TextSpan(style: style, children: spans);
  }
}

/// Colour for a line costing [c] cycles per evaluation.
Color costColor(double c) => c <= 20
    ? Sc.green
    : c <= 80
        ? Sc.gold
        : c <= 200
            ? Sc.amber
            : Sc.red;

class CodeEditor extends StatefulWidget {
  final CodeController controller;
  final StageAnalysis? analysis;
  final double fontSize;
  const CodeEditor(
      {super.key,
      required this.controller,
      required this.analysis,
      this.fontSize = 14});

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final _vScroll = ScrollController(), _hScroll = ScrollController();
  final _focus = FocusNode();

  double get _lineHeight => (widget.fontSize * 1.5).roundToDouble();

  TextStyle get _mono => TextStyle(
      fontFamily: Sc.mono,
      fontFamilyFallback: Sc.monoFallback,
      fontSize: widget.fontSize,
      height: _lineHeight / widget.fontSize,
      color: Sc.body);

  @override
  void dispose() {
    _vScroll.dispose();
    _hScroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Tab inserts two spaces; Enter keeps the indentation of the line.
  KeyEventResult _onKey(FocusNode node, KeyEvent ev) {
    if (ev is! KeyDownEvent && ev is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final c = widget.controller, sel = c.selection;
    if (!sel.isValid) return KeyEventResult.ignored;
    String? insert;
    if (ev.logicalKey == LogicalKeyboardKey.tab) {
      insert = '  ';
    } else if (ev.logicalKey == LogicalKeyboardKey.enter ||
        ev.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final before = c.text.substring(0, sel.start);
      final lineStart = before.lastIndexOf('\n') + 1;
      final line = before.substring(lineStart);
      var indent = line.substring(0, line.length - line.trimLeft().length);
      if (line.trimRight().endsWith('{')) indent += '  ';
      insert = '\n$indent';
    }
    if (insert == null) return KeyEventResult.ignored;
    final t = c.text.replaceRange(sel.start, sel.end, insert);
    c.value = TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(offset: sel.start + insert.length));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final src = widget.controller.text;
        final lines = src.split('\n');
        final a = widget.analysis;
        final costs = a?.lines ?? const <int, LineCost>{};
        final maxCost = costs.entries
            .where((e) => e.key > 0)
            .fold(1.0, (m, e) => max(m, e.value.cycles));
        final errLines = <int, String>{
          for (final d in widget.controller._diags.where((d) => d.line != null))
            d.line!: d.message,
        };
        // no wrapping (the gutter is one row per line): the text is as wide as its widest line,
        // measured in the editor's own style, with room for italics and the caret
        final widest = lines.fold('', (String w, l) => l.length > w.length ? l : w);
        final measured = (TextPainter(
                text: TextSpan(text: widest, style: _mono.copyWith(fontStyle: FontStyle.italic)),
                textDirection: TextDirection.ltr,
                maxLines: 1)
              ..layout())
            .width;
        return LayoutBuilder(builder: (context, box) {
          const gutterW = 112.0;
          final textW = max(box.maxWidth - gutterW, measured * 1.08 + 64);
          return Stack(children: [
            // the gutter's background fills the view, however short the file
            Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: gutterW,
                child: Container(color: Sc.inset)),
            Scrollbar(
              controller: _vScroll,
              child: SingleChildScrollView(
                controller: _vScroll,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: gutterW,
                      padding: const EdgeInsets.only(top: 8, bottom: 200),
                      child: Column(
                        children: [
                          for (var i = 1; i <= lines.length; i++)
                            _GutterRow(
                              line: i,
                              height: _lineHeight,
                              cost: costs[i],
                              maxCost: maxCost,
                              error: errLines[i],
                              style: _mono.copyWith(
                                  fontSize: widget.fontSize * 0.8,
                                  color: Sc.faint),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: _hScroll,
                        child: SingleChildScrollView(
                          controller: _hScroll,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: textW,
                            child: Focus(
                              onKeyEvent: _onKey,
                              child: TextField(
                                controller: widget.controller,
                                focusNode: _focus,
                                maxLines: null,
                                autofocus: true,
                                style: _mono,
                                strutStyle: StrutStyle(
                                    fontFamily: Sc.mono,
                                    fontFamilyFallback: Sc.monoFallback,
                                    fontSize: widget.fontSize,
                                    height: _lineHeight / widget.fontSize,
                                    forceStrutHeight: true),
                                cursorColor: Sc.primary,
                                keyboardType: TextInputType.multiline,
                                autocorrect: false,
                                enableSuggestions: false,
                                smartQuotesType: SmartQuotesType.disabled,
                                smartDashesType: SmartDashesType.disabled,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isCollapsed: true,
                                  contentPadding:
                                      EdgeInsets.fromLTRB(14, 8, 14, 200),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ]);
        });
      },
    );
  }
}

class _GutterRow extends StatelessWidget {
  final int line;
  final double height, maxCost;
  final LineCost? cost;
  final String? error;
  final TextStyle style;
  const _GutterRow(
      {required this.line,
      required this.height,
      required this.cost,
      required this.maxCost,
      required this.error,
      required this.style});

  @override
  Widget build(BuildContext context) {
    final c = cost;
    final row = SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: 12,
            child: error == null
                ? null
                : const Center(
                    child: Icon(Icons.circle, size: 7, color: Sc.red)),
          ),
          SizedBox(
              width: 30,
              child: Text('$line', textAlign: TextAlign.right, style: style)),
          const SizedBox(width: 8),
          Expanded(
            child: c == null
                ? const SizedBox()
                : Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      FractionallySizedBox(
                        widthFactor: (c.cycles / maxCost).clamp(0.04, 1.0),
                        child: Container(
                          height: height * 0.62,
                          decoration: BoxDecoration(
                            color: costColor(c.cycles).withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          c.ran < 0.999
                              ? '${c.cycles.toStringAsFixed(0)}*'
                              : c.cycles.toStringAsFixed(0),
                          style: style.copyWith(color: costColor(c.cycles)),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
    final tip = error ??
        (c == null
            ? null
            : '${c.cycles.toStringAsFixed(1)} cycles per evaluation (mean), including the routines this line calls'
                '${c.ran < 0.999 ? '\nruns in ${(c.ran * 100).round()}% of evaluations (inside an if)' : ''}');
    return tip == null ? row : Tooltip(message: tip, child: row);
  }
}
