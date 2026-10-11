// The native compiler against the reference interpreter, in the emulator: the shader
// examples, the gcc corpus programs and random programs must give identical outputs.
import 'dart:io';
import 'dart:math';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
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
