// The Q16 runtime, bit-exact with the C that shader.py compiles with gcc (RUNTIME in
// zephyr_scion tools/imcu/shader.py): every function takes and returns 32-bit two's
// complement ints, with C's wrap-around on + - and unsigned 32-bit arithmetic where the
// C uses `unsigned`. This is the reference the native code generator must match.
import '../sin_table.dart';

const q1 = 65536;

int i32(int v) => (v & 0xffffffff) >= 0x80000000 ? (v & 0xffffffff) - 0x100000000 : v & 0xffffffff;
int u32(int v) => v & 0xffffffff;

/// C `(unsigned)a` for a negative int, negated: `-(unsigned)a`.
int _uabs(int a) => a < 0 ? u32(-a) : a;

int qMul(int a, int b) {
  final neg = (u32(a) ^ u32(b)) >> 31;
  final ua = _uabs(a), ub = _uabs(b);
  final ah = ua >> 16, al = ua & 0xffff, bh = ub >> 16, bl = ub & 0xffff;
  final hi = u32(ah * bh);
  if (hi >= 0x7fff) return neg != 0 ? -0x7fffffff : 0x7fffffff;
  var r = u32((hi << 16) + ah * bl + al * bh + (u32(al * bl) >> 16));
  if (r >= 0x7fffffff) r = 0x7fffffff;
  return neg != 0 ? i32(-r) : i32(r);
}

int qDiv(int a, int b) {
  final neg = (u32(a) ^ u32(b)) >> 31;
  final ua = _uabs(a), ub = _uabs(b);
  var q = 0, r = 0;
  if (ub == 0) return 0;
  for (var i = 47; i >= 0; i--) {
    final bit = i >= 16 ? (ua >> (i - 16)) & 1 : 0;
    if (r & 0x80000000 != 0) r = 0x7fffffff;
    r = u32(r << 1 | bit);
    if (r >= ub) {
      r = u32(r - ub);
      if (i < 31) {
        q |= 1 << i;
      } else {
        q = 0x7fffffff;
      }
    }
  }
  q = u32(q);
  return neg != 0 ? i32(-q) : i32(q);
}

int udiv32(int n, int d) {
  var q = 0, s = 0;
  if (d == 0) return 0;
  if (n < d) return 0;
  while (d <= (n >> 1) && s < 31) {
    d = u32(d << 1);
    s++;
  }
  for (; s >= 0; s--, d >>= 1) {
    q = u32(q << 1);
    if (n >= d) {
      n = u32(n - d);
      q |= 1;
    }
  }
  return q;
}

int qSin(int x) {
  final i = (u32(x) >> 8) & 255, f = u32(x) & 255;
  final s0 = sin256[i], s1 = sin256[(i + 1) & 255];
  return i32(s0 * (256 - f) + s1 * f) >> 6;
}

int qCos(int x) => qSin(i32(x + 16384));

const _at = [
  0, 163, 326, 489, 651, 813, 975, 1136, 1297, 1457, 1617, 1775, 1933, 2090, 2246, 2401, 2555,
  2708, 2860, 3010, 3159, 3307, 3453, 3599, 3742, 3884, 4025, 4164, 4302, 4438, 4572, 4705, 4836,
  4966, 5094, 5220, 5344, 5467, 5589, 5708, 5826, 5943, 6058, 6171, 6282, 6392, 6500, 6607, 6712,
  6815, 6917, 7018, 7117, 7214, 7310, 7405, 7498, 7589, 7679, 7768, 7856, 7942, 8026, 8110, 8192,
];

