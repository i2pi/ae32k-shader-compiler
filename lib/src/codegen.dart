// Code generator: shader AST -> AE32000 assembly for one stage slot.
//
// Stage layout: `int stage(struct ctx *c)` at the slot base (R8 = ctx on entry, 0 in R8
// on return), followed by the runtime routines it uses (runtime.dart). Values live in
// a register pool (R0-R7); the first locals get pool registers as their homes, the rest
// stack slots. R14 holds ctx. Runtime calls and inline sequences use R8-R13 and preserve
// the pool, so nothing is saved around them. The prologue saves the pool registers
// actually used, R14, and R10-R13 when they are touched (callee-saved in the gcc ABI).
import 'dart:math';

import 'abi.dart';
import 'lang/ast.dart';
import 'lang/eval.dart' show evaluate;
import 'lang/q16.dart';
import 'peephole.dart';
import 'ranges.dart';
import 'runtime.dart';

class CompileError implements Exception {
  final String message;
  CompileError(this.message);
  @override
  String toString() => 'CompileError: $message';
}

const _pool = [0, 1, 2, 3, 4, 5, 6, 7]; // R8-R13 are argument/scratch registers

/// A value in a register; [temp] values may be overwritten, local homes may not.
class _V {
  final int r;
  final bool temp;
  const _V(this.r, this.temp);
}

class CodeGen {
  final Program p;
  final _out = StringBuffer();
  final _free = <int>[..._pool];
  final _used = <int>{};
  final _homes = <String, int>{}; // local -> register
  final _slots = <String, int>{}; // local -> stack offset
  final _calls = <String>{};
  var _label = 0;

  /// Fast mode: no saturation on q_mul / q_div and no zero-divisor test; results match
  /// the reference evaluated with `fast: true` (lang/q16.dart qFast).
  final bool fast;

  late final Map<String, Range?> _ranges = localRanges(p);
  Range? _range(Expr e) => rangeOf(_fold(e), _ranges);

  /// [regLocals]: how many locals get a register home (the rest live on the stack).
  /// [copies]: keep the register copies (skip lib/src/peephole.dart), for comparison.
  final bool copies;

  CodeGen(this.p, {int regLocals = 6, this.fast = false, this.copies = false}) {
    for (final l in p.locals) {
      if (_homes.length < regLocals) {
        _homes[l] = _alloc();
      } else {
        _slots[l] = 4 * _slots.length;
      }
    }
  }

  /// The stage's assembly, runtime included.
  String generate() {
    for (final s in p.body) {
      _stmt(s);
    }
    // The body (locals start at 0, as in C), with copies removed; then the prologue and
    // epilogue save exactly what the final body touches: R10-R13 whenever it calls the runtime
    // (which clobbers them), %lr only when it calls, and R14 only when it needs the ctx
    // pointer to outlive R8 (a call, or R8 used for anything else).
    final body = StringBuffer();
    for (final l in _homes.values) {
      body.writeln('    ldi 0,%R$l');
    }
    for (final o in _slots.values) {
      body
        ..writeln('    ldi 0,%R9')
        ..writeln('    st %R9,(%SP,$o)');
    }
    body.write(_out);
    // the body runs from `R14 = ctx` to an exit that reads only R8 (the epilogue restores the rest)
    var code = '    lea (%R8,0),%R14\n$body    ldi 0,%R8\n    jplr\n';
    if (!copies) code = removeCopies(code, exitLive: {8});
    code = code.substring(0, code.lastIndexOf('    jplr'));
    code = code.replaceFirst('    lea (%R8,0),%R14\n', '');
    final calls = RegExp(r'^\s+jal ', multiLine: true).hasMatch(code);
    // without calls, and with R8 written only by the final ldi 0, R8 still holds ctx at every
    // read: use it and leave R14 alone
    final r8Free = !calls && !regsWritten(code.substring(0, code.lastIndexOf('    ldi 0,%R8'))).contains(8);
    final ctx = r8Free && !copies ? 8 : 14;
    if (ctx == 8) code = code.replaceAll('%R14', '%R8');
    // runtime routines read ctx through R14 (the sine table), so a call keeps it
    final refs = {for (final m in RegExp(r'%R(\d+)\b').allMatches(code)) int.parse(m[1]!), if (calls) 14};
    final saved = [
      for (final r in [0, 1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14])
        if ((refs.contains(r) && (r != 14 || ctx == 14)) || (calls && r >= 10 && r <= 13)) r,
    ];
    final frame = 4 * _slots.length;
    final head = StringBuffer('stage:\n');
    if (calls) head.writeln('    push %lr');
    final lows = [for (final r in saved) if (r < 8) '%R$r'], highs = [for (final r in saved) if (r >= 8) '%R$r'];
    if (lows.isNotEmpty) head.writeln('    push ${lows.join(',')}');
    if (highs.isNotEmpty) head.writeln('    push ${highs.join(',')}');
    if (refs.contains(14)) head.writeln('    lea (%R8,0),%R14');
    if (frame > 0) head.writeln('    lea (%SP,${-frame}),%SP');
    final tail = StringBuffer();
    if (frame > 0) tail.writeln('    lea (%SP,$frame),%SP');
    if (highs.isNotEmpty) tail.writeln('    pop ${highs.join(',')}');
    if (lows.isNotEmpty) tail.writeln('    pop ${lows.join(',')}');
    tail.writeln(calls ? '    pop %pc' : '    jplr');
    return '$head$code$tail${runtimeFor(_calls, fast: fast)}';
  }

