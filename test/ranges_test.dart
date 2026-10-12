// The range analysis (lib/src/ranges.dart) must contain every value a program computes:
// checked on every subexpression of random programs, in both modes, and the function bounds
// it relies on exhaustively or at their extremes.
import 'dart:math';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:ae32k_shader_compiler/src/emu.dart';
import 'package:ae32k_shader_compiler/src/lang/ast.dart';
import 'package:ae32k_shader_compiler/src/lang/eval.dart';
import 'package:ae32k_shader_compiler/src/lang/parser.dart';
import 'package:ae32k_shader_compiler/src/lang/q16.dart';
import 'package:ae32k_shader_compiler/src/ranges.dart';
import 'package:test/test.dart';

import 'emu_gcc_test.dart' show randomInputs;
import 'support/random_program.dart';

void main() {
  test('function bounds', () {
    for (var x = 0; x < 65536; x++) {
      // sin/cos read only the low 16 bits
      expect(qSin(x), inInclusiveRange(-q1, q1));
      expect(qCos(x), inInclusiveRange(-q1, q1));
    }
    // sqrt is largest at the largest input (isqrt is monotonic within each branch)
    expect(qSqrt(0x7fffffff), lessThanOrEqualTo(11863040));
    expect(qSqrt((1 << 22) - 1), lessThanOrEqualTo(11863040));
    // and monotone (the range of sqrt(x) is sqrt of x's bounds), across its branch point too
    for (var x = (1 << 22) - 70000; x < (1 << 22) + 70000; x++) {
      expect(qSqrt(x + 1), greaterThanOrEqualTo(qSqrt(x)));
    }
    for (var x = 0; x < 1 << 31; x += 4093) {
      expect(qSqrt(x + 4093), greaterThanOrEqualTo(qSqrt(x)));
    }
    final rng = Random(2);
    for (var n = 0; n < 20000; n++) {
      final a = rng.nextInt(1 << 32) - (1 << 31), b = rng.nextInt(1 << 32) - (1 << 31);
      expect(qAtan2(a, b), inInclusiveRange(-32768, 32768));
      expect(qNoise(a, b), inInclusiveRange(0, 0xffff));
      expect(qSmoothstep(a, b, rng.nextInt(1 << 32) - (1 << 31)), inInclusiveRange(0, q1));
    }
  });

  test('mod by a whole constant stays within +-(2|c| + 1.0), extremes included', () {
    final rng = Random(4);
    for (final k in [2, 3, 5, 7, 24, 100, 1000, 4095, 4096]) {
      for (final c in [k * q1, -k * q1]) {
        final r = rangeOf(Binary('%', const In('x'), Num(c)), const {})!;
        void t(int a) => expect(qMod(a, c), inInclusiveRange(r.lo, r.hi), reason: 'mod($a, $c)');
        for (var d = 0; d < 20000; d++) {
          t(-0x80000000 + d);
          t(0x7fffffff - d);
          t(d - 10000);
        }
        for (var n = 0; n < 50000; n++) {
          t(rng.nextInt(1 << 32) - (1 << 31));
        }
      }
    }
  });

  for (final fast in [false, true]) {
    test('every subexpression lies in its range (random programs${fast ? ', fast' : ''})', () {
      final rng = Random(fast ? 41 : 40);
      final gen = RandomProgram(rng);
      var checked = 0;
      for (var n = 0; n < 600; n++) {
        final src = gen.program();
        final prog = parse(src);
        final locals = localRanges(prog);
        for (var k = 0; k < 20; k++) {
          evaluate(prog, randomInputs(rng), null, fast, (e, v) {
            final r = rangeOf(e, locals);
            if (r == null) return;
            checked++;
            if (v < r.lo || v > r.hi) fail('value $v outside $r for $e in\n$src');
          });
        }
      }
      expect(checked, greaterThan(10000));
    });
  }

  for (final fast in [false, true]) {
    test('inline multiply by bounded factors at edge inputs${fast ? ', fast' : ''}', () {
      const factors = ['sin(in.y)', 'cos(in.y)', 'frac(in.y)', 'noise(in.y, in.u)', '(in.y > 0)', 'step(in.y, 0)',
        'smoothstep(0, 1, in.y)', 'sign(in.y)', 'clamp(in.y, -1, 1)', 'abs(sin(in.y))', '(1 - frac(in.y))'];
      const xs = [0, 1, -1, 0x7fffffff, -0x7fffffff, -0x80000000, 0x7fff0000, 0x7ffeffff, -0x7fff0000, 0x12345678,
        -0x12345678, 0x10000, -0x10000, 0xffff];
      const ys = [0, 1, -1, 0x4000, 0x8000, 0xc000, 0x10000, -0x10000, 0x7fffffff, -0x80000000, 0x3243f, 0x123];
      for (final f in factors) {
        for (final src in ['out.dx = in.x * $f;', 'out.dx = $f * in.x;', 'let a = frac(in.x); out.dx = a * $f;',
          'out.dx = sin(in.x) * 40 + $f * 3.7;']) {
          final prog = parse(src);
          final runner = StageRunner(compileStage(src, fast: fast).bytes);
          for (final x in xs) {
            for (final y in ys) {
              final inputs = {'x': x, 'y': y, 'u': y ^ 0x5555};
              expect(runner.run(inputs)[0], evaluate(prog, inputs, null, fast)[0], reason: '$src x=$x y=$y');
            }
          }
        }
      }
    });
  }
}