int qAtan2(int y, int x) {
  final ax = _uabs(x), ay = _uabs(y);
  final big = ax > ay ? ax : ay, sml = ax > ay ? ay : ax;
  if (big == 0) return 0;
  final r = big < (1 << 17) ? udiv32(u32(sml << 14), big) : udiv32(sml, big >> 14);
  var i = r >> 8, f = r & 255;
  if (i > 63) {
    i = 63;
    f = 255;
  }
  var a = (_at[i] * (256 - f) + _at[i + 1] * f) >> 8;
  if (ax < ay) a = 16384 - a;
  if (x < 0) a = 32768 - a;
  if (y < 0) a = -a;
  return a;
}

int isqrt32(int v) {
  var res = 0, bit = 1 << 30;
  while (bit > v) {
    bit >>= 2;
  }
  while (bit != 0) {
    if (v >= res + bit) {
      v = u32(v - (res + bit));
      res = (res >> 1) + bit;
    } else {
      res >>= 1;
    }
    bit >>= 2;
  }
  return res;
}

int qSqrt(int x) {
  if (x <= 0) return 0;
  if (x < (1 << 22)) return i32(isqrt32(u32(x << 8)) << 4);
  return i32(isqrt32(x) << 8);
}

int qAbs(int a) => a < 0 ? i32(-a) : a;
int qMin(int a, int b) => a < b ? a : b;
int qMax(int a, int b) => a > b ? a : b;
int qClamp(int x, int lo, int hi) => x < lo ? lo : (x > hi ? hi : x);
int qFloor(int a) => i32(a & ~0xffff);
int qFrac(int a) => a & 0xffff;
int qLerp(int a, int b, int t) => i32(a + qMul(i32(b - a), t));
int qStep(int e, int x) => x < e ? 0 : q1;
int qSign(int a) => a > 0 ? q1 : (a < 0 ? -q1 : 0);

int qSmoothstep(int e0, int e1, int x) {
  final t = qClamp(qDiv(i32(x - e0), i32(e1 - e0)), 0, q1);
  return qMul(qMul(t, t), i32(3 * q1 - 2 * t));
}

int qMod(int a, int b) => b != 0 ? i32(a - qMul(qFloor(qDiv(a, b)), b)) : 0;

int _vh(int ix, int iy) {
  var h = u32(u32(ix) * 73856093) ^ u32(u32(iy) * 19349663) ^ 0x9E3779B9;
  h = u32(h * 2654435761);
  h ^= h >> 15;
  h = u32(h * 2246822519);
  h ^= h >> 13;
  return h & 0xffff;
}

int qNoise(int x, int y) {
  final ix = x >> 16, iy = y >> 16, fx = x & 0xffff, fy = y & 0xffff;
  final sx = qMul(qMul(fx, fx), i32(3 * q1 - 2 * fx)), sy = qMul(qMul(fy, fy), i32(3 * q1 - 2 * fy));
  final a = _vh(ix, iy), b = _vh(i32(ix + 1), iy), c2 = _vh(ix, i32(iy + 1)), d = _vh(i32(ix + 1), i32(iy + 1));
  final top = i32(a + qMul(b - a, sx)), bot = i32(c2 + qMul(d - c2, sx));
  return i32(top + qMul(i32(bot - top), sy));
}

int callQ(String fn, List<int> a) => switch (fn) {
      'sin' => qSin(a[0]),
      'cos' => qCos(a[0]),
      'atan2' => qAtan2(a[0], a[1]),
      'sqrt' => qSqrt(a[0]),
      'abs' => qAbs(a[0]),
      'min' => qMin(a[0], a[1]),
      'max' => qMax(a[0], a[1]),
      'clamp' => qClamp(a[0], a[1], a[2]),
      'floor' => qFloor(a[0]),
      'frac' => qFrac(a[0]),
      'lerp' => qLerp(a[0], a[1], a[2]),
      'smoothstep' => qSmoothstep(a[0], a[1], a[2]),
      'step' => qStep(a[0], a[1]),
      'sign' => qSign(a[0]),
      'noise' => qNoise(a[0], a[1]),
      'mod' => qMod(a[0], a[1]),
      _ => throw ArgumentError('unknown function $fn'),
    };