  void _e(String s) => _out.writeln('    $s');
  String _newLabel() => '.L${_label++}';

  int _alloc() {
    if (_free.isEmpty) throw CompileError('expression needs more than ${_pool.length} registers');
    final r = _free.removeAt(0);
    _used.add(r);
    return r;
  }

  void _release(_V v) {
    if (v.temp) _free.insert(0, v.r);
  }

  /// [v] in a register that may be modified.
  _V _own(_V v) {
    if (v.temp) return v;
    final t = _alloc();
    _e('lea (%R${v.r},0),%R$t');
    return _V(t, true);
  }

  // ---------------------------------------------------------------- statements

  void _stmt(Stmt s) {
    switch (s) {
      case Assign(:final name, :final e):
        final v = _expr(e);
        if (_homes.containsKey(name)) {
          if (v.r != _homes[name]) _e('lea (%R${v.r},0),%R${_homes[name]}');
        } else {
          _e('st %R${v.r},(%SP,${_slots[name]})');
        }
        _release(v);
      case OutAssign(:final slot, :final e):
        final v = _expr(e);
        _e('st %R${v.r},(%R14,${ctxOut + 4 * slot})');
        _release(v);
      case If(:final cond, :final then, :final otherwise):
        final lElse = _newLabel(), lEnd = _newLabel();
        _branchIfFalse(cond, lElse);
        for (final t in then) {
          _stmt(t);
        }
        if (otherwise.isNotEmpty) _e('jmp $lEnd');
        _out.writeln('$lElse:');
        for (final t in otherwise) {
          _stmt(t);
        }
        if (otherwise.isNotEmpty) _out.writeln('$lEnd:');
    }
  }

  static const _cmpNot = {'<': 'jge', '<=': 'jgt', '>': 'jle', '>=': 'jlt', '==': 'jnz', '!=': 'jz'};

  void _branchIfFalse(Expr c, String target) {
    final f = _fold(c);
    if (f is Num) {
      if (f.q == 0) _e('jmp $target');
      return;
    }
    if (f is Binary && _cmpNot.containsKey(f.op)) {
      final [a, b] = _exprs([f.l, f.r]);
      _e('cmp %R${b.r},%R${a.r}');
      _release(b);
      _release(a);
      _e('${_cmpNot[f.op]} $target');
      return;
    }
    final v = _expr(f);
    _e('cmpq 0,%R${v.r}');
    _release(v);
    _e('jz $target');
  }

  // ---------------------------------------------------------------- expressions

  /// Folds constant subtrees with the reference semantics (bit-exact by construction).
  Expr _fold(Expr e) {
    switch (e) {
      case Unary(:final op, :final e):
        final x = _fold(e);
        return x is Num ? Num(_const(Unary(op, x))) : Unary(op, x);
      case Binary(:final op, :final l, :final r):
        final a = _fold(l), b = _fold(r);
        return a is Num && b is Num ? Num(_const(Binary(op, a, b))) : Binary(op, a, b);
      case Call(:final fn, :final args):
        final xs = [for (final a in args) _fold(a)];
        return xs.every((x) => x is Num) ? Num(_const(Call(fn, xs))) : Call(fn, xs);
      default:
        return e;
    }
  }

  int _const(Expr e) => evaluate(Program([OutAssign(0, e)], const [], const [], const {}), const {}, null, fast)[0];

