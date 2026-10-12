// The native compiler against the reference interpreter, in the emulator: the shader
// examples, the gcc corpus programs and random programs must give identical outputs.
import 'dart:io';
import 'dart:math';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:ae32k_shader_compiler/src/codegen.dart';
import 'package:ae32k_shader_compiler/src/emu.dart';
import 'package:ae32k_shader_compiler/src/lang/eval.dart';
import 'package:ae32k_shader_compiler/src/lang/parser.dart';
import 'package:test/test.dart';

import 'emu_gcc_test.dart' show randomInputs;
import 'support/random_program.dart';

void checkProgram(String name, String src, int slot, Random rng, {int runs = 100, bool fast = false}) {
  final prog = parse(src);
  final CompiledStage st;
  try {
    st = compileStage(src, slot: slot, fast: fast);
  } catch (e) {
    fail('$name does not compile: $e\n$src');
  }
  final runner = StageRunner(st.bytes, slot: slot);
  final init = List.filled(16, 0);
  for (final e in prog.outMap) {
    if (e.mode == 1) init[e.slot] = 65536;
  }
  for (var n = 0; n < runs; n++) {
    final inputs = randomInputs(rng);
    final List<int> got;
    try {
      got = runner.run(inputs, outInit: init);
    } catch (e) {
      fail('$name: $e\n$src\n${st.asm}');
    }
    final want = evaluate(prog, inputs, init, fast);
    if (got.join(',') != want.join(',')) {
      fail('$name: outputs differ\ninputs $inputs\nwant $want\ngot  $got\n$src\n${st.asm}');
    }
  }
}

