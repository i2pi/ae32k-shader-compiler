// What an editor needs on every keystroke, in pure Dart (any platform, including the web):
// diagnostics with positions, the compiled stage, and its cycle cost per source line from the
// device-fitted emulator over sample inputs.
import 'dart:math';

import '../ae32k_shader_compiler.dart';
import 'asm.dart' show AsmError;
import 'emu.dart';
import 'lang/eval.dart';
import 'lang/parser.dart';

class Diagnostic {
  final String message;

  /// 1-based; null when the problem has no position (e.g. a stage over the size limit).
  final int? line, column;
  final bool isError;
  const Diagnostic(this.message, {this.line, this.column, this.isError = true});
  @override
  String toString() => line == null ? message : 'line $line${column == null ? '' : ':$column'}: $message';
}

class LineCost {
  /// Mean cycles per evaluation spent on this line, including runtime routines it calls.
  final double cycles;

  /// Fraction of the sample evaluations in which the line ran at all (lines inside an `if`).
  final double ran;
  const LineCost(this.cycles, this.ran);
}

class StageAnalysis {
  final List<Diagnostic> diagnostics;
  final CompiledStage? stage;

  /// Source line -> cost; line 0 is the stage's entry and exit (register saves, return).
  final Map<int, LineCost> lines;
  final double meanCycles;
  final int minCycles, maxCycles, samples;

  /// Mean cycles per evaluation spent at each instruction address (stage and routines).
  final Map<int, double> pcCycles;
  const StageAnalysis(this.diagnostics, this.stage, this.lines, this.meanCycles, this.minCycles, this.maxCycles, this.samples,
      [this.pcCycles = const {}]);
  bool get ok => stage != null;
}

/// Sample inputs like the resident's for [slot]: pixel positions for warp and scan, point
/// indices for the vertex stage. [fixed] overrides any input (e.g. the live knob values).
Map<String, int> sampleInputs(Random rng, int slot, [Map<String, int> fixed = const {}]) {
  final px = rng.nextInt(1920), py = rng.nextInt(1080), idx = rng.nextInt(96);
  return {
    if (slot == 2) ...{'x': idx << 16, 'y': 0, 'u': (idx << 16) ~/ 96, 'v': 0}
    else ...{'x': px << 16, 'y': py << 16, 'u': (px << 16) ~/ 1920, 'v': (py << 16) ~/ 1080},
    't': rng.nextInt(600 << 16), 'frame': rng.nextInt(36000) << 16, 'rnd': rng.nextInt(65536),
    'w': 1920 << 16, 'h': 1080 << 16,
    for (var k = 0; k < 8; k++) 'k$k': 0,
    for (var k = 0; k < 4; k++) 'p$k': rng.nextInt(4) << 16,
    ...fixed,
  };
}

/// Compiles [source] and measures it. Never throws: problems come back as [Diagnostic]s.
StageAnalysis analyzeStage(String source,
    {int slot = 0, bool fast = false, Map<String, Register>? registers, int samples = 24, Map<String, int> fixed = const {}}) {
  final CompiledStage st;
  try {
    st = compileStage(source, slot: slot, fast: fast, registers: registers);
  } on ShaderSyntaxError catch (e) {
    return StageAnalysis([Diagnostic(e.message, line: e.line, column: e.column)], null, const {}, 0, 0, 0, 0);
  } on CompileError catch (e) {
    return StageAnalysis([Diagnostic(e.message)], null, const {}, 0, 0, 0, 0);
  } on AsmError catch (e) {
    return StageAnalysis([Diagnostic('internal: $e')], null, const {}, 0, 0, 0, 0);
  }
  final diags = <Diagnostic>[];
  final prog = parse(source, registers: registers);
  if (slot == 1 && prog.outMap.isEmpty) {
    diags.add(const Diagnostic('a scan stage without @out lines writes no registers', isError: false));
  }
  final init = List.filled(16, 0);
  for (final e in prog.outMap) {
    if ((e.mode & 15) == 1) init[e.slot] = 65536;
  }
  final runner = StageRunner(st.bytes, slot: slot);
  final rng = Random(1);
  final half = <int, int>{}, ranIn = <int, int>{}, pcHalf = <int, int>{};
  var total = 0, lo = 1 << 30, hi = 0;
  for (var n = 0; n < samples; n++) {
    final inputs = sampleInputs(rng, slot, fixed);
    final lineHalf = <int, int>{}, stats = <String, int>{};
    try {
      final got = runner.run(inputs, outInit: init, stats: stats, lineOf: st.sourceLines, lineHalf: lineHalf, profile: pcHalf);
      final want = evaluate(prog, inputs, init, fast);
      if (got.join(',') != want.join(',')) {
        diags.add(Diagnostic('internal: the native code disagrees with the reference for inputs $inputs'));
        break;
      }
    } on EmuError catch (e) {
      diags.add(Diagnostic('internal: $e'));
      break;
    }
    lineHalf.forEach((l, h) {
      half[l] = (half[l] ?? 0) + h;
      ranIn[l] = (ranIn[l] ?? 0) + 1;
    });
    final c = stats['cycles']!;
    total += c;
    lo = min(lo, c);
    hi = max(hi, c);
  }
  final lines = {for (final l in half.keys) l: LineCost(half[l]! / 2 / samples, ranIn[l]! / samples)};
  final pcs = {for (final e in pcHalf.entries) e.key: e.value / 2 / samples};
  return StageAnalysis(diags, st, lines, total / samples, samples == 0 ? 0 : lo, hi, samples, pcs);
}
