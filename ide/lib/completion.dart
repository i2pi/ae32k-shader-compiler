// Completions at the cursor, from context: after `in.` the stage's inputs, after `out.` its
// outputs (a scan stage's are its `@out` names), on an `@out` line register names then modes,
// elsewhere keywords, functions, constants, `in`/`out` and the locals declared so far.
import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';

import 'stage_io.dart';

enum CompletionKind {
  keyword,
  function,
  constant,
  local,
  input,
  output,
  register,
  mode
}

class Completion {
  final String label, insert, detail;
  final CompletionKind kind;

  /// Where the cursor goes inside [insert] (default: after it), e.g. inside `sin()`.
  final int? caret;
  const Completion(this.label, this.insert, this.detail, this.kind,
      [this.caret]);
}

class CompletionResult {
  /// The replaced text runs from [start] to the cursor.
  final int start;
  final List<Completion> items;
  const CompletionResult(this.start, this.items);
}

const _functions = {
  'sin': ('sin(x)', 'sine of x turns (1.0 = full circle)'),
  'cos': ('cos(x)', 'cosine of x turns'),
  'atan2': ('atan2(y, x)', 'angle of (x, y) in turns, -0.5..0.5'),
  'sqrt': ('sqrt(x)', 'square root, 0 for x <= 0'),
  'abs': ('abs(x)', 'absolute value'),
  'min': ('min(a, b)', 'smaller'),
  'max': ('max(a, b)', 'larger'),
  'clamp': ('clamp(x, lo, hi)', 'x limited to lo..hi'),
  'floor': ('floor(x)', 'largest whole number <= x'),
  'frac': ('frac(x)', 'x - floor(x), 0..1'),
  'lerp': ('lerp(a, b, t)', 'a + (b - a) * t'),
  'smoothstep': (
    'smoothstep(e0, e1, x)',
    '0..1 with a smooth ramp (~300 cycles)'
  ),
  'step': ('step(edge, x)', '0 below edge, else 1'),
  'sign': ('sign(x)', '-1, 0 or 1'),
  'mod': ('mod(a, b)', 'a - floor(a / b) * b'),
  'noise': ('noise(x, y)', 'value noise, 0..1'),
};

const _modes = {
  'raw': 'integer part into the field',
  'gain': 'x the field\'s value at map time (1.0 = unchanged)',
  'add': 'integer part added to that value',
  'unit': '0..1 onto the field\'s range',
  'strobe': 'write the constant after any change',
};

final _outLine = RegExp(r'^\s*@out\s+(\w+)(\s+)?(\S*)(\s+)?(\S*)$');
final _declName = RegExp(r'^\s*@out\s+(\w+)\s', multiLine: true);
final _let = RegExp(r'\blet\s+([A-Za-z_]\w*)');

CompletionResult? complete(String src, int cursor, int slot) {
  if (cursor < 0 || cursor > src.length) return null;
  final lineStart = src.lastIndexOf('\n', cursor - 1) + 1;
  final before = src.substring(lineStart, cursor);
  if (before.contains('//')) return null; // in a comment

  // an @out line: <output> <register> [mode]
  final o = _outLine.firstMatch(before);
  if (o != null && o.group(2) != null) {
    final field = o.group(4) == null ? 1 : 2;
    final prefix = field == 1 ? o.group(3)! : o.group(5)!;
    final start = cursor - prefix.length;
    if (field == 1) {
      final items = [
        for (final r in registers.values)
          if (r.name.startsWith(prefix))
            Completion(
                r.name,
                r.name,
                '${r.mode} · ${r.granularity} · ${r.description}',
                CompletionKind.register),
      ];
      return CompletionResult(start, items.take(40).toList());
    }
    return CompletionResult(start, [
      for (final e in _modes.entries)
        if (e.key.startsWith(prefix))
          Completion(e.key, e.key, e.value, CompletionKind.mode),
    ]);
  }

  // the identifier being typed, and what precedes it
  var s = cursor;
  while (s > lineStart && RegExp(r'[A-Za-z0-9_]').hasMatch(src[s - 1])) {
    s--;
  }
  final prefix = src.substring(s, cursor);
  if (prefix.isNotEmpty && RegExp(r'^\d').hasMatch(prefix)) {
    return null; // a number
  }

  if (s >= 1 && src[s - 1] == '.') {
    final head = src.substring(lineStart, s - 1);
    if (head.endsWith('in') && !RegExp(r'[A-Za-z0-9_]in$').hasMatch(head)) {
      return CompletionResult(s, [
        for (final i in stageInputs(slot))
          if (i.name.startsWith(prefix))
            Completion(i.name, i.name, i.meaning, CompletionKind.input),
      ]);
    }
    if (head.endsWith('out') && !RegExp(r'[A-Za-z0-9_]out$').hasMatch(head)) {
      final outs = slot == 1
          ? [
              for (final m in _declName.allMatches(src))
                StageItem(m.group(1)!, '@out')
            ]
              .fold(
                  <String, StageItem>{},
                  (Map<String, StageItem> acc, i) =>
                      acc..putIfAbsent(i.name, () => i))
              .values
              .toList()
          : stageOutputs(slot);
      return CompletionResult(s, [
        for (final i in outs)
          if (i.name.startsWith(prefix))
            Completion(i.name, i.name, i.meaning, CompletionKind.output),
      ]);
    }
    return null;
  }
  if (prefix.isEmpty) return null;

  final locals = {
    for (final m in _let.allMatches(src.substring(0, lineStart))) m.group(1)!
  };
  final items = <Completion>[
    for (final k in const ['let', 'if', 'else'])
      if (k.startsWith(prefix) && k != prefix)
        Completion(k, '$k ', 'keyword', CompletionKind.keyword),
    for (final k in const ['in', 'out'])
      if (k.startsWith(prefix) && k != prefix)
        Completion('$k.', '$k.', k == 'in' ? 'an input' : 'an output',
            CompletionKind.keyword),
    for (final l in locals)
      if (l.startsWith(prefix) && l != prefix)
        Completion(l, l, 'local', CompletionKind.local),
    for (final e in _functions.entries)
      if (e.key.startsWith(prefix))
        Completion(e.value.$1, '${e.key}()', e.value.$2,
            CompletionKind.function, e.key.length + 1),
    for (final c in const {
      'pi': '3.14159',
      'tau': '6.28319 (a full circle in radians)'
    }.entries)
      if (c.key.startsWith(prefix) && c.key != prefix)
        Completion(c.key, c.key, c.value, CompletionKind.constant),
  ];
  return CompletionResult(s, items);
}
