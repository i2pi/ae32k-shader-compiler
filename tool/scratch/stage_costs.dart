// Mean cycles per stage over a set of example files; slot from content (out.vx -> vertex, @out -> scan, else warp).
import 'dart:io';
import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';

void main(List<String> args) {
  final fast = args.contains('--fast');
  final lines = args.contains('--lines');
  final files = <File>[
    for (final a in args.where((a) => !a.startsWith('--')))
      if (FileSystemEntity.isDirectorySync(a))
        ...Directory(a).listSync().whereType<File>().where((f) => f.path.endsWith('.ss'))
      else File(a),
  ]..sort((a, b) => a.path.compareTo(b.path));
  var tot = 0.0;
  for (final f in files) {
    final src = f.readAsStringSync();
    final slot = RegExp(r'out\.vx\b').hasMatch(src) ? 2 : (src.contains('@out') ? 1 : 0);
    final a = analyzeStage(src, slot: slot, fast: fast, samples: 64);
    final name = f.path.split('/').reversed.take(2).toList().reversed.join('/');
    if (!a.ok) { print('$name  ERR ${a.diagnostics.first}'); continue; }
    tot += a.meanCycles;
    final errs = a.diagnostics.where((d) => d.isError).map((d) => d.message).join('; ');
    print('${name.padRight(34)} s$slot ${a.meanCycles.toStringAsFixed(0).padLeft(6)} ${a.minCycles.toString().padLeft(5)}-${a.maxCycles.toString().padRight(5)} ${a.stage!.bytes.length.toString().padLeft(5)}B $errs');
    if (lines) {
      final sl = src.split('\n');
      final ks = a.lines.keys.toList()..sort();
      for (final l in ks) {
        final c = a.lines[l]!;
        if (c.cycles < 3) continue;
        print('    ${c.cycles.toStringAsFixed(0).padLeft(5)}  L$l ${l == 0 ? '(entry/exit)' : sl[l - 1].trim()}');
      }
    }
  }
  print('total ${tot.toStringAsFixed(0)}');
}
