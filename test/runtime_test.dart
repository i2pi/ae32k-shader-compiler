// Each assembly runtime routine against its q16.dart reference, in the emulator, over
// edge cases and random arguments; and the register convention (R0-R7 and R14 survive).
import 'dart:math';

import 'package:ae32k_shader_compiler/src/abi.dart';
import 'package:ae32k_shader_compiler/src/asm.dart';
import 'package:ae32k_shader_compiler/src/emu.dart';
import 'package:ae32k_shader_compiler/src/lang/q16.dart';
import 'package:ae32k_shader_compiler/src/runtime.dart';
import 'package:ae32k_shader_compiler/src/sin_table.dart';
import 'package:test/test.dart';

const edges = [
  0, 1, -1, 2, -2, 0x7fff, 0x8000, 0xffff, 0x10000, -0x10000, 0x10001, 0x18000, 0x7fffffff,
  -0x7fffffff, -0x80000000, 0x40000000, -0x40000000, 0x3fffffff, 0x7fff0000, 0x7ffeffff, 0x123456,
  -0x123456, 0x00ff00ff, 1 << 22, (1 << 22) - 1, 1 << 17, (1 << 17) - 1, 100 << 16, -(100 << 16),
];

class Harness {
  static const ctx = Cpu.dspm + 0x1000, sinAt = Cpu.dspm + 0x1400;
  late final Assembled code;
  final String entry;
  Harness(this.entry, {bool fast = false}) {
    code = assemble(runtimeFor([entry], fast: fast), slotAddr[0]!);
  }

  int call(List<int> args) {
    final cpu = Cpu();
    cpu.load(slotAddr[0]!, code.bytes);
    for (var k = 0; k < 256; k++) {
      cpu.write16(sinAt + 2 * k, sin256[k]);
    }
    cpu.write32(ctx + ctxSin, sinAt);
    cpu.stackPtr = Cpu.dspm + 0x10000;
    for (final k in [0, 1, 2, 3, 4, 5, 6, 7]) {
      cpu.r[k] = 0x5A5A0000 + k;
    }
    cpu.r[14] = ctx;
    if (args.length > 1) cpu.r[9] = args[1];
    if (args.length > 2) cpu.r[10] = args[2];
    final res = cpu.call(code.labels[entry]!, args[0]);
    for (final k in [0, 1, 2, 3, 4, 5, 6, 7]) {
      if (cpu.r[k] != 0x5A5A0000 + k) throw EmuError('$entry clobbered R$k');
    }
    if (cpu.r[14] != ctx) throw EmuError('$entry clobbered R14');
    if (cpu.stackPtr != Cpu.dspm + 0x10000) throw EmuError('$entry: SP off');
    return res;
  }
}

void check(String entry, int arity, int Function(List<int>) ref, {int random = 3000}) {
  test(entry, () {
    final h = Harness(entry);
    final rng = Random(entry.hashCode);
    int pick() => switch (rng.nextInt(4)) {
          0 => edges[rng.nextInt(edges.length)],
          1 => rng.nextInt(0x40000) - 0x20000,
          2 => (rng.nextDouble() * 200 - 100 * 65536).round(),
          _ => rng.nextInt(0x100000000) - 0x80000000,
        };
    final cases = <List<int>>[
      if (arity == 1) for (final a in edges) [a],
      if (arity == 2) for (final a in edges) for (final b in edges) [a, b],
      for (var n = 0; n < random; n++) [for (var k = 0; k < arity; k++) pick()],
    ];
    for (final a in cases) {
      expect(h.call(a), ref(a), reason: '$entry(${a.join(', ')})');
    }
  });
}