  /// Registers needed to evaluate [e] (Sethi-Ullman), so the hungrier operand goes first.
  int _need(Expr e) => switch (e) {
        Num() || In() || OutRead() || Local() => 1,
        Unary(:final e) => _need(e),
        Binary(:final op, :final l, :final r) when op == '&&' || op == '||' => max(_need(l), _need(r)) + 1,
        Binary(:final l, :final r) => _pair(_need(l), _need(r)),
        Call(:final args) => _many([for (final a in args) _need(a)]),
      };

  static int _pair(int a, int b) => a == b ? a + 1 : max(a, b);

  static int _many(List<int> needs) {
    final s = [...needs]..sort((a, b) => b.compareTo(a));
    var m = 0;
    for (var i = 0; i < s.length; i++) {
      m = max(m, s[i] + i);
    }
    return m;
  }

  /// Evaluates [es] hungriest first; results in the original order.
  List<_V> _exprs(List<Expr> es) {
    final order = [for (var i = 0; i < es.length; i++) i]..sort((a, b) => _need(es[b]).compareTo(_need(es[a])));
    final out = List<_V?>.filled(es.length, null);
    for (final i in order) {
      out[i] = _expr(es[i]);
    }
    return out.cast<_V>();
  }

  _V _expr(Expr e) {
    e = _fold(e);
    switch (e) {
      case Num(:final q):
        final t = _alloc();
        _e('ldi $q,%R$t');
        return _V(t, true);
      case In(:final name):
        final t = _alloc();
        _e('ld (%R14,${ctxInput[name]}),%R$t');
        return _V(t, true);
      case OutRead(:final slot):
        final t = _alloc();
        _e('ld (%R14,${ctxOut + 4 * slot}),%R$t');
        return _V(t, true);
      case Local(:final name):
        if (_homes.containsKey(name)) return _V(_homes[name]!, false);
        final t = _alloc();
        _e('ld (%SP,${_slots[name]}),%R$t');
        return _V(t, true);
      case Unary(op: '-', :final e):
        final v = _own(_expr(e));
        _e('neg %R${v.r}');
        return v;
      case Unary(:final e):
        return _truth(_expr(e), negate: true);
      case Binary(:final op, :final l, :final r):
        return _binary(op, l, r);
      case Call(:final fn, :final args):
        return _call(fn, args);
    }
  }

  /// 1.0 when [v] is non-zero (or zero, with [negate]), else 0.
  _V _truth(_V v, {bool negate = false}) {
    final t = _own(v);
    final l = _newLabel();
    _e('cmpq 0,%R${t.r}');
    _e('ldi 0,%R${t.r}');
    _e('${negate ? 'jnz' : 'jz'} $l');
    _e('ldi $q1,%R${t.r}');
    _out.writeln('$l:');
    return t;
  }

  _V _binary(String op, Expr l, Expr r) {
    switch (op) {
      case '+' || '-':
        final [la, b] = _exprs([l, r]);
        final a = _own(la);
        _e('${op == '+' ? 'add' : 'sub'} %R${b.r},%R${a.r}');
        _release(b);
        return a;
      case '*':
        final a = _fold(l), b = _fold(r);
        if (a is Num && b is! Num) return _mulConst(b, a.q);
        if (b is Num && a is! Num) return _mulConst(a, b.q);
        final ra = _range(a), rb = _range(b);
        if (rb != null && rb.within(-q1, q1)) return _mulSmall(a, b, rb, ra);
        if (ra != null && ra.within(-q1, q1)) return _mulSmall(b, a, ra, rb);
        return _runtime('__qmul', [l, r]);
      case '/':
        final d = _fold(r);
        if (d is Num && _pow2(d.q)) {
          final v = _own(_expr(l));
          _divPow2Reg(v.r, d.q, _range(l));
          return v;
        }
        return _runtime('__qdiv', [l, r]);
      case '%':
        final d = _fold(r);
        if (d is Num && _pow2(d.q)) {
          // a - q_mul(floor(q_div(a, c)), c), all inline
          final v = _own(_expr(l));
          final t = _alloc();
          _e('lea (%R${v.r},0),%R$t');
          _divPow2Reg(t, d.q);
          _e('and -65536,%R$t');
          _mulConstReg(t, d.q);
          _e('sub %R$t,%R${v.r}');
          _free.insert(0, t);
          return v;
        }
        return _runtime('__qmod', [l, r]);
      case '&&' || '||':
        final and = op == '&&';
        final t = _alloc();
        final done = _newLabel();
        _e('ldi ${and ? 0 : q1},%R$t');
        for (final side in [l, r]) {
          final v = _expr(side);
          _e('cmpq 0,%R${v.r}');
          _release(v);
          _e('${and ? 'jz' : 'jnz'} $done');
        }
        _e('ldi ${and ? q1 : 0},%R$t');
        _out.writeln('$done:');
        return _V(t, true);
      default: // comparisons
        final [a, b] = _exprs([l, r]);
        _e('cmp %R${b.r},%R${a.r}');
        _release(b);
        _release(a);
        final t = _alloc();
        final skip = _newLabel();
        _e('ldi 0,%R$t'); // LDI leaves the flags alone
        _e('${_cmpNot[op]} $skip');
        _e('ldi $q1,%R$t');
        _out.writeln('$skip:');
        return _V(t, true);
    }
  }

