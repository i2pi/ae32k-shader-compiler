// The editor: syntax colours from the compiler's highlighter, a wavy underline under errors, and a
// gutter with line numbers and each line's cycle cost (mean per evaluation, from the emulator).
import 'dart:math';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'completion.dart';
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

  /// The stage being edited (0 warp, 1 scan, 2 vertex), for completions.
  final int slot;
  const CodeEditor(
      {super.key,
      required this.controller,
      required this.analysis,
      this.slot = 0,
      this.fontSize = 14});

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final _vScroll = ScrollController(), _hScroll = ScrollController();
  final _focus = FocusNode();
  static const _gutterW = 112.0, _padLeft = 14.0, _padTop = 8.0;

  // autocompletion: shown while typing, from completion.dart
  CompletionResult? _comp;
  int _compSel = 0;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_onChange);
  }

  void _onChange() {
    final c = widget.controller, text = c.text, sel = c.selection;
    final typed = text != _lastText;
    final grew = text.length > _lastText.length;
    _lastText = text;
    if (!sel.isValid || !sel.isCollapsed) return _hide();
    if (!typed) {
      // a cursor move: keep the list only while the cursor stays in the word being completed
      final r = _comp;
      if (r != null &&
          (sel.baseOffset < r.start || sel.baseOffset > text.length)) {
        _hide();
      }
      return;
    }
    if (!grew && _comp == null) {
      return; // deleting does not open the list, but narrows it
    }
    final r = complete(text, sel.baseOffset, widget.slot);
    if (r == null || r.items.isEmpty) return _hide();
    setState(() {
      _comp = r;
      _compSel = 0;
    });
  }

  void _hide() {
    if (_comp != null) setState(() => _comp = null);
  }

  void _accept(Completion item) {
    final c = widget.controller, r = _comp!, at = c.selection.baseOffset;
    final t = c.text.replaceRange(r.start, at, item.insert);
    _comp = null;
    c.value = TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(
            offset: r.start + (item.caret ?? item.insert.length)));
    _lastText = t;
    // `in.` / `out.` open the next list straight away
    if (item.insert.endsWith('.')) {
      final n = complete(t, r.start + item.insert.length, widget.slot);
      if (n != null && n.items.isNotEmpty) _comp = n;
    }
    setState(() => _compSel = 0);
    _focus.requestFocus();
  }

  double get _lineHeight => (widget.fontSize * 1.5).roundToDouble();

  TextStyle get _mono => TextStyle(
      fontFamily: Sc.mono,
      fontFamilyFallback: Sc.monoFallback,
      fontSize: widget.fontSize,
      height: _lineHeight / widget.fontSize,
      color: Sc.body);

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
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
    final comp = _comp;
    if (comp != null) {
      final k = ev.logicalKey;
      if (k == LogicalKeyboardKey.arrowDown ||
          k == LogicalKeyboardKey.arrowUp) {
        setState(() => _compSel =
            (_compSel + (k == LogicalKeyboardKey.arrowDown ? 1 : -1)) %
                comp.items.length);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.numpadEnter ||
          k == LogicalKeyboardKey.tab) {
        _accept(comp.items[_compSel.clamp(0, comp.items.length - 1)]);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.escape) {
        _hide();
        return KeyEventResult.handled;
      }
    }
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
        final widest =
            lines.fold('', (String w, l) => l.length > w.length ? l : w);
        final measured = (TextPainter(
                text: TextSpan(
                    text: widest,
                    style: _mono.copyWith(fontStyle: FontStyle.italic)),
                textDirection: TextDirection.ltr,
                maxLines: 1)
              ..layout())
            .width;
        return LayoutBuilder(builder: (context, box) {
          const gutterW = _gutterW;
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
                      padding: const EdgeInsets.only(top: _padTop, bottom: 200),
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
                                  contentPadding: EdgeInsets.fromLTRB(
                                      _padLeft, _padTop, 14, 200),
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
            if (_comp != null) _dropdown(src, box),
          ]);
        });
      },
    );
  }

  /// The completion list, just below the start of the word being completed.
  Widget _dropdown(String src, BoxConstraints box) {
    final r = _comp!;
    final lineStart = src.lastIndexOf('\n', r.start - 1) + 1;
    final line = '\n'.allMatches(src.substring(0, lineStart)).length;
    final x = (TextPainter(
            text:
                TextSpan(text: src.substring(lineStart, r.start), style: _mono),
            textDirection: TextDirection.ltr,
            maxLines: 1)
          ..layout())
        .width;
    const rowH = 26.0, w = 420.0;
    final shown = min(r.items.length, 8);
    return ListenableBuilder(
      listenable: Listenable.merge([_vScroll, _hScroll]),
      builder: (context, _) {
        final v = _vScroll.hasClients ? _vScroll.offset : 0.0,
            h = _hScroll.hasClients ? _hScroll.offset : 0.0;
        var top = _padTop + (line + 1) * _lineHeight - v + 2;
        if (top + shown * rowH > box.maxHeight) {
          top = top - _lineHeight - shown * rowH - 4; // flip above
        }
        final left = (_gutterW + _padLeft + x - h - 30)
            .clamp(0.0, max(0.0, box.maxWidth - w))
            .toDouble();
        return Positioned(
          left: left,
          top: top,
          width: w,
          height: shown * rowH + 6,
          child: Material(
            color: const Color(0xFF2E2F34),
            elevation: 3,
            shadowColor: Colors.black54,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 3),
              itemExtent: rowH,
              itemCount: r.items.length,
              itemBuilder: (context, i) {
                final it = r.items[i], on = i == _compSel;
                return GestureDetector(
                  onTapDown: (_) => _accept(it),
                  child: Container(
                    color: on ? Sc.blue.withValues(alpha: 0.28) : null,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: [
                      Container(
                        width: 18,
                        alignment: Alignment.center,
                        child: Text(_kindLetter(it.kind),
                            style: Sc.caps(10.5,
                                color: _kindColor(it.kind),
                                weight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 6),
                      Text(it.label,
                          style: _mono.copyWith(
                              fontSize: 13,
                              height: 1.0,
                              color: _kindColor(it.kind))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(it.detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Sc.uiText(12, color: on ? Sc.body : Sc.faint)),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  static String _kindLetter(CompletionKind k) => switch (k) {
        CompletionKind.keyword => 'K',
        CompletionKind.function => 'F',
        CompletionKind.constant => 'C',
        CompletionKind.local => 'L',
        CompletionKind.input => 'IN',
        CompletionKind.output => 'OUT',
        CompletionKind.register => 'R',
        CompletionKind.mode => 'M',
      };

  static Color _kindColor(CompletionKind k) => switch (k) {
        CompletionKind.keyword => Sc.token(TokenKind.keyword),
        CompletionKind.function => Sc.token(TokenKind.function),
        CompletionKind.constant => Sc.token(TokenKind.constant),
        CompletionKind.local => Sc.token(TokenKind.local),
        CompletionKind.input => Sc.token(TokenKind.input),
        CompletionKind.output => Sc.token(TokenKind.output),
        CompletionKind.register => Sc.token(TokenKind.register),
        CompletionKind.mode => Sc.token(TokenKind.mode),
      };
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
