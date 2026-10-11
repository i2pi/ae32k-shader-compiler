// Reference interpreter: runs a parsed stage with the exact semantics of the C that
// shader.py generates (q16.dart), so native code can be checked against it bit for bit.
import 'ast.dart';
import 'q16.dart';

/// Inputs by name (abi.dart ctxInput) and the 16 outputs as the resident left them
/// (zero, or 1.0 for `gain` map entries). Returns the outputs after the stage ran.
///
/// [observe] sees every expression evaluated, with its value (for checking range analysis).
List<int> evaluate(Program p, Map<String, int> inputs,
    [List<int>? outInit, bool fast = false, void Function(Expr e, int value)? observe]) {
  final was = qFast;
  qFast = fast;
  try {
    return _evaluate(p, inputs, outInit, observe);
  } finally {
    qFast = was;
  }
}

List<int> _evaluate(Program p, Map<String, int> inputs, List<int>? outInit, void Function(Expr, int)? observe) {
  final out = List<int>.of(outInit ?? List.filled(16, 0));
  final env = {for (final l in p.locals) l: 0};

  late final int Function(Expr) ev;
  int ev0(Expr e) => switch (e) {
        Num(:final q) => q,
        In(:final name) => i32(inputs[name] ?? 0),
        OutRead(:final slot) => out[slot],
        Local(:final name) => env[name]!,
        Unary(op: '-', :final e) => i32(-ev(e)),
        Unary(:final e) => ev(e) != 0 ? 0 : q1,
        Call(:final fn, :final args) => callQ(fn, [for (final a in args) ev(a)]),
        Binary(:final op, :final l, :final r) => _bin(op, l, r, ev),
      };
  ev = observe == null
      ? ev0
      : (e) {
          final v = ev0(e);
          observe(e, v);
          return v;
        };

  void run(List<Stmt> body) {
    for (final s in body) {
      switch (s) {
        case Assign(:final name, :final e):
          env[name] = ev(e);
        case OutAssign(:final slot, :final e):
          out[slot] = ev(e);
        case If(:final cond, :final then, :final otherwise):
          run(ev(cond) != 0 ? then : otherwise);
      }
    }
  }

  run(p.body);
  return out;
}

int _bin(String op, Expr l, Expr r, int Function(Expr) ev) {
  // && and || short-circuit in C; the operands are pure, so only the value matters
  if (op == '&&') return ev(l) != 0 && ev(r) != 0 ? q1 : 0;
  if (op == '||') return ev(l) != 0 || ev(r) != 0 ? q1 : 0;
  final a = ev(l), b = ev(r);
  return switch (op) {
    '+' => i32(a + b),
    '-' => i32(a - b),
    '*' => qMul(a, b),
    '/' => qDiv(a, b),
    '%' => qMod(a, b),
    '<' => a < b ? q1 : 0,
    '<=' => a <= b ? q1 : 0,
    '>' => a > b ? q1 : 0,
    '>=' => a >= b ? q1 : 0,
    '==' => a == b ? q1 : 0,
    '!=' => a != b ? q1 : 0,
    _ => throw ArgumentError('operator $op'),
  };
}
