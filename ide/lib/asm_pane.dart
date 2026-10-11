// The generated assembly beside the source: each instruction's address and mean cycles per
// evaluation (from the same emulator runs as the gutter), linked to the source line it came
// from. The instructions of the line under the cursor are highlighted and scrolled into view;
// clicking an instruction moves the cursor to its source line.
import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:flutter/material.dart';

import 'code_editor.dart' show costColor;
import 'theme.dart';

class _Row {
  final String text, comment;
  final int? line, addr;
  final bool label;
  const _Row(this.text, this.comment, this.line, this.addr, this.label);
}

final _tag = RegExp(r'\s*// @L(\d+)');

List<_Row> _rows(CompiledStage st) {
  final out = <_Row>[];
  final lines = st.asm.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var t = lines[i];
    if (t.trim().isEmpty) continue;
    final m = _tag.firstMatch(t);
    final line = m == null ? null : int.parse(m.group(1)!);
    if (m != null) t = t.replaceRange(m.start, m.end, '');
    final c = t.indexOf('//');
    final code = (c >= 0 ? t.substring(0, c) : t).trimRight(),
        comment = c >= 0 ? t.substring(c).trim() : '';
    final label = !code.startsWith(' ') && code.trim().endsWith(':');
    out.add(_Row(code.trim(), comment, line, st.asmAddr[i + 1], label));
  }
  return out;
}

class AsmPane extends StatefulWidget {
  final StageAnalysis? analysis;
  final int cursorLine;
  final ValueChanged<int> onJump;
  const AsmPane(
      {super.key,
      required this.analysis,
      required this.cursorLine,
      required this.onJump});
  @override
  State<AsmPane> createState() => _AsmPaneState();
}

class _AsmPaneState extends State<AsmPane> {
  static const _rowH = 19.0;
  final _scroll = ScrollController();
  List<_Row> _cache = const [];
  CompiledStage? _for;

  List<_Row> get _list {
    final st = widget.analysis?.stage;
    if (st != _for) {
      _for = st;
      _cache = st == null ? const [] : _rows(st);
    }
    return _cache;
  }

  @override
  void didUpdateWidget(AsmPane old) {
    super.didUpdateWidget(old);
    if (old.cursorLine != widget.cursorLine) {
      final i = _list.indexWhere((r) => r.line == widget.cursorLine);
      if (i >= 0 && _scroll.hasClients) {
        final top = i * _rowH,
            view = _scroll.position.viewportDimension,
            at = _scroll.offset;
        if (top < at || top > at + view - 3 * _rowH) {
          _scroll.animateTo(
              (top - view / 3).clamp(0, _scroll.position.maxScrollExtent),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut);
        }
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static const _mono = TextStyle(
      fontFamily: Sc.mono,
      fontFamilyFallback: Sc.monoFallback,
      fontSize: 12.5,
      height: 1.0);

  TextSpan _code(String t, bool label) {
    if (label) {
      return TextSpan(text: t, style: _mono.copyWith(color: Sc.primary));
    }
    final sp = t.indexOf(' ');
    final op = sp < 0 ? t : t.substring(0, sp),
        args = sp < 0 ? '' : t.substring(sp);
    final kids = <TextSpan>[
      TextSpan(
          text: op.padRight(6),
          style: _mono.copyWith(color: op.startsWith('.') ? Sc.faint : Sc.gold))
    ];
    for (final m in RegExp(
            r'(%\w+)|(-?\b(?:0x[0-9a-fA-F]+|\d+)\b)|([A-Za-z_.][\w.]*)|([^%A-Za-z_.\d-]+|-)')
        .allMatches(args)) {
      final c = m.group(1) != null
          ? const Color(0xFF83A6C9)
          : m.group(2) != null
              ? const Color(0xFFE6A07A)
              : m.group(3) != null
                  ? Sc.primary
                  : Sc.caption;
      kids.add(TextSpan(text: m.group(0), style: _mono.copyWith(color: c)));
    }
    return TextSpan(children: kids);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.analysis,
        rows = _list,
        cyc = a?.pcCycles ?? const <int, double>{};
    final instructions = rows.where((r) => r.addr != null && !r.label).length;
    final routines = rows
        .where((r) =>
            r.label && r.text.startsWith('__') && !r.text.contains('_', 2))
        .map((r) => r.text.replaceAll(':', ''));
    return Container(
      color: Sc.inset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.black26))),
            child: Row(children: [
              Text('ASSEMBLY', style: Sc.caps(11, color: Sc.caption)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  a?.stage == null
                      ? ''
                      : '$instructions instructions${routines.isEmpty ? '' : ' · runtime ${routines.join(' ')}'}',
                  overflow: TextOverflow.ellipsis,
                  style: Sc.uiText(12, color: Sc.faint),
                ),
              ),
            ]),
          ),
          Expanded(
            child: a?.stage == null
                ? Center(
                    child: Text(
                        a == null
                            ? 'compiling…'
                            : 'fix the errors to see the code',
                        style: Sc.uiText(13, color: Sc.faint)))
                : Scrollbar(
                    controller: _scroll,
                    child: ListView.builder(
                      controller: _scroll,
                      itemExtent: _rowH,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final hot =
                            r.line != null && r.line == widget.cursorLine;
                        final c = r.addr == null ? null : cyc[r.addr];
                        return InkWell(
                          onTap: r.line == null
                              ? null
                              : () => widget.onJump(r.line!),
                          child: Container(
                            color: hot ? Sc.blue.withValues(alpha: 0.16) : null,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(children: [
                              SizedBox(
                                width: 30,
                                child: Text(r.line == null ? '' : '${r.line}',
                                    textAlign: TextAlign.right,
                                    style: _mono.copyWith(
                                        fontSize: 11,
                                        color: hot ? Sc.text : Sc.faint)),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 36,
                                child: Text(
                                    r.addr == null || r.label
                                        ? ''
                                        : (r.addr! & 0xffff)
                                            .toRadixString(16)
                                            .padLeft(4, '0'),
                                    style: _mono.copyWith(
                                        fontSize: 11,
                                        color: const Color(0xFF5E5E66))),
                              ),
                              SizedBox(
                                width: 40,
                                child: Text(
                                  r.label || r.addr == null
                                      ? ''
                                      : (c == null
                                          ? '·'
                                          : (c < 10
                                              ? c.toStringAsFixed(1)
                                              : c.toStringAsFixed(0))),
                                  textAlign: TextAlign.right,
                                  style: _mono.copyWith(
                                      fontSize: 11,
                                      color: c == null
                                          ? const Color(0xFF55555B)
                                          : costColor(c * 8)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: RichText(
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  text: TextSpan(children: [
                                    if (!r.label) const TextSpan(text: '  '),
                                    _code(r.text, r.label),
                                    if (r.comment.isNotEmpty)
                                      TextSpan(
                                          text: '  ${r.comment}',
                                          style:
                                              _mono.copyWith(color: Sc.faint)),
                                  ]),
                                ),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
