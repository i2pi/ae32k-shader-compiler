// What the current stage can read and write: the inputs the resident fills for this stage, and
// the outputs (warp dx/dy, vertex vx/vy/p0..p3, or the scan stage's own `@out` names with their
// registers). Entries the code uses are highlighted; clicking one inserts it at the cursor.
import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:flutter/material.dart';

import 'stage_io.dart';
import 'theme.dart';

class _Decl {
  final String output, target, mode, granularity;
  final int line;
  final bool known;
  const _Decl(this.output, this.target, this.mode, this.granularity, this.line,
      this.known);
}

final _outLine = RegExp(r'^\s*@out\s+(\w+)\s+(.*?)\s*;?\s*(//.*)?$');

/// The scan stage's `@out` lines, resolved against the compiled-in registers.inc.
List<_Decl> _decls(String src) {
  final out = <_Decl>[];
  final lines = src.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final m = _outLine.firstMatch(lines[i]);
    if (m == null) continue;
    final f =
        m.group(2)!.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (f.isEmpty) continue;
    if (f.length >= 4) {
      out.add(_Decl(m.group(1)!, 'reg ${f[0]} mask ${f[1]} >> ${f[2]}',
          f.length > 3 ? f[3] : '?', '', i + 1, true));
    } else {
      Register? r;
      try {
        r = lookupRegister(f[0]);
      } on FormatException {
        r = null;
      }
      out.add(_Decl(m.group(1)!, f[0], f.length > 1 ? f[1] : (r?.mode ?? '?'),
          r?.granularity ?? '', i + 1, r != null));
    }
  }
  return out;
}

/// Names after `in.` and `out.` in the code, and which outputs are assigned (`out.x =`).
(Set<String>, Set<String>, Set<String>) _usage(String src) {
  final ins = <String>{}, outs = <String>{}, written = <String>{};
  final hs = highlight(src);
  for (var i = 0; i < hs.length; i++) {
    final h = hs[i];
    final t = src.substring(h.start, h.end);
    if (h.kind == TokenKind.input) ins.add(t);
    if (h.kind == TokenKind.output &&
        h.start >= 4 &&
        src.substring(h.start - 4, h.start) == 'out.') {
      outs.add(t);
      final rest = src.substring(h.end).trimLeft();
      if (rest.startsWith('=') && !rest.startsWith('==')) written.add(t);
    }
  }
  return (ins, outs, written);
}

class IoPane extends StatelessWidget {
  final String source;
  final int slot;
  final ValueChanged<String> onInsert;
  final ValueChanged<int> onJump;
  const IoPane(
      {super.key,
      required this.source,
      required this.slot,
      required this.onInsert,
      required this.onJump});

  @override
  Widget build(BuildContext context) {
    final (ins, outs, written) = _usage(source);
    final decls = slot == 1 ? _decls(source) : const <_Decl>[];
    final declared = {for (final d in decls) d.output};
    final children = <Widget>[
      _header('OUTPUTS', 'out.'),
    ];
    if (slot == 1) {
      if (decls.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          child: Text(
              'A scan stage writes registers through @out lines, e.g.\n@out swap in_swap\n@out gy out0_csc_y0 gain',
              style: Sc.uiText(12, color: Sc.faint)),
        ));
      }
      // one row per output name; its register fields underneath
      for (final name in declared) {
        final ds = decls.where((d) => d.output == name).toList();
        final w = written.contains(name);
        children.add(_entry(
            'out.$name', w ? 'written' : 'declared, never written',
            used: w, warn: !w, onTap: () => onInsert('out.$name = ')));
        for (final d in ds) {
          children.add(InkWell(
            onTap: () => onJump(d.line),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 1, 10, 3),
              child: Row(children: [
                Expanded(
                  child: Text(d.target,
                      overflow: TextOverflow.ellipsis,
                      style: Sc.uiText(12,
                          color: d.known ? const Color(0xFF83A6C9) : Sc.red)),
                ),
                Text(
                    '${d.mode}${d.granularity.isEmpty ? '' : ' · ${d.granularity}'}',
                    style: Sc.uiText(11.5, color: Sc.caption)),
              ]),
            ),
          ));
        }
      }
      for (final n in written.where((n) => !declared.contains(n))) {
        children.add(_entry('out.$n', 'no @out line: drives no register',
            used: true, warn: true, onTap: () => onInsert('out.$n')));
      }
    } else {
      for (final o in stageOutputs(slot)) {
        children.add(_entry('out.${o.name}', o.meaning,
            used: written.contains(o.name),
            onTap: () => onInsert('out.${o.name} = ')));
      }
    }
    children.addAll([
      const SizedBox(height: 10),
      _header('INPUTS', 'in.'),
      for (final i in stageInputs(slot))
        _entry('in.${i.name}', i.meaning,
            used: ins.contains(i.name), onTap: () => onInsert('in.${i.name}')),
      // inputs the code uses that this stage does not fill
      for (final n
          in ins.where((n) => !stageInputs(slot).any((i) => i.name == n)))
        _entry('in.$n', 'not set for this stage (reads 0)',
            used: true, warn: true, onTap: () => onInsert('in.$n')),
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Text(
            'Highlighted: used by the code. Click to insert at the cursor.',
            style: Sc.uiText(11.5, color: Sc.faint)),
      ),
    ]);
    return Container(
      color: Sc.panel,
      child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children)),
    );
  }

  Widget _header(String title, String prefix) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Text(title, style: Sc.caps(11, color: Sc.caption)),
      );

  Widget _entry(String code, String meaning,
          {required bool used,
          bool warn = false,
          required VoidCallback onTap}) =>
      InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: used
                ? (warn ? Sc.amber : Sc.blue).withValues(alpha: 0.14)
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 74,
              child: Text(code,
                  style: TextStyle(
                      fontFamily: Sc.mono,
                      fontFamilyFallback: Sc.monoFallback,
                      fontSize: 12.5,
                      color: code.startsWith('in.')
                          ? const Color(0xFF83A6C9)
                          : Sc.primary,
                      fontWeight: used ? FontWeight.w700 : FontWeight.w400)),
            ),
            Expanded(
                child: Tooltip(
                    message: meaning,
                    waitDuration: const Duration(milliseconds: 600),
                    child: Text(meaning,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Sc.uiText(12,
                            color: warn
                                ? Sc.amber
                                : (used ? Sc.body : Sc.faint))))),
          ]),
        ),
      );
}
