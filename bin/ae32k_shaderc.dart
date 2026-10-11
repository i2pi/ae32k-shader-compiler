// ae32k_shaderc: compile a Scion shader stage to native AE32000 code (no gcc, no Wine),
// optionally check it in the emulator and upload it over OSC.
//
//   dart run bin/ae32k_shaderc.dart file.ss [--scan | --vert | --slot N] [--asm] [--out f.bin]
//                                   [--check N] [--osc] [--host IP] [--port P] [--knobs a,b,..]
// Same slots and upload as tools/imcu/shader.py: warp = slot 0 (default), --scan = 1, --vert = 2.
import 'dart:io';
import 'dart:math';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:ae32k_shader_compiler/src/emu.dart';
import 'package:ae32k_shader_compiler/src/lang/eval.dart';
import 'package:ae32k_shader_compiler/src/lang/parser.dart';
import 'package:ae32k_shader_compiler/upload.dart';

const usage = '''usage: ae32k_shaderc <file.ss> [options]
  --scan / --vert / --slot N   target slot (default 0, the warp stage)
  --asm                        print the generated assembly
  --out FILE                   write the blob (little-endian words, as uploaded)
  --check N                    run N random evaluations in the emulator against the reference
  --osc                        upload over OSC (/send/1/shader/part...) to --host (\$SCION_IP)
  --host IP  --port P          default 192.168.100.221:9000
  --knobs a,b,...              knob values sent after the upload''';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    stderr.writeln(usage);
    exit(args.isEmpty ? 64 : 0);
  }
  String? opt(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final file = args.first;
  final slot = args.contains('--vert') ? 2 : args.contains('--scan') ? 1 : int.parse(opt('--slot') ?? '0');
  final src = File(file).readAsStringSync();
  final CompiledStage st;
  try {
    st = compileStage(src, slot: slot);
  } on ShaderSyntaxError catch (e) {
    stderr.writeln('$file: $e');
    exit(1);
  } on CompileError catch (e) {
    stderr.writeln('$file: $e');
    exit(1);
  }
  if (args.contains('--asm')) stdout.write(st.asm);
  stdout.writeln('stage: ${st.bytes.length} bytes, ${st.words.length} words, slot $slot');
  if (st.outMap.isNotEmpty) {
    stdout.writeln('output map: ${st.outMap.length} entries');
  }
  final out = opt('--out');
  if (out != null) File(out).writeAsBytesSync(st.bytes);

  final checks = int.tryParse(opt('--check') ?? '') ?? 0;
  if (checks > 0) {
    final prog = parse(src);
    final runner = StageRunner(st.bytes, slot: slot);
    final rng = Random(1);
    var worst = 0;
    for (var n = 0; n < checks; n++) {
      final inputs = {
        'x': rng.nextInt(1920) << 16, 'y': rng.nextInt(1080) << 16, 'u': rng.nextInt(65536),
        'v': rng.nextInt(65536), 't': rng.nextInt(600 << 16), 'frame': rng.nextInt(10000) << 16,
        'rnd': rng.nextInt(65536), 'w': 1920 << 16, 'h': 1080 << 16,
        for (var k = 0; k < 8; k++) 'k$k': rng.nextInt(10 << 16) - (5 << 16),
        for (var k = 0; k < 4; k++) 'p$k': rng.nextInt(100 << 16),
      };
      final init = List.filled(16, 0);
      for (final e in prog.outMap) {
        if (e.mode == 1) init[e.slot] = 65536;
      }
      final stats = <String, int>{};
      final got = runner.run(inputs, outInit: init, stats: stats);
      final want = evaluate(prog, inputs, init);
      if (got.join(',') != want.join(',')) {
        stderr.writeln('check FAILED for inputs $inputs:\n  native    $got\n  reference $want');
        exit(2);
      }
      worst = max(worst, stats['cycles']!);
    }
    stdout.writeln('check: $checks evaluations match the reference; at most $worst cycles (emulator estimate)');
  }

  if (args.contains('--osc')) {
    final host = opt('--host') ?? Platform.environment['SCION_IP'] ?? '192.168.100.221';
    final port = int.parse(opt('--port') ?? '9000');
    final knobs = opt('--knobs')?.split(',').map(double.parse).toList();
    final n = await uploadStage(st, host, port: port, knobs: knobs);
    stdout.writeln('sent over OSC: $n bytes to $host:$port (check `imcu tiles stat` / `imcu scan stat` for the armed size)');
  }
}
