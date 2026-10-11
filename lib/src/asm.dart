// A small assembler over isa.dart: gas syntax plus labels, so the runtime and the code
// generator can be written as text. Branches are relaxed to their shortest encoding
// (sizes only grow between passes, so it converges).
//
//   name:                 label
//   .short a, b, ...      16-bit data      .word a, ...   32-bit data   .align 4
//   jz name / jal name    branch to a label
//   ldi name,%R3          a label's absolute address as an immediate
//   // comment
import 'isa.dart';

class AsmError implements Exception {
  final String message;
  AsmError(this.message);
  @override
  String toString() => 'AsmError: $message';
}

class Assembled {
  final List<int> bytes;
  final Map<String, int> labels; // absolute addresses
  const Assembled(this.bytes, this.labels);
}

class _Line {
  final String text;
  final int lineNo;
  _Line(this.text, this.lineNo);
  int words = 1; // current size estimate (instructions only)
}

final _labelRe = RegExp(r'^([A-Za-z_.$][\w.$]*):\s*(.*)$');
final _symRe = RegExp(r'[A-Za-z_.$][\w.$]*');

Assembled assemble(String source, int base) {
  final lines = <_Line>[];
  final src = source.split('\n');
  for (var n = 0; n < src.length; n++) {
    var t = src[n];
    final c = t.indexOf('//');
    if (c >= 0) t = t.substring(0, c);
    t = t.trim();
    while (true) {
      final m = _labelRe.firstMatch(t);
      if (m == null) break;
      lines.add(_Line('${m.group(1)}:', n + 1));
      t = m.group(2)!.trim();
    }
    if (t.isNotEmpty) lines.add(_Line(t, n + 1));
  }

  for (var pass = 0; pass < 50; pass++) {
    // lay out
    final labels = <String, int>{};
    var pc = base;
    for (final l in lines) {
      if (l.text.endsWith(':') && !l.text.contains(' ')) {
        final name = l.text.substring(0, l.text.length - 1);
        if (labels.containsKey(name)) throw AsmError('line ${l.lineNo}: duplicate label $name');
        labels[name] = pc;
      } else {
        pc = _advance(l, pc);
      }
    }
    // encode
    var grew = false;
    final out = <int>[];
    pc = base;
    for (final l in lines) {
      if (l.text.endsWith(':') && !l.text.contains(' ')) continue;
      if (l.text.startsWith('.')) {
        final bytes = _directive(l, pc, labels);
        out.addAll(bytes);
        pc += bytes.length;
        continue;
      }
      final List<int> words;
      try {
        words = encode(_parseWithLabels(l.text, labels), pc);
      } on EncodeError catch (e) {
        throw AsmError('line ${l.lineNo} "${l.text}": ${e.message}');
      } on FormatException catch (e) {
        throw AsmError('line ${l.lineNo} "${l.text}": ${e.message}');
      }
      if (words.length > l.words) {
        l.words = words.length;
        grew = true;
      }
      // pad to the reserved size (a branch that got shorter after growth elsewhere); the
      // NOP goes after it, so the instruction stays at the address it was encoded for
      while (words.length < l.words) {
        words.add(0xE0B0);
      }
      for (final w in words) {
        out
          ..add(w & 0xff)
          ..add(w >> 8);
      }
      pc += 2 * words.length;
    }
    if (!grew) return Assembled(out, labels);
  }
  throw AsmError('branch relaxation did not converge');
}

int _advance(_Line l, int pc) {
  if (!l.text.startsWith('.')) return pc + 2 * l.words;
  final (d, args) = _split(l.text);
  return switch (d) {
    '.short' => pc + 2 * args.length,
    '.word' => pc + 4 * args.length,
    '.align' => (pc + int.parse(args.single) - 1) ~/ int.parse(args.single) * int.parse(args.single),
    _ => throw AsmError('line ${l.lineNo}: unknown directive $d'),
  };
}

(String, List<String>) _split(String t) {
  final sp = t.indexOf(RegExp(r'\s'));
  if (sp < 0) return (t, const []);
  return (t.substring(0, sp), [for (final a in t.substring(sp).split(',')) a.trim()]);
}

List<int> _directive(_Line l, int pc, Map<String, int> labels) {
  final (d, args) = _split(l.text);
  int val(String a) => labels[a] ?? _num(a, l);
  switch (d) {
    case '.short':
      return [for (final a in args) ...[val(a) & 0xff, (val(a) >> 8) & 0xff]];
    case '.word':
      return [for (final a in args) for (var k = 0; k < 4; k++) (val(a) >> (8 * k)) & 0xff];
    case '.align':
      final n = int.parse(args.single);
      final pad = (n - pc % n) % n;
      return [for (var k = 0; k < pad; k += 2) ...[0xB0, 0xE0]].take(pad).toList();
  }
  throw AsmError('line ${l.lineNo}: unknown directive $d');
}

int _num(String a, _Line l) {
  final neg = a.startsWith('-');
  final t = neg ? a.substring(1) : a;
  final v = t.startsWith('0x') ? int.tryParse(t.substring(2), radix: 16) : int.tryParse(t);
  if (v == null) throw AsmError('line ${l.lineNo}: unknown symbol or number "$a"');
  return neg ? -v : v;
}

/// Replaces label names in the operands by their addresses, then parses.
Insn _parseWithLabels(String text, Map<String, int> labels) {
  final sp = text.indexOf(RegExp(r'\s'));
  if (sp < 0) return parse(text);
  final m = text.substring(0, sp);
  final ops = text.substring(sp).replaceAllMapped(_symRe, (x) {
    final s = x.group(0)!;
    if (labels.containsKey(s)) return '${labels[s]}';
    if (branches.contains(m) && s != '.' && !s.startsWith('x')) throw FormatException('unknown label $s');
    return s;
  });
  return parse('$m$ops');
}
