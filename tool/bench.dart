// Native compiler vs gcc on the corpus: blob size and emulated cycles per evaluation
// (mean over the same random inputs). The cycle model is the emulator's estimate, not
// a hardware measurement.
//   dart run tool/bench.dart
import 'dart:io';
import 'dart:math';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:ae32k_shader_compiler/src/emu.dart';

import '../test/emu_gcc_test.dart' show randomInputs;

void main() {
  final dir = 'test/golden/gcc';
  var sumG = 0.0, sumN = 0.0, sizeG = 0, sizeN = 0, n = 0;
  final rows = <String>[];
  for (final line in File('$dir/manifest.txt').readAsLinesSync().where((l) => l.isNotEmpty)) {
    final f = line.split('\t');
    final name = f[0], slot = int.parse(f[1]);
    final gccBlob = File('$dir/$name.bin').readAsBytesSync();
    final nat = compileStage(File('$dir/$name.ss').readAsStringSync(), slot: slot);
    final g = StageRunner(gccBlob, slot: slot), t = StageRunner(nat.bytes, slot: slot);
    final rng = Random(7);
    var cg = 0, cn = 0;
    const runs = 50;
    for (var k = 0; k < runs; k++) {
      final inp = randomInputs(rng);
      final sg = <String, int>{}, sn = <String, int>{};
      g.run(inp, stats: sg);
      t.run(inp, stats: sn);
      cg += sg['cycles']!;
      cn += sn['cycles']!;
    }
    sumG += cg / runs;
    sumN += cn / runs;
    sizeG += gccBlob.length;
    sizeN += nat.bytes.length;
    n++;
    if (!name.startsWith('rand')) {
      rows.add('${name.padRight(12)} ${'${gccBlob.length}'.padLeft(6)} ${'${nat.bytes.length}'.padLeft(6)}'
          ' ${(cg / runs).toStringAsFixed(0).padLeft(8)} ${(cn / runs).toStringAsFixed(0).padLeft(8)}'
          ' ${(cg / cn).toStringAsFixed(2).padLeft(6)}x');
    }
  }
  print('${'stage'.padRight(12)} ${'gcc B'.padLeft(6)} ${'ours B'.padLeft(6)} ${'gcc cyc'.padLeft(8)} ${'our cyc'.padLeft(8)} speedup');
  rows.forEach(print);
  print('all $n programs: size ${sizeG ~/ n} -> ${sizeN ~/ n} B mean, cycles ${(sumG / n).toStringAsFixed(0)} -> ${(sumN / n).toStringAsFixed(0)} mean');
}