  static const _runtimeFn = {
    'sin': '__qsin', 'cos': '__qcos', 'sqrt': '__qsqrt', 'atan2': '__qatan2', 'mod': '__qmod',
    'smoothstep': '__qsmooth', 'noise': '__qnoise',
  };

  _V _call(String fn, List<Expr> args) {
    if (fn == 'mod') return _expr(Binary('%', args[0], args[1])); // same q_mod; inline for 2^m
    if (_runtimeFn.containsKey(fn)) return _runtime(_runtimeFn[fn]!, args);
    switch (fn) {
      case 'abs':
        final v = _own(_expr(args[0]));
        final l = _newLabel();
        _e('cmpq 0,%R${v.r}');
        _e('jge $l');
        _e('neg %R${v.r}');
        _out.writeln('$l:');
        return v;
      case 'min' || 'max':
        // a < b ? a : b  /  a > b ? a : b
        final [aa, b] = _exprs(args);
        final a = _own(aa);
        final l = _newLabel();
        _e('cmp %R${b.r},%R${a.r}');
        _e('${fn == 'min' ? 'jlt' : 'jgt'} $l');
        _e('lea (%R${b.r},0),%R${a.r}');
        _out.writeln('$l:');
        _release(b);
        return a;
      case 'clamp':
        // x < lo ? lo : (x > hi ? hi : x)
        final [xx, lo, hi] = _exprs(args);
        final x = _own(xx);
        final lHi = _newLabel(), lEnd = _newLabel();
        _e('cmp %R${lo.r},%R${x.r}');
        _e('jge $lHi');
        _e('lea (%R${lo.r},0),%R${x.r}');
        _e('jmp $lEnd');
        _out.writeln('$lHi:');
        _e('cmp %R${hi.r},%R${x.r}');
        _e('jle $lEnd');
        _e('lea (%R${hi.r},0),%R${x.r}');
        _out.writeln('$lEnd:');
        _release(hi);
        _release(lo);
        return x;
      case 'floor' || 'frac':
        final v = _own(_expr(args[0]));
        _e('and ${fn == 'floor' ? -65536 : 65535},%R${v.r}');
        return v;
      case 'step':
        // x < e ? 0 : 1
        final [e, x] = _exprs(args);
        _e('cmp %R${e.r},%R${x.r}');
        _release(x);
        _release(e);
        final t = _alloc();
        final l = _newLabel();
        _e('ldi 0,%R$t');
        _e('jlt $l');
        _e('ldi $q1,%R$t');
        _out.writeln('$l:');
        return _V(t, true);
      case 'sign':
        final v = _expr(args[0]);
        final t = _alloc();
        final lEnd = _newLabel();
        _e('ldi $q1,%R$t');
        _e('cmpq 0,%R${v.r}');
        _e('jgt $lEnd');
        _e('ldi 0,%R$t');
        _e('jz $lEnd');
        _e('ldi ${-q1},%R$t');
        _out.writeln('$lEnd:');
        _release(v);
        return _V(t, true);
      case 'lerp':
        // a + q_mul(b - a, t)
        return _expr(Binary('+', args[0], Binary('*', Binary('-', args[1], args[0]), args[2])));
    }
    throw CompileError('unknown function $fn');
  }

  /// q_mul(x, c) inline for a constant c (q_mul is symmetric). Bit-exact with the C:
  /// sign-magnitude product of the 16-bit halves, truncated, saturating ([fast]: wrapping).
  _V _mulConst(Expr x, int c) {
    final v = _own(_expr(x));
    _mulConstReg(v.r, c, _range(x));
    return v;
  }