void main() {
  final gcc = Directory('test/golden/gcc');
  for (final line in File('${gcc.path}/manifest.txt').readAsLinesSync().where((l) => l.isNotEmpty)) {
    final f = line.split('\t');
    test('native ${f[0]}', () {
      checkProgram(f[0], File('${gcc.path}/${f[0]}.ss').readAsStringSync(), int.parse(f[1]), Random(f[0].hashCode));
    });
  }
  test('q_mul by constants (inline) at edge inputs', () {
    // constants with integer and fraction parts, around the saturation threshold of ah*ch
    const consts = ['1.7', '-1.7', '3.1', '5.3', '0.7', '-0.25', '2', '-3', '100.5', '-1000.25', '32767.5', '1.0000153', '0'];
    const xs = [0, 1, -1, 0xffff, 0x10000, -0x10000, 0x18000, 0x7fffffff, -0x7fffffff, -0x80000000, 0x7fff0000,
      0x12345, -0x12345, 19 << 16, 20 << 16, 0x4b30000, 0x4b40000, 0x13ffff, 0x140000];
    for (final c in consts) {
      final src = 'out.dx = in.x * $c;\nout.dy = $c * in.y;';
      final runner = StageRunner(compileStage(src).bytes);
      final prog = parse(src);
      for (final x in xs) {
        final inputs = {'x': x, 'y': -x};
        expect(runner.run(inputs).sublist(0, 2), evaluate(prog, inputs).sublist(0, 2), reason: 'x=$x c=$c');
      }
    }
  });

  for (final fast in [false, true]) {
    test('q_div / q_mod by powers of two (inline)${fast ? ', fast' : ''}', () {
      const consts = ['8', '-8', '2', '0.5', '-0.25', '1', '-1', '0.0000153', '-16384', '256', '0.125', '16384'];
      const xs = [0, 1, -1, 7, -7, 0xffff, 0x10000, -0x10000, 0x18000, 0x7fffffff, -0x7fffffff, -0x80000000,
        0x7fff0000, 0x12345, -0x12345, 0x3fffffff, 0x40000000, 0xfffff, 0x100000, -0x100001, 1 << 30];
      for (final c in consts) {
        final src = 'out.dx = in.x / $c;\nout.dy = mod(in.x, $c);\nout.o2 = in.y % $c;';
        final runner = StageRunner(compileStage(src, fast: fast).bytes);
        expect(compileStage(src, fast: fast).asm, isNot(contains('jal __qdiv')), reason: c);
        final prog = parse(src);
        for (final x in xs) {
          final inputs = {'x': x, 'y': -x};
          expect(runner.run(inputs).sublist(0, 3), evaluate(prog, inputs, null, fast).sublist(0, 3), reason: 'x=$x c=$c');
        }
      }
    });
  }

  test('minimal stages around each runtime call (prologue / ctx register choices)', () {
    // a body whose only ctx reads come before a call that reads ctx itself (sin's table)
    const bodies = [
      'out.dx = sin(in.x);', 'out.dx = cos(in.x);', 'let a = in.x; out.dx = abs(sin(a));', 'out.dx = sqrt(in.x);',
      'out.dx = atan2(in.x, in.y);', 'out.dx = noise(in.x, in.y);', 'out.dx = in.x / in.y;', 'out.dx = in.x * in.y;',
      'out.dx = mod(in.x, in.y);', 'out.dx = smoothstep(in.x, in.y, in.u);', 'out.dx = 1;', 'let a = 2;',
      'if (in.x > 0) { out.dx = sin(in.y); }', 'out.dx = in.x * 1.5; out.dy = in.y / 4;',
      // no ctx access after the call: only the routine itself reads R14
      'let a = sin(in.x);', 'let a = min(in.x, 1); a = abs(sin(a));', 'let a = cos(in.y) + noise(in.x, 1);',
    ];
    final rng = Random(5);
    for (final fast in [false, true]) {
      for (final b in bodies) {
        checkProgram(b, b, 0, rng, runs: 30, fast: fast);
      }
    }
  });

  test('the reciprocal for every whole divisor 3..32767: floor(x*M >> S) == x ~/ k', () {
    final rng = Random(9);
    for (var k = 3; k < 1 << 15; k++) {
      if (k & (k - 1) == 0) continue;
      final (m, sh) = CodeGen.magic(k)!;
      final xs = [0, 1, k - 1, k, k + 1, 0x7fffffff, 0x80000000, 0x80000000 - (0x80000000 % k), 0x80000000 - (0x80000000 % k) - 1,
        for (var n = 0; n < 40; n++) rng.nextInt(1 << 31)];
      for (final x in xs) {
        expect((BigInt.from(x) * BigInt.from(m)) >> sh, BigInt.from(x ~/ k), reason: 'k=$k x=$x');
      }
    }
  });

  for (final fast in [false, true]) {
    test('q_div / q_mod by whole constants (inline reciprocal)${fast ? ', fast' : ''}', () {
      const consts = ['3', '-3', '12', '1080', '1920', '7', '-1000', '32767', '10', '100', '255'];
      final rng = Random(11);
      final xs = [0, 1, -1, 11, 12, 13, -12, -13, 0x7fffffff, -0x7fffffff, -0x80000000, 0x10000, -0x10000,
        for (var n = 0; n < 60; n++) rng.nextInt(1 << 32) - (1 << 31)];
      for (final c in consts) {
        final src = 'out.dx = in.x / $c;\nout.dy = mod(in.x, $c);\nout.o2 = (in.y + 0.5) / $c;';
        final st = compileStage(src, fast: fast);
        expect(st.asm, isNot(contains('jal __qdiv')), reason: c);
        final runner = StageRunner(st.bytes);
        final prog = parse(src);
        for (final x in xs) {
          final inputs = {'x': x, 'y': x ^ 0x1234567};
          expect(runner.run(inputs).sublist(0, 3), evaluate(prog, inputs, null, fast).sublist(0, 3), reason: 'x=$x c=$c');
        }
      }
    });
  }

  for (final fast in [false, true]) {
    test('constant locals, shared subexpressions, smoothstep and fractional divisors${fast ? ', fast' : ''}', () {
      // programs shaped for the AST passes: a let bound to a constant, the same expression
      // twice, cos next to sin(.. + 0.25), smoothstep with constant edges (either order, equal,
      // wide), and divisions of bounded values by fractions
      final rng = Random(fast ? 77 : 78);
      const edges = ['0.0, 0.06', '0.1, 0.5', '0.5, 0.1', '0.3, 0.3', '-2, 3', '0, 1', '0.02, 0.12', '-1000, 1000', '0, 0.5', '0, 0.75'];
      const fracs = ['0.06', '0.37', '0.0002', '0.75', '1.5', '-0.4', '2.5', '0.123', '12.25', '0.5'];
      const bounded = ['frac(in.x)', 'sin(in.t)', 'clamp(in.y, -2, 3)', 'mod(in.x, 3)', 'abs(sin(in.u)) * 40', 'min(max(in.k0, 0), 1)', 'mod(in.y, 1080)'];
      for (var n = 0; n < 150; n++) {
        final g = RandomProgram(rng);
        final e = g.expr(2, ['a']), f = g.expr(2, ['a']);
        final c = ['24', '0.3', '1080', '-7', '0.0625', '3'][rng.nextInt(6)];
        final src = [
          'let a = in.x * 0.5 + in.k1;',
          'let n = $c;',
          'let b = ($e) / n + mod(in.x, n);',
          'let s = smoothstep(${edges[rng.nextInt(edges.length)]}, $f);',
          'out.o0 = b * ($e) + cos(a) * sin(a + 0.25) - cos(a + 0.5);',
          'out.o1 = s * (1 - s) + ($f);',
          'out.o2 = ${bounded[rng.nextInt(bounded.length)]} / ${fracs[rng.nextInt(fracs.length)]};',
          'if (in.k2 > 0.5) {',
          '  out.o3 = ($e) * n - smoothstep(${edges[rng.nextInt(edges.length)]}, in.y);',
          '}',
        ].join('\n');
        checkProgram('passes $n', src, 0, rng, runs: 60, fast: fast);
      }
    });
  }
  test('400 random programs, fast', () {
    final rng = Random(20261012);
    final gen = RandomProgram(rng);
    for (var n = 0; n < 400; n++) {
      checkProgram('fast random #$n', gen.program(), 0, rng, runs: 40, fast: true);
    }
  });

  test('400 random programs', () {
    final rng = Random(20261011);
    final gen = RandomProgram(rng);
    for (var n = 0; n < 400; n++) {
      checkProgram('random #$n', gen.program(), 0, rng, runs: 40);
    }
  });
}
