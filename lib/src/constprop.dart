// Constant locals: `let n = 24;` assigned once, at the top level, to a value that folds to a
// constant, is replaced by that constant in the statements after it, so `in.x / n` compiles
// like `in.x / 24` (reciprocal multiply instead of the general divide) and the local needs no
// register. The value comes from the reference evaluator, so the result is bit-exact.
import 'lang/ast.dart';
import 'lang/eval.dart' show evaluate;

Program propagateConstants(Program p, {bool fast = false}) {
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
  final env = <String, int>{};
  Expr sub(Expr e) => switch (e) {
        Local(:final name) when env.containsKey(name) => Num(env[name]!),
        Unary(:final op, :final e) => Unary(op, sub(e)),
        Binary(:final op, :final l, :final r) => Binary(op, sub(l), sub(r)),
        Call(:final fn, :final args) => Call(fn, [for (final a in args) sub(a)]),
        _ => e,
      };
  bool isConst(Expr e) => switch (e) {
        Num() => true,
        In() || OutRead() || Local() => false,
        Unary(:final e) => isConst(e),
        Binary(:final l, :final r) => isConst(l) && isConst(r),
        Call(:final args) => args.every(isConst),
      };
  Stmt subStmt(Stmt s) => switch (s) {
        Assign(:final name, :final e) => Assign(name, sub(e), line: s.line),
        OutAssign(:final slot, :final e) => OutAssign(slot, sub(e), line: s.line),
        If(:final cond, :final then, :final otherwise) =>
          If(sub(cond), [for (final t in then) subStmt(t)], [for (final t in otherwise) subStmt(t)], line: s.line),
      };

  final body = <Stmt>[], folded = <String, Assign>{};
  for (final s in p.body) {
    final t = subStmt(s);
    if (t is Assign && assigns[t.name] == 1 && isConst(t.e)) {
      env[t.name] = evaluate(Program([OutAssign(0, t.e)], const [], const [], const {}), const {}, null, fast)[0];
      folded[t.name] = t;
      continue;
    }
    body.add(t);
  }
  if (folded.isEmpty) return p;

  // a folded local still read somewhere (before its assignment: it reads 0 there) keeps its
  // assignment, in place
  final read = <String>{};
  void reads(Expr e) {
    switch (e) {
      case Local(:final name):
        read.add(name);
      case Unary(:final e):
        reads(e);
      case Binary(:final l, :final r):
        reads(l);
        reads(r);
      case Call(:final args):
        args.forEach(reads);
      default:
    }
  }

  void readsStmt(Stmt s) {
    switch (s) {
      case Assign(:final e) || OutAssign(:final e):
        reads(e);
      case If(:final cond, :final then, :final otherwise):
        reads(cond);
        then.forEach(readsStmt);
        otherwise.forEach(readsStmt);
    }
  }

  body.forEach(readsStmt);
  if (folded.keys.any(read.contains)) {
    // rare: rebuild keeping those assignments where they were
    final keep = folded.keys.where(read.contains).toSet();
    final out = <Stmt>[];
    var i = 0;
    for (final s in p.body) {
      if (s is Assign && folded.containsKey(s.name)) {
        if (keep.contains(s.name)) out.add(folded[s.name]!);
      } else {
        out.add(body[i++]);
      }
    }
    return Program(out, [for (final l in p.locals) if (!folded.containsKey(l) || keep.contains(l)) l], p.outMap, p.outNames);
  }
  return Program(body, [for (final l in p.locals) if (!folded.containsKey(l)) l], p.outMap, p.outNames);
}