  /// R[r] = q_mul(R[r], c), where R[r] is known to lie in [xr] (null: anything). The sign
  /// handling goes when x >= 0, the saturation tests when |x|*|c| stays inside 32 bits.
  /// Uses R9-R12.
  void _mulConstReg(int r, int c, [Range? xr]) {
    final mag = c < 0 ? (-c) & 0xffffffff : c;
    final ch = mag >> 16, cl = mag & 0xffff;
    if (mag == 0) {
      _e('ldi 0,%R$r');
      return;
    }
    final nonNeg = xr != null && xr.nonNeg;
    // |c| < 1.0: ah*cl + (al*cl >> 16) <= 2^31 * 65535/65536 < 2^31, so it never saturates
    final noSat = fast || ch == 0 || (xr != null && xr.mag * mag < (0x7fffffff - (1 << 17)) * 65536);
    if (noSat && cl == 0) {
      // without saturation, q_mul by a whole number is the (wrapping) product
      final d = r.isEven ? r : 10;
      if (d != r) _e('lea (%R$r,0),%R$d');
      _e('mul ${c ~/ 65536},%R$d');
      if (d != r) _e('lea (%R$d,0),%R$r');
      return;
    }
    final lAbs = _newLabel(), lSat = _newLabel(), lSign = _newLabel(), lDone = _newLabel();
    if (!nonNeg) {
      _e('lea (%R$r,0),%R9'); // x, for the sign
      _e('cmpq 0,%R$r');
      _e('jge $lAbs');
      _e('neg %R$r');
      _out.writeln('$lAbs:');
    }
    if (ch == 0) {
      // ah*cl + (al*cl >> 16)
      _e('lea (%R$r,0),%R10');
      _e('lsr 16,%R10');
      _e('mul $cl,%R10');
      _e('lea (%R$r,0),%R12');
      _e('and 65535,%R12');
      _e('mul $cl,%R12');
      _e('lsr 16,%R12');
      _e('add %R12,%R10');
    } else {
      // hi = ah*ch >= 0x7fff saturates; else (hi << 16) + ah*cl + al*ch + (al*cl >> 16)
      // mod 2^32, as the C. With cl == 0 that is |x|*ch; otherwise ah*|c| + al*ch + ...
      final t = (0x7fff + ch - 1) ~/ ch;
      _e('lea (%R$r,0),%R10');
      _e('lsr 16,%R10');
      if (!noSat) {
        _e('cmp $t,%R10');
        _e('jnc $lSat');
      }
      if (cl == 0) {
        _e('lea (%R$r,0),%R10');
        _e('mul $ch,%R10');
      } else {
        _e('ldi $mag,%R11');
        _e('mul %R11,%R10'); // ah*|c| = (ah*ch << 16) + ah*cl
        _e('lea (%R$r,0),%R12');
        _e('and 65535,%R12');
        _e('mul $cl,%R12');
        _e('lsr 16,%R12');
        _e('add %R12,%R10'); // + al*cl >> 16
        _e('lea (%R$r,0),%R12');
        _e('and 65535,%R12');
        _e('mul $ch,%R12');
        _e('add %R12,%R10'); // + al*ch
      }
    }
    if (!noSat) {
      // r >= 0x7fffffff (unsigned) clamps to 0x7fffffff; only r >= 2^31 changes anything
      _e('cmpq 0,%R10');
      _e('jge $lSign');
      _out.writeln('$lSat:');
      _e('ldi 2147483647,%R10');
    }
    _out.writeln('$lSign:');
    if (!nonNeg) {
      _e('cmpq 0,%R9');
      _e('${c < 0 ? 'jlt' : 'jge'} $lDone');
      _e('neg %R10');
    } else if (c < 0) {
      _e('neg %R10');
    }
    _out.writeln('$lDone:');
    _e('lea (%R10,0),%R$r');
  }