void main() {
  check('__qmul', 2, (a) => qMul(a[0], a[1]));
  for (final fast in [false, true]) {
    test('__qmul around its saturation tests${fast ? ', fast' : ''}', () {
      // the C saturates at (|a|>>16)*(|b|>>16) >= 0x7fff, and the routine also at |a||b| >= 2^47
      final h = Harness('__qmul', fast: fast);
      final rng = Random(fast ? 12 : 11);
      const highs = [(1, 0x7ffe), (1, 0x7fff), (0x7fff, 1), (181, 181), (181, 182), (2, 0x3fff), (2, 0x4000), (0x8000, 1),
        (0x8000, 0), (0, 0x8000), (3, 0x2aaa), (0x7fff, 0), (0xffff >> 1, 1), (255, 128), (256, 127),
        (7, 0x1249), (31, 0x421), (151, 217), (217, 151)]; // 0x7fff = 7*31*151: the C's test fires below 2^47
      qFast = fast;
      try {
        for (final (ah, bh) in highs) {
          for (var n = 0; n < 400; n++) {
            int mk(int hi) {
              final lo = rng.nextBool() ? rng.nextInt(4) : rng.nextInt(0x10000);
              final m = hi == 0x8000 ? 0x80000000 : (hi << 16 | lo);
              return rng.nextBool() ? m.toSigned(32) : (-m).toSigned(32);
            }
            final a = mk(ah), b = mk(bh);
            expect(h.call([a, b]), qMul(a, b), reason: 'qmul($a, $b)');
          }
        }
      } finally {
        qFast = false;
      }
    });
  }
  check('__qdiv', 2, (a) => qDiv(a[0], a[1]), random: 1500);
  test('__qdiv at the saturation boundary and exact multiples', () {
    // |a| = |b| << 15 is where the quotient reaches 2^31; |a| = k|b| +- 1 flips integer bits.
    final h = Harness('__qdiv');
    final rng = Random(7);
    for (var n = 0; n < 3000; n++) {
      final b = 1 + rng.nextInt(1 << (1 + rng.nextInt(31)));
      final k = rng.nextBool() ? 1 << 15 : 1 + rng.nextInt(1 << (1 + rng.nextInt(15)));
      for (final d in [-1, 0, 1]) {
        final ua = b * k + d;
        if (ua < 0 || ua > 0x80000000) continue;
        for (final (sa, sb) in [(1, 1), (-1, 1), (1, -1), (-1, -1)]) {
          final a = (sa * ua).toSigned(32), bb = (sb * b).toSigned(32);
          expect(h.call([a, bb]), qDiv(a, bb), reason: 'q_div($a, $bb)');
        }
      }
    }
  });
  check('__qsin', 1, (a) => qSin(a[0]));
  check('__qcos', 1, (a) => qCos(a[0]));
  check('__qsqrt', 1, (a) => qSqrt(a[0]));
  test('__isqrt on perfect squares +-1 and the full unsigned range', () {
    final h = Harness('__isqrt');
    final rng = Random(3);
    final vs = <int>[0, 1, 2, 3, 0xffffffff, 0x80000000, 0x40000000, 0x3fffffff,
      for (var r = 1; r < 65536; r += 1 + rng.nextInt(97)) ...[r * r - 1, r * r, r * r + 1],
      for (var n = 0; n < 2000; n++) rng.nextInt(1 << 32)];
    for (final v in vs) {
      expect(h.call([v.toSigned(32)]) & 0xffffffff, isqrt32(v & 0xffffffff), reason: 'isqrt($v)');
    }
  });
  test('__qatan2 around its division: big near 2^17, small == big, extremes', () {
    final h = Harness('__qatan2');
    final rng = Random(13);
    final bigs = [1, 2, 3, 0xffff, 0x10000, 0x1ffff, 0x20000, 0x20001, 0x3ffff, 0x7fffffff, 0x80000000,
      for (var n = 0; n < 200; n++) 1 + rng.nextInt(1 << (1 + rng.nextInt(31)))];
    for (final big in bigs) {
      for (final small in {0, 1, big, big - 1, big ~/ 2, big ~/ 3 + 1, rng.nextInt(big) + 0}) {
        for (final (sy, sx) in [(1, 1), (-1, 1), (1, -1), (-1, -1)]) {
          for (final swap in [false, true]) {
            final a = ((swap ? small : big) * sy).toSigned(32), b = ((swap ? big : small) * sx).toSigned(32);
            expect(h.call([a, b]), qAtan2(a, b), reason: 'atan2($a, $b)');
          }
        }
      }
    }
  });
  check('__qatan2', 2, (a) => qAtan2(a[0], a[1]));
  check('__qmod', 2, (a) => qMod(a[0], a[1]), random: 1000);
  check('__qsmooth', 3, (a) => qSmoothstep(a[0], a[1], a[2]), random: 1000);
  check('__qnoise', 2, (a) => qNoise(a[0], a[1]), random: 1500);
}
