// Where a set of stages spends its cycles (emulator, device-fitted model): totals per runtime
// routine, and the stage bodies by instruction kind. For judging an optimisation on many shapes.
//
//   dart run tool/corpus_profile.dart [--fast] [--n 40] dir-or-files...
// Slot from the file name: v* -> vertex (2), s* or an @out map -> scan (1), else warp (0).
import 'dart:io';
import 'dart:math';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:ae32k_shader_compiler/src/asm.dart';
import 'package:ae32k_shader_compiler/src/emu.dart';
import 'package:ae32k_shader_compiler/src/isa.dart';

void main(List<String> args) {
  final fast = args.contains('--fast');
  final ni = args.indexOf('--n');
  final n = ni >= 0 ? int.parse(args[ni + 1]) : 40;
  final files = <File>[
    for (final a in args.where((a) => !a.startsWith('--') && (ni < 0 || a != args[ni + 1])))
      if (FileSystemEntity.isDirectorySync(a))
        ...Directory(a).listSync().whereType<File>().where((f) => f.path.endsWith('.ss'))
      else
        File(a),
  ]..sort((a, b) => a.path.compareTo(b.path));
  final routines = <String, int>{}, kinds = <String, int>{};
  var total = 0, bytes = 0;
  for (final f in files) {
    final src = f.readAsStringSync(), base = f.uri.pathSegments.last;
    final slot = base.startsWith('v') ? 2 : (base.startsWith('s') || src.contains('@out') ? 1 : 0);
    final st = compileStage(src, slot: slot, fast: fast);
    bytes += st.bytes.length;
    final labels = assemble(st.asm, slotAddr[slot]!).labels;
    final entries = labels.entries.where((e) => RegExp(r'^__[a-z0-9]+$').hasMatch(e.key)).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final words = [for (var i = 0; i + 1 < st.bytes.length; i += 2) st.bytes[i] | st.bytes[i + 1] << 8];
    final prof = <int, int>{};
    final rng = Random(1);
    final runner = StageRunner(st.bytes, slot: slot);
    for (var k = 0; k < n; k++) {
      runner.run({
        'x': rng.nextInt(1920) << 16, 'y': rng.nextInt(1080) << 16, 'u': rng.nextInt(65536), 'v': rng.nextInt(65536),
        't': rng.nextInt(600 << 16), 'frame': rng.nextInt(10000) << 16, 'rnd': rng.nextInt(65536),
        'w': 1920 << 16, 'h': 1080 << 16,
        for (var j = 0; j < 8; j++) 'k$j': rng.nextInt(2 << 16),
        for (var j = 0; j < 4; j++) 'p$j': rng.nextInt(100 << 16),
      }, profile: prof);
    }
    prof.forEach((pc, h) {
      var owner = 'stage';
      for (final e in entries) {
        if (e.value <= pc) owner = e.key;
      }
      routines[owner] = (routines[owner] ?? 0) + h;
      total += h;
      if (owner == 'stage') {
        final i = decode(words, (pc - slotAddr[slot]!) >> 1).insn;
        final k = i.m == 'lea' && i.imm == 0 ? 'move' : i.m;
        kinds[k] = (kinds[k] ?? 0) + h;
      }
    });
  }
  final per = 2.0 * n * files.length; // half-cycles -> cycles per stage call
  stdout.writeln('${files.length} stages${fast ? ' (--fast)' : ''}: mean ${(total / per).toStringAsFixed(1)} cycles per call, '
      'mean ${(bytes / files.length).toStringAsFixed(0)} bytes');
  for (final e in routines.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
    stdout.writeln('  ${e.key.padRight(10)} ${(e.value / per).toStringAsFixed(1).padLeft(7)}  ${(100 * e.value / total).toStringAsFixed(1).padLeft(5)}%');
  }
  final body = routines['stage'] ?? 1;
  stdout.writeln('  stage body by instruction:');
  for (final e in (kinds.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(14)) {
    stdout.writeln('    ${e.key.padRight(8)} ${(e.value / per).toStringAsFixed(1).padLeft(7)}  ${(100 * e.value / body).toStringAsFixed(1).padLeft(5)}%');
  }
}
