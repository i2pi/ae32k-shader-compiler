// The emulator against gcc: every blob in test/golden/gcc/ (tool/gen_gcc_corpus.py,
// compiled the current way, shader.py -> C -> Wine gcc) must produce exactly the outputs
// of the Dart reference interpreter for random inputs. A mismatch means the emulator,
// the reference or the Q16 port is wrong; none of them is trusted alone.
import 'dart:io';
import 'dart:math';

import 'package:ae32k_shader_compiler/src/emu.dart';
import 'package:ae32k_shader_compiler/src/lang/eval.dart';
import 'package:ae32k_shader_compiler/src/lang/parser.dart';
import 'package:test/test.dart';

/// Inputs like the resident's: positions in px and 0..1, time, knobs, and a share of
/// extreme values (overflow, saturation, sign edges).
Map<String, int> randomInputs(Random rng) {
  int q(double v) => (v * 65536).round();
  int wild() => switch (rng.nextInt(6)) {
        0 => 0,
        1 => -0x80000000,
        2 => 0x7fffffff,
        3 => rng.nextInt(0x100000000) - 0x80000000,
        4 => q(rng.nextDouble() * 4 - 2),
        _ => q(rng.nextDouble() * 4000 - 2000),
      };
  final px = rng.nextInt(1920), py = rng.nextInt(1080);
  final m = <String, int>{
    'x': px << 16, 'y': py << 16, 'u': (px << 16) ~/ 1920, 'v': (py << 16) ~/ 1080,
    't': q(rng.nextDouble() * 600), 'frame': rng.nextInt(100000) << 16,
    'rnd': rng.nextInt(0x10000), 'w': 1920 << 16, 'h': 1080 << 16,
    for (var k = 0; k < 8; k++) 'k$k': q(rng.nextDouble() * 10 - 5),
    'heat': rng.nextInt(0x10000), 'mvx': q(rng.nextDouble() * 64 - 32), 'mvy': q(rng.nextDouble() * 64 - 32),
    for (var k = 0; k < 4; k++) 'p$k': q(rng.nextDouble() * 100),
  };
  if (rng.nextInt(4) == 0) {
    for (final k in m.keys.toList()) {
      if (rng.nextInt(3) == 0) m[k] = wild();
    }
  }
  return m;
}

void main() {
  final dir = Directory('test/golden/gcc');
  final manifest = File('${dir.path}/manifest.txt').readAsLinesSync().where((l) => l.isNotEmpty);
  for (final line in manifest) {
    final f = line.split('\t');
    final name = f[0], slot = int.parse(f[1]);
    test('gcc $name matches the reference', () {
      final src = File('${dir.path}/$name.ss').readAsStringSync();
      final prog = parse(src);
      final runner = StageRunner(File('${dir.path}/$name.bin').readAsBytesSync(), slot: slot);
      final rng = Random(name.hashCode);
      var maxCycles = 0;
      for (var n = 0; n < 200; n++) {
        final inputs = randomInputs(rng);
        // the resident starts outputs at 0, or 1.0 for gain-mapped scan outputs
        final init = List.filled(16, 0);
        for (final e in prog.outMap) {
          if (e.mode == 1) init[e.slot] = 65536;
        }
        final stats = <String, int>{};
        final got = runner.run(inputs, outInit: init, stats: stats);
        final want = evaluate(prog, inputs, init);
        maxCycles = max(maxCycles, stats['cycles']!);
        expect(got, want, reason: 'inputs ${_show(inputs)}');
      }
      printOnFailure('$name: max $maxCycles cycles');
    });
  }
}

String _show(Map<String, int> m) => m.entries.map((e) => '${e.key}=${e.value}').join(' ');
