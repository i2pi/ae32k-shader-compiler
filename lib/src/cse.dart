// Common subexpressions: a pure expression that appears more than once is computed once into a
// fresh local, assigned just before the first top-level statement that uses it. Pure: built from
// constants, inputs and locals that are assigned exactly once, at the top level, before that
// point (so every occurrence sees the same values); output read-backs are left alone. Before
// matching, cos(x) becomes sin(x + 0.25) and constants in sums are gathered (both exact: the
// reference defines cos that way, and + wraps), so e.g. cos(a) and sin(a + 0.25) share a call.
import 'lang/ast.dart';
import 'lang/eval.dart' show evaluate;
import 'lang/q16.dart';

Program eliminateCommon(Program p, {bool fast = false}) {
  final assigns = <String, int>{};
  void count(List<Stmt> ss) {
    for (final s in ss) {
      switch (s) {
        case Assign(:final name):
          assigns[name] = (assigns[name] ?? 0) + 1;
        case If(:final then, :final otherwise):
          count(then);
          count(otherwise);
        case OutAssign():
      }
    }
  }

  count(p.body);
  // where each single top-level assignment happens
  final defAt = <String, int>{};
  for (var i = 0; i < p.body.length; i++) {
    final s = p.body[i];
    if (s is Assign && assigns[s.name] == 1) defAt[s.name] = i;
  }

  int fold(Expr e) => evaluate(Program([OutAssign(0, e)], const [], const [], const {}), const {}, null, fast)[0];

  // canonical form
  Expr canon(Expr e) {
    switch (e) {
      case Call(fn: 'cos', :final args):
        return canon(Call('sin', [Binary('+', args[0], const Num(q1 ~/ 4))]));
      case Call(:final fn, :final args):
        final xs = [for (final a in args) canon(a)];
        return xs.every((x) => x is Num) ? Num(fold(Call(fn, xs))) : Call(fn, xs);
      case Unary(:final op, :final e):
        final x = canon(e);
        return x is Num ? Num(fold(Unary(op, x))) : Unary(op, x);
      case Binary(op: '+' || '-', :final l, :final r):
        // a +- c gathered: (x + c1) + c2 -> x + (c1 + c2); a lone constant goes on the right
        final a = canon(l), b = canon(r);
        if (a is Num && b is Num) return Num(fold(Binary(e.op, a, b)));
        int? c;
        Expr x;
        if (b is Num) {
          c = e.op == '+' ? b.q : i32(-b.q);
          x = a;
        } else if (a is Num && e.op == '+') {
          c = a.q;
          x = b;
        } else {
          return Binary(e.op, a, b);
        }
        if (x is Binary && x.op == '+' && x.r is Num) {
          c = i32(c + (x.r as Num).q);
          x = x.l;
        }
        return c == 0 ? x : Binary('+', x, Num(c));
      case Binary(:final op, :final l, :final r):
        final a = canon(l), b = canon(r);
        return a is Num && b is Num ? Num(fold(Binary(op, a, b))) : Binary(op, a, b);
      default:
        return e;
    }
  }

  String key(Expr e) => switch (e) {
        Num(:final q) => '#$q',
        In(:final name) => 'in.$name',
        OutRead(:final slot) => 'out$slot',
        Local(:final name) => name,
        Unary(:final op, :final e) => '($op${key(e)})',
        Binary(:final op, :final l, :final r) => '(${key(l)}$op${key(r)})',
        Call(:final fn, :final args) => '$fn(${args.map(key).join(',')})',
      };

  // worth a local: a call, a multiply or divide, or a few operations
  int size(Expr e) => switch (e) {
        Num() || In() || OutRead() || Local() => 0,
        Unary(:final e) => 1 + size(e),
        Binary(:final l, :final r) => 1 + size(l) + size(r),
        Call(:final args) => 1 + args.fold(0, (s, a) => s + size(a)),
      };
  bool heavy(Expr e) => switch (e) {
        Call() => true,
        Binary(op: '*' || '/' || '%', :final l, :final r) => !(l is Num || r is Num) || size(e) >= 2,
        _ => size(e) >= 3,
      };

  /// Latest top-level statement index defining a local [e] reads, or null if [e] is impure.
  int? ready(Expr e) {
    switch (e) {
      case Num() || In():
        return -1;
      case OutRead():
        return null;
      case Local(:final name):
        return defAt[name];
      case Unary(:final e):
        return ready(e);
      case Binary(:final l, :final r):
        final a = ready(l), b = ready(r);
        return a == null || b == null ? null : (a > b ? a : b);
      case Call(:final args):
        var m = -1;
        for (final a in args) {
          final x = ready(a);
          if (x == null) return null;
          if (x > m) m = x;
        }
        return m;
    }
  }

  var body = [
    for (final s in p.body) _mapStmt(s, canon),
  ];
  final locals = [...p.locals];
  var n = 0;
  for (;;) {
    // occurrences per key: statement index of the first, and how many
    final first = <String, int>{}, times = <String, int>{}, expr = <String, Expr>{};
    void visit(Expr e, int at) {
      if (heavy(e)) {
        final k = key(e);
        first.putIfAbsent(k, () => at);
        times[k] = (times[k] ?? 0) + 1;
        expr[k] = e;
      }
      switch (e) {
        case Unary(:final e):
          visit(e, at);
        case Binary(:final l, :final r):
          visit(l, at);
          visit(r, at);
        case Call(:final args):
          for (final a in args) {
            visit(a, at);
          }
        default:
      }
    }

    void visitStmt(Stmt s, int at) {
      switch (s) {
        case Assign(:final e) || OutAssign(:final e):
          visit(e, at);
        case If(:final cond, :final then, :final otherwise):
          visit(cond, at);
          for (final t in [...then, ...otherwise]) {
            visitStmt(t, at);
          }
      }
    }

    for (var i = 0; i < body.length; i++) {
      visitStmt(body[i], i);
    }
    // the biggest repeated pure expression whose inputs are ready before its first use
    String? best;
    for (final k in times.keys) {
      if (times[k]! < 2) continue;
      final r = ready(expr[k]!);
      if (r == null || r >= first[k]!) continue;
      if (best == null || size(expr[k]!) > size(expr[best]!)) best = k;
    }
    if (best == null) break;
    final e = expr[best]!, at = first[best]!, name = '__cse${n++}';
    locals.add(name);
    Expr sub(Expr x) => key(x) == best
        ? Local(name)
        : switch (x) {
            Unary(:final op, :final e) => Unary(op, sub(e)),
            Binary(:final op, :final l, :final r) => Binary(op, sub(l), sub(r)),
            Call(:final fn, :final args) => Call(fn, [for (final a in args) sub(a)]),
            _ => x,
          };
    body = [
      for (var i = 0; i < body.length; i++) ...[
        if (i == at) Assign(name, e, line: body[i].line),
        i >= at ? _mapStmt(body[i], sub) : body[i],
      ],
    ];
    // later statements moved down by one
    for (final k in defAt.keys.toList()) {
      if (defAt[k]! >= at) defAt[k] = defAt[k]! + 1;
    }
    defAt[name] = at;
  }
  return Program(body, locals, p.outMap, p.outNames);
}

Stmt _mapStmt(Stmt s, Expr Function(Expr) f) => switch (s) {
      Assign(:final name, :final e) => Assign(name, f(e), line: s.line),
      OutAssign(:final slot, :final e) => OutAssign(slot, f(e), line: s.line),
      If(:final cond, :final then, :final otherwise) =>
        If(f(cond), [for (final t in then) _mapStmt(t, f)], [for (final t in otherwise) _mapStmt(t, f)], line: s.line),
    };
