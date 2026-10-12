// Value ranges of expressions, exact under the language's semantics (no assumptions about the
// inputs, which the resident does not bound: vertex coordinates go off screen, t wraps). Used
// to drop sign handling and saturation tests that cannot matter, e.g. in sin(..) * 40 or
// x * frac(..). Function bounds are checked exhaustively in test/ranges_test.dart.
import 'lang/ast.dart';
import 'lang/q16.dart';

class Range {
  final int lo, hi;
  const Range(this.lo, this.hi);
  bool get nonNeg => lo >= 0;
  int get mag => hi.abs() > lo.abs() ? hi.abs() : lo.abs();
  bool within(int a, int b) => lo >= a && hi <= b;
  Range union(Range o) => Range(lo < o.lo ? lo : o.lo, hi > o.hi ? hi : o.hi);
  @override
  bool operator ==(Object other) => other is Range && other.lo == lo && other.hi == hi;
  @override
  int get hashCode => Object.hash(lo, hi);
  @override
  String toString() => '[$lo, $hi]';
}

const _minI = -0x80000000, _maxI = 0x7fffffff;
const unit = Range(-q1, q1), flag = Range(0, q1);

Range? _fit(int lo, int hi) => lo >= _minI && hi <= _maxI ? Range(lo, hi) : null;

/// Bounds of q_mul over two ranges, only where the true product stays well inside 32 bits
/// (then there is no saturation and no wrap, and q_mul is the product truncated toward 0).
Range? mulRange(Range? a, Range? b) {
  if (a == null || b == null) return null;
  if (a.mag * b.mag >= (_maxI - (1 << 17)) * q1) return null;
  final ps = [a.lo * b.lo, a.lo * b.hi, a.hi * b.lo, a.hi * b.hi];
  var lo = ps.first, hi = ps.first;
  for (final p in ps) {
    if (p < lo) lo = p;
    if (p > hi) hi = p;
  }
  // q_mul without saturation is exactly trunc(a * b / 2^16) (sign-magnitude), monotone in the product
  return Range(lo ~/ q1, hi ~/ q1);
}

Range? rangeOf(Expr e, Map<String, Range?> locals) {
  Range? r(Expr x) => rangeOf(x, locals);
  switch (e) {
    case Num(:final q):
      return Range(q, q);
    case In() || OutRead():
      return null;
    case Local(:final name):
      return locals[name];
    case Unary(op: '!'):
      return flag;
    case Unary(:final e):
      final x = r(e);
      return x == null || x.lo == _minI ? null : Range(-x.hi, -x.lo);
    case Binary(:final op, :final l, :final r):
      switch (op) {
        case '+' || '-':
          final a = rangeOf(l, locals), b = rangeOf(r, locals);
          if (a == null || b == null) return null;
          return op == '+' ? _fit(a.lo + b.lo, a.hi + b.hi) : _fit(a.lo - b.hi, a.hi - b.lo);
        case '*':
          return mulRange(rangeOf(l, locals), rangeOf(r, locals));
        case '/':
          // q_div by a constant is monotone in x (sign-magnitude, truncated, saturating)
          final a = rangeOf(l, locals);
          if (a == null || r is! Num || r.q == 0) return null;
          final x = qDiv(a.lo, r.q), y = qDiv(a.hi, r.q);
          return x <= y ? Range(x, y) : Range(y, x);
        case '%':
          return _modRange(r);
        default:
          return flag; // comparisons, && and ||
      }
    case Call(:final fn, :final args):
      final xs = [for (final a in args) r(a)];
      switch (fn) {
        case 'sin' || 'cos' || 'sign':
          return unit;
        case 'atan2':
          return const Range(-32768, 32768);
        case 'sqrt':
          // monotone: each branch of q_sqrt is, and it rises across the 2^22 boundary
          final x = xs[0];
          return x == null ? const Range(0, 11863040) : Range(qSqrt(x.lo), qSqrt(x.hi));
        case 'noise' || 'frac':
          return const Range(0, 0xffff);
        case 'step' || 'smoothstep':
          return flag;
        case 'abs':
          final x = xs[0];
          if (x == null || x.lo == _minI) return null;
          if (x.lo >= 0) return x;
          if (x.hi <= 0) return Range(-x.hi, -x.lo);
          return Range(0, x.mag);
        case 'floor':
          final x = xs[0];
          return x == null ? null : Range(x.lo & ~0xffff, x.hi & ~0xffff);
        case 'min' || 'max':
          final a = xs[0], b = xs[1];
          if (a == null || b == null) return null;
          return fn == 'min'
              ? Range(a.lo < b.lo ? a.lo : b.lo, a.hi < b.hi ? a.hi : b.hi)
              : Range(a.lo > b.lo ? a.lo : b.lo, a.hi > b.hi ? a.hi : b.hi);
        case 'clamp':
          final a = xs[1], b = xs[2];
          return a == null || b == null ? null : a.union(b);
        case 'mod':
          return _modRange(args[1]);
        case 'lerp':
          // a + q_mul(b - a, t)
          return rangeOf(Binary('+', args[0], Binary('*', Binary('-', args[1], args[0]), args[2])), locals);
        default:
          return null;
      }
  }
}

/// q_mod(a, c) for a whole constant 2 <= |c| <= 4096: within +-(2|c| + 1.0) for every a,
/// edge effects of q_div's truncation and q_mul's saturation included (checked by brute force
/// at the extremes of a in test/ranges_test.dart).
Range? _modRange(Expr c) {
  if (c is! Num) return null;
  final m = c.q.abs();
  if (m & 0xffff != 0 || m < 2 * q1 || m > 4096 * q1) return null;
  return Range(-2 * m - q1, 2 * m + q1);
}

/// Ranges of the locals over the whole program (they start at 0, as in C): the union of
/// everything assigned to each, iterated to a fixed point; unknown if it keeps growing.
Map<String, Range?> localRanges(Program p) {
  final assigns = <Assign>[];
  void collect(List<Stmt> body) {
    for (final s in body) {
      switch (s) {
        case Assign():
          assigns.add(s);
        case If(:final then, :final otherwise):
          collect(then);
          collect(otherwise);
        case OutAssign():
          break;
      }
    }
  }

  collect(p.body);
  final m = <String, Range?>{for (final l in p.locals) l: const Range(0, 0)};
  // after a few rounds, anything still growing (e.g. a = a + 1) is widened to unknown; locals
  // only move toward unknown from then on, so this ends
  for (var round = 0;; round++) {
    var changed = false;
    for (final a in assigns) {
      final cur = m[a.name];
      if (cur == null) continue;
      final v = rangeOf(a.e, m);
      final next = v == null || round >= 8 ? null : cur.union(v);
      if (next != cur && (v == null || cur.union(v) != cur)) {
        m[a.name] = next;
        changed = true;
      }
    }
    if (!changed) return m;
  }
}
