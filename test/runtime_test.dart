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
  Harness(this.entry) {
    code = assemble(runtimeFor([entry]), slotAddr[0]!);
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
  check('__udiv', 2, (a) => udiv32(a[0] & 0xffffffff, a[1] & 0xffffffff).toSigned(32));
  check('__qatan2', 2, (a) => qAtan2(a[0], a[1]));
  check('__qmod', 2, (a) => qMod(a[0], a[1]), random: 1000);
  check('__qsmooth', 3, (a) => qSmoothstep(a[0], a[1], a[2]), random: 1000);
  check('__qnoise', 2, (a) => qNoise(a[0], a[1]), random: 1500);
}