  /// q_mul(x, f) inline for |f| <= 1.0 (f in [fr], x in [xr] or anything): bh is 0, or 1 with
  /// bl == 0, so the product is ah*|f| + (al*|f| >> 16); it saturates only for |f| == 1.0
  /// and |x| >= 0x7fff0000. Uses R9-R12.
  _V _mulSmall(Expr x, Expr f, Range fr, Range? xr) {
    final ab = _exprs([x, f]);
    final v = _own(ab[0]), w = _own(ab[1]);
    final xNon = xr != null && xr.nonNeg, fNon = fr.nonNeg;
    if (!(xNon && fNon)) {
      _e('lea (%R${v.r},0),%R9');
      _e('xor %R${w.r},%R9'); // the sign of the result in bit 31
    }
    if (!xNon) {
      final l = _newLabel();
      _e('cmpq 0,%R${v.r}');
      _e('jge $l');
      _e('neg %R${v.r}');
      _out.writeln('$l:');
    }
    if (!fNon) {
      final l = _newLabel();
      _e('cmpq 0,%R${w.r}');
      _e('jge $l');
      _e('neg %R${w.r}');
      _out.writeln('$l:');
    }
    _e('lea (%R${v.r},0),%R10');
    _e('lsr 16,%R10');
    _e('mul %R${w.r},%R10'); // ah*|f|
    _e('lea (%R${v.r},0),%R12');
    _e('and 65535,%R12');
    _e('mul %R${w.r},%R12');
    _e('lsr 16,%R12');
    _e('add %R12,%R10'); // + al*|f| >> 16
    if (!fast && fr.mag >= q1 && (xr == null || xr.mag >= 0x7fff0000)) {
      final l = _newLabel();
      _e('ldi 2147418112,%R11'); // 0x7fff0000
      _e('cmp %R11,%R10');
      _e('jc $l');
      _e('cmp 65536,%R${w.r}');
      _e('jnz $l');
      _e('ldi 2147483647,%R10'); // |f| == 1.0 and ah >= 0x7fff: saturated
      _out.writeln('$l:');
    }
    if (!(xNon && fNon)) {
      final l = _newLabel();
      _e('cmpq 0,%R9');
      _e('jge $l');
      _e('neg %R10');
      _out.writeln('$l:');
    }
    _e('lea (%R10,0),%R${v.r}');
    _release(w);
    return v;
  }

  /// R[r] = q_div(R[r], c) for c = +-2^m: a shift of |x|, saturating at 0x7fffffff
  /// when the quotient reaches 2^31. Uses R9, R10.
  void _divPow2Reg(int r, int c, [Range? xr]) {
    final mag = c < 0 ? (-c) & 0xffffffff : c;
    final m = mag.bitLength - 1;
    if (m > 16) {
      // trunc(x / 2^k) = (x + (x < 0 ? 2^k - 1 : 0)) >> k (arithmetic), also for x = -2^31
      final k = m - 16;
      if (!(xr?.nonNeg ?? false)) {
        _e('lea (%R$r,0),%R9');
        _e('asr 31,%R9');
        _e('lsr ${32 - k},%R9');
        _e('add %R9,%R$r');
      }
      _e('asr $k,%R$r');
      if (c < 0) _e('neg %R$r');
      return;
    }
    final lAbs = _newLabel(), lSign = _newLabel(), lDone = _newLabel();
    _e('lea (%R$r,0),%R9'); // x, for the sign
    _e('cmpq 0,%R$r');
    _e('jge $lAbs');
    _e('neg %R$r');
    _out.writeln('$lAbs:');
    {
      // |x| << (16 - m) >= 2^31 saturates: |x| >> (15 + m) != 0 (kept in fast mode: the
      // q_div routine needs its saturation test to terminate, so fast q_div saturates too)
      final lOk = _newLabel();
      _e('lea (%R$r,0),%R10');
      _e('lsr ${15 + m},%R10');
      _e('cmpq 0,%R10');
      _e('jz $lOk');
      _e('ldi 2147483647,%R$r');
      _e('jmp $lSign');
      _out.writeln('$lOk:');
      if (m < 16) _e('asl ${16 - m},%R$r');
    }
    _out.writeln('$lSign:');
    _e('cmpq 0,%R9');
    _e('${c < 0 ? 'jlt' : 'jge'} $lDone');
    _e('neg %R$r');
    _out.writeln('$lDone:');
  }

  static bool _pow2(int c) {
    final mag = c < 0 ? (-c) & 0xffffffff : c;
    return mag != 0 && mag & (mag - 1) == 0;
  }

  /// Calls a runtime routine: arguments to R8.., result from R8 into a new temp.
  _V _runtime(String routine, List<Expr> args) {
    _calls.add(routine);
    final vs = _exprs(args);
    for (var k = 0; k < vs.length; k++) {
      _e('lea (%R${vs[k].r},0),%R${8 + k}');
    }
    for (final v in vs.reversed) {
      _release(v);
    }
    _e('jal $routine');
    final t = _alloc();
    _e('lea (%R8,0),%R$t');
    return _V(t, true);
  }
}
