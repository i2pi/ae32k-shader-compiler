// smoothstep(e0, e1, x) with constant edges, e1 > e0, as plain expressions the code generator
// does well: t = clamp(x - e0, 0, e1 - e0) / (e1 - e0) into a fresh local (a reciprocal
// multiply, the dividend's range being known), then t * t * (3 - 2 * t). Bit-exact with
// q_smoothstep: for d > 0, clamp(q_div(n, d), 0, 1) == q_div(clamp(n, 0, d), d), since q_div is
// monotone in n, q_div(0, d) = 0 and q_div(d, d) = 1.0. The local is assigned just before the
// statement that uses it (smoothstep has no side effects, so evaluating it early is safe).
import 'lang/ast.dart';
import 'lang/q16.dart';

Program lowerSmoothstep(Program p) {
  final locals = [...p.locals];
  var n = 0;
  List<Stmt> block(List<Stmt> ss) {
    final out = <Stmt>[];
    for (final s in ss) {
      final pre = <Stmt>[];
      Expr x(Expr e) {
        switch (e) {
          case Call(fn: 'smoothstep', :final args)
              when args[0] is Num && args[1] is Num && i32((args[1] as Num).q - (args[0] as Num).q) > 0:
            final e0 = (args[0] as Num).q, d = i32((args[1] as Num).q - e0);
            final t = '__ss${n++}';
            locals.add(t);
            pre.add(Assign(t, Binary('/', Call('clamp', [Binary('-', x(args[2]), Num(e0)), const Num(0), Num(d)]), Num(d)), line: s.line));
            final tl = Local(t);
            return Binary('*', Binary('*', tl, tl), Binary('-', const Num(3 * q1), Binary('*', const Num(2 * q1), tl)));
          case Unary(:final op, :final e):
            return Unary(op, x(e));
          case Binary(:final op, :final l, :final r):
            return Binary(op, x(l), x(r));
          case Call(:final fn, :final args):
            return Call(fn, [for (final a in args) x(a)]);
          default:
            return e;
        }
      }

      final Stmt t = switch (s) {
        Assign(:final name, :final e) => Assign(name, x(e), line: s.line),
        OutAssign(:final slot, :final e) => OutAssign(slot, x(e), line: s.line),
        If(:final cond, :final then, :final otherwise) => If(x(cond), block(then), block(otherwise), line: s.line),
      };
      out
        ..addAll(pre)
        ..add(t);
    }
    return out;
  }

  final body = block(p.body);
  return n == 0 ? p : Program(body, locals, p.outMap, p.outNames);
}
