// Per-stage event counts from the emulator next to the device cycles from a hw_bench
// --stages log, as JSON lines for fitting the cycle model: LOG=bench.txt dart run tool/fit_events.dart
import 'dart:convert';
import 'dart:io';
import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:ae32k_shader_compiler/src/emu.dart';
const hookInputs = {
  'x': 960 << 16, 'y': 540 << 16, 'u': 0x8000, 'v': 0x8000, 't': 0x10000, 'frame': 0x10000,
  'rnd': 0x4000, 'w': 1920 << 16, 'h': 1080 << 16, 'p0': 0x8000, 'p1': 0x8000, 'p2': 0x8000, 'p3': 0x8000,
};
void main() {
  for (final l in File(Platform.environment['LOG']!).readAsLinesSync()) {
    final m = RegExp(r'^(\S+)/(native|gcc)\s+\d+\s+([\d.]+)\s+match').firstMatch(l);
    if (m == null) continue;
    final blob = m[2] == 'gcc' ? File('test/golden/gcc/${m[1]}.bin').readAsBytesSync()
        : compileStage(File('test/golden/gcc/${m[1]}.ss').readAsStringSync(), slot: 0).bytes;
    final st = <String, int>{};
    StageRunner(blob, slot: 0).run(hookInputs, stats: st);
    print(jsonEncode({'name': '${m[1]}/${m[2]}', 'hw': double.parse(m[3]!) + 1, ...st}));
  }
}
