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

void checkProgram(String name, String src, int slot, Random rng, {int runs = 100}) {
  final prog = parse(src);
  final CompiledStage st;
  try {
    st = compileStage(src, slot: slot);
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
    final want = evaluate(prog, inputs, init);
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
  test('400 random programs', () {
    final rng = Random(20261011);
    final gen = RandomProgram(rng);
    for (var n = 0; n < 400; n++) {
      checkProgram('random #$n', gen.program(), 0, rng, runs: 40);
    }
  });
}
