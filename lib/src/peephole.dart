// Register-copy removal over the generated stage assembly (before the runtime routines).
//
// The code generator moves values between its pool, the runtime's argument registers and
// scratch registers with `lea (%Ra,0),%Rb`; about a quarter of a stage body's cycles were such
// copies. With register liveness over the basic blocks this pass
//  - forwards copies: after b = a, later reads of b read a, until either is redefined;
//  - renames a temporary: t = ...; ...; d = t with t dead afterwards becomes d = ...; ...;
//  - drops copies (and ldi/lea) whose result is never read.
// It only rewrites register numbers and deletes instructions; flags are unaffected (LEA does
// not set them). Anything it does not understand is a barrier.

const _defOnly = {'ldi', 'lea', 'ld', 'ldb', 'ldbu', 'lds', 'ldsu', 'mfmh', 'mfml'};
const _useDef = {
  'add', 'adc', 'sub', 'sbc', 'and', 'or', 'xor', 'addq', 'asl', 'asr', 'lsr', 'ssl', 'mul', 'mulu',
  'neg', 'not', 'extb', 'exts', 'cvb', 'cvs', 'rol', 'ror',
};
const _useAll = {'cmp', 'cmpq', 'tst', 'st', 'stb', 'sts', 'mtmh', 'mtml'};
const _branches = {
  'jmp', 'jnv', 'jv', 'jp', 'jm', 'jnz', 'jz', 'jnc', 'jc', 'jgt', 'jlt', 'jge', 'jle', 'jhi', 'jls',
};
const _evenDst = {'mul', 'mulu'};
const _all = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15};
// runtime routines: arguments R8-R10, R14 = ctx; they clobber R8-R13
const _callUse = {8, 9, 10, 14}, _callDef = {8, 9, 10, 11, 12, 13};

final _reg = RegExp(r'%R(\d+)\b');

class _Ins {
  String? label; // a label line
  String m = '';
  List<String> ops = [];
  String comment = '';
  _Ins.label(this.label);
  _Ins(this.m, this.ops, this.comment);

  bool get isLabel => label != null;
  bool get isCall => m == 'jal';
  bool get isExit => m == 'jplr' || (m == 'pop' && ops.contains('%pc'));
  bool get isBranch => _branches.contains(m);
  bool get known =>
      isLabel || _defOnly.contains(m) || _useDef.contains(m) || _useAll.contains(m) || isBranch || isCall ||
      isExit || m == 'push' || m == 'pop' || m == 'nop';

  static Set<int> _regs(String op) => {for (final x in _reg.allMatches(op)) int.parse(x[1]!)};

  Set<int> get uses {
    if (isLabel || isBranch || m == 'nop' || m == 'pop' && !isExit) return {};
    if (isCall) return _callUse;
    if (isExit || !known) return _all;
    if (m == 'push') return {for (final o in ops) ..._regs(o)};
    if (_defOnly.contains(m)) return {for (final o in ops.take(ops.length - 1)) ..._regs(o)};
    return {for (final o in ops) ..._regs(o)}; // useDef and useAll read every operand
  }

  Set<int> get defs {
    if (isLabel || isBranch || m == 'nop' || m == 'push' || isExit) return {};
    if (isCall) return _callDef;
    if (!known) return _all;
    if (m == 'pop') return {for (final o in ops) ..._regs(o)};
    if (_useAll.contains(m)) return {};
    return _regs(ops.last); // defOnly and useDef write the last operand
  }

  /// Rewrites R[from] to R[to] in the read-only operands ([uses]) or everywhere ([all]).
  void rename(int from, int to, {required bool all}) {
    for (var k = 0; k < ops.length; k++) {
      final dst = k == ops.length - 1 && (_defOnly.contains(m) || _useDef.contains(m));
      if (dst && !all) continue;
      ops[k] = ops[k].replaceAllMapped(_reg, (x) => int.parse(x[1]!) == from ? '%R$to' : x[0]!);
    }
  }

  /// A plain register copy `lea (%Ra,0),%Rb`: (a, b).
  (int, int)? get move {
    if (m != 'lea' || ops.length != 2) return null;
    final s = RegExp(r'^\(%R(\d+),0\)$').firstMatch(ops[0]), d = RegExp(r'^%R(\d+)$').firstMatch(ops[1]);
    return s == null || d == null ? null : (int.parse(s[1]!), int.parse(d[1]!));
  }

  @override
  String toString() => isLabel ? '$label:' : '    $m${ops.isEmpty ? '' : ' ${ops.join(',')}'}$comment';
}

List<String> _split(String s) {
  final out = <String>[];
  var depth = 0, start = 0;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')') depth--;
    if (s[i] == ',' && depth == 0) {
      out.add(s.substring(start, i).trim());
      start = i + 1;
    }
  }
  if (s.trim().isNotEmpty) out.add(s.substring(start).trim());
  return out;
}

