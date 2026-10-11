// Where a stage spends its cycles (emulator model): per runtime routine and the stage body,
// averaged over random inputs.   dart run tool/profile.dart file.ss [--slot N] [--n 200]
import 'dart:io';
import 'dart:math';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:ae32k_shader_compiler/src/abi.dart';
import 'package:ae32k_shader_compiler/src/asm.dart';
import 'package:ae32k_shader_compiler/src/emu.dart';

void main(List<String> args) {
  String? opt(String n) => args.contains(n) ? args[args.indexOf(n) + 1] : null;
  final slot = int.parse(opt('--slot') ?? '0'), n = int.parse(opt('--n') ?? '200');
  final st = compileStage(File(args.first).readAsStringSync(), slot: slot);
  final labels = assemble(st.asm, slotAddr[slot]!).labels;
  // routine entry points (labels starting "__" without a further "_" suffix section)
  final entries = labels.entries.where((e) => RegExp(r'^__[a-z0-9]+$').hasMatch(e.key)).toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  String owner(int pc) {
    var o = 'stage';
    for (final e in entries) {
      if (e.value <= pc) o = e.key;
    }
    return o;
  }

  final prof = <int, int>{};
  final rng = Random(1);
  final runner = StageRunner(st.bytes, slot: slot);
  for (var k = 0; k < n; k++) {
    runner.run({
      'x': rng.nextInt(1920) << 16, 'y': rng.nextInt(1080) << 16, 'u': rng.nextInt(65536), 'v': rng.nextInt(65536),
      't': rng.nextInt(600 << 16), 'frame': rng.nextInt(10000) << 16, 'rnd': rng.nextInt(65536),
      'w': 1920 << 16, 'h': 1080 << 16,
      for (var j = 0; j < 8; j++) 'k$j': rng.nextInt(10 << 16) - (5 << 16),
      for (var j = 0; j < 4; j++) 'p$j': rng.nextInt(100 << 16),
    }, profile: prof);
  }
  final by = <String, int>{};
  prof.forEach((pc, h) => by[owner(pc)] = (by[owner(pc)] ?? 0) + h);
  final total = by.values.fold(0, (a, b) => a + b);
  stdout.writeln('${args.first}: ${(total / 2 / n).toStringAsFixed(0)} cycles/run, ${st.bytes.length} bytes');
  for (final e in by.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
    stdout.writeln('  ${e.key.padRight(10)} ${(e.value / 2 / n).toStringAsFixed(1).padLeft(8)}  ${(100 * e.value / total).toStringAsFixed(1).padLeft(5)}%');
  }
}
