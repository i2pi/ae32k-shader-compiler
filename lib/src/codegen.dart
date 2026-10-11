// Code generator: shader AST -> AE32000 assembly for one stage slot.
//
// Stage layout: `int stage(struct ctx *c)` at the slot base (R8 = ctx on entry, 0 in R8
// on return), followed by the runtime routines it uses (runtime.dart). Values live in
// a register pool (R0-R7, R11-R13); the first locals get pool registers as their homes,
// the rest stack slots. R14 holds ctx. Runtime calls take R8-R10 and preserve the pool,
// so nothing is saved around them. Only pool registers actually used are saved, plus R14
// and, when the runtime is called, R10 (callee-saved in the gcc ABI).
import 'dart:math';

import 'abi.dart';
import 'lang/ast.dart';
import 'lang/eval.dart' show evaluate;
import 'lang/q16.dart';
import 'runtime.dart';

class CompileError implements Exception {
  final String message;
  CompileError(this.message);
  @override
  String toString() => 'CompileError: $message';
}

const _pool = [0, 1, 2, 3, 4, 5, 6, 7, 11, 12, 13];

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

  /// [regLocals]: how many locals get a register home (the rest live on the stack).
  CodeGen(this.p, {int regLocals = 6}) {
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
    final lows = [for (final r in _used.where((r) => r < 8).toList()..sort()) '%R$r'];
    // R10 is callee-saved in the gcc ABI but the runtime's third argument register
    final highs = [for (final r in [..._used.where((r) => r > 8), if (_calls.isNotEmpty) 10, 14]..sort()) '%R$r'];
    final frame = 4 * _slots.length;
    final head = StringBuffer()
      ..writeln('stage:')
      ..writeln('    push %lr');
    if (lows.isNotEmpty) head.writeln('    push ${lows.join(',')}');
    head
      ..writeln('    push ${highs.join(',')}')
      ..writeln('    lea (%R8,0),%R14');
    if (frame > 0) head.writeln('    lea (%SP,${-frame}),%SP');
    for (final l in _homes.values) {
      head.writeln('    ldi 0,%R$l'); // C locals start at 0
    }
    for (final o in _slots.values) {
      head
        ..writeln('    ldi 0,%R8')
        ..writeln('    st %R8,(%SP,$o)');
    }
    final tail = StringBuffer();
    if (frame > 0) tail.writeln('    lea (%SP,$frame),%SP');
    tail
      ..writeln('    ldi 0,%R8')
      ..writeln('    pop ${highs.join(',')}');
    if (lows.isNotEmpty) tail.writeln('    pop ${lows.join(',')}');
    tail.writeln('    pop %pc');
    return '$head$_out$tail${runtimeFor(_calls)}';
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

  int _const(Expr e) => evaluate(Program([OutAssign(0, e)], const [], const [], const {}), const {})[0];

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
        return _runtime('__qmul', [l, r]);
      case '/':
        return _runtime('__qdiv', [l, r]);
      case '%':
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