List<_Ins> _parse(String asm) {
  final out = <_Ins>[];
  for (final line in asm.split('\n')) {
    final c = line.indexOf('//');
    final code = (c >= 0 ? line.substring(0, c) : line).trimRight();
    final comment = c >= 0 ? '  ${line.substring(c).trim()}' : '';
    if (code.trim().isEmpty) continue;
    final l = RegExp(r'^(\S+):$').firstMatch(code.trim());
    if (l != null && !code.startsWith(' ')) {
      out.add(_Ins.label(l[1]));
      continue;
    }
    final t = code.trim();
    final sp = t.indexOf(' ');
    out.add(sp < 0 ? _Ins(t, [], comment) : _Ins(t.substring(0, sp), _split(t.substring(sp + 1)), comment));
  }
  return out;
}

/// Live registers after each instruction.
List<Set<int>> _liveOut(List<_Ins> code) {
  final labelAt = {for (var i = 0; i < code.length; i++) if (code[i].isLabel) code[i].label!: i};
  final n = code.length;
  final liveIn = List.generate(n + 1, (_) => <int>{});
  final liveOut = List.generate(n, (_) => <int>{});
  for (var changed = true; changed;) {
    changed = false;
    for (var i = n - 1; i >= 0; i--) {
      final c = code[i];
      final out = <int>{};
      if (c.isExit) {
        // nothing after
      } else if (c.isBranch) {
        final t = labelAt[c.ops.single];
        out.addAll(t == null ? _all : liveIn[t]);
        if (c.m != 'jmp') out.addAll(liveIn[i + 1]);
      } else {
        out.addAll(liveIn[i + 1]);
      }
      final inn = {...out.difference(c.defs), ...c.uses};
      if (out.length != liveOut[i].length || inn.length != liveIn[i].length) {
        liveOut[i] = out;
        liveIn[i] = inn;
        changed = true;
      }
    }
  }
  return liveOut;
}

bool _endsBlock(_Ins c) => c.isBranch || c.isExit || !c.known;

/// One rewrite; true if something changed.
bool _step(List<_Ins> code) {
  final live = _liveOut(code);
  for (var p = 0; p < code.length; p++) {
    final c = code[p];
    // dead copies and constants
    if ((c.m == 'lea' || c.m == 'ldi') && c.ops.isNotEmpty) {
      final d = _Ins._regs(c.ops.last);
      if (d.length == 1 && !c.ops.last.contains('SP') && !live[p].contains(d.single)) {
        code.removeAt(p);
        return true;
      }
    }
    final mv = c.move;
    if (mv == null) continue;
    final (a, b) = mv;
    if (a == b) {
      code.removeAt(p);
      return true;
    }
    // forward: later reads of b read a instead
    var changed = false;
    for (var j = p + 1; j < code.length; j++) {
      final x = code[j];
      if (x.isLabel || !x.known) break;
      if (x.isCall && (_callUse.contains(b) || _callDef.contains(a) || _callDef.contains(b))) break;
      if (x.m == 'push' || x.m == 'pop') break;
      final u = x.uses, d = x.defs;
      if (u.contains(b) && !d.contains(b)) {
        x.rename(b, a, all: false);
        changed = true;
      }
      if (d.contains(a) || d.contains(b) || _endsBlock(x)) break;
    }
    if (changed) return true;
    // backward: rename the temporary a to b over its range, when a dies here
    if (live[p].contains(a)) continue;
    int? start;
    for (var j = p - 1; j >= 0; j--) {
      final x = code[j];
      if (x.isLabel || _endsBlock(x) || x.m == 'push' || x.m == 'pop') break;
      if (x.isCall && (_callUse.contains(a) || _callDef.contains(a) || _callUse.contains(b) || _callDef.contains(b))) break;
      if (j < p - 1 && (x.uses.contains(b) || x.defs.contains(b))) break; // b must be free in the range
      if (x.defs.contains(a) && !x.uses.contains(a)) {
        if (x.uses.contains(b) && j < p - 1) break;
        start = j;
        break;
      }
      if (j == p - 1 && (x.uses.contains(b) || x.defs.contains(b))) break;
    }
    if (start == null) continue;
    if (b.isOdd && [for (var j = start; j < p; j++) code[j]].any((x) => _evenDst.contains(x.m) && x.defs.contains(a))) continue;
    for (var j = start; j < p; j++) {
      code[j].rename(a, b, all: true);
    }
    code.removeAt(p);
    return true;
  }
  return false;
}

/// Removes register copies from [asm] (one stage's code, no runtime routines).
String removeCopies(String asm) {
  final code = _parse(asm);
  for (var n = 0; n < 2000 && _step(code); n++) {}
  return '${code.join('\n')}\n';
}
