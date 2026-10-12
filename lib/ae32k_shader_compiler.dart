/// Compiles Scion shader stages to native AE32000 code for the MDIN's internal MCU.
library;

import 'src/abi.dart';
import 'src/asm.dart';
import 'src/codegen.dart';
import 'src/constprop.dart';
import 'src/cse.dart';
import 'src/lower.dart';
import 'src/lang/ast.dart';
import 'src/lang/parser.dart';
import 'src/registers.dart';

export 'src/abi.dart' show slotAddr, maxBlobBytes;
export 'src/analysis.dart' show analyzeStage, StageAnalysis, Diagnostic, LineCost, sampleInputs;
export 'src/lang/highlight.dart' show highlight, Highlight, TokenKind;
export 'src/codegen.dart' show CompileError;
export 'src/lang/ast.dart' show OutMapEntry, Program;
export 'src/lang/eval.dart' show evaluate;
export 'src/lang/parser.dart' show ShaderSyntaxError, parse;
export 'src/osc.dart' show oscMessage, oscNoArgTypes, stageParts, knobMessage, scanMapMessage, slotPath;
export 'src/registers.dart' show Register, parseRegisters, registers;

class CompiledStage {
  final int slot;
  final List<int> bytes; // padded to a multiple of 4
  final String asm;
  final List<OutMapEntry> outMap;

  /// The source line of every stage instruction, by address (0 for the prologue and epilogue);
  /// runtime routines are absent.
  final Map<int, int> sourceLines;

  /// The address of the instruction on each line of [asm] (1-based), for listings.
  final Map<int, int> asmAddr;
  const CompiledStage(this.slot, this.bytes, this.asm, this.outMap, [this.sourceLines = const {}, this.asmAddr = const {}]);

  /// Little-endian 32-bit words, as uploaded (`/send/1/shader/part`, `imcu hyb x`).
  List<int> get words => [
        for (var i = 0; i < bytes.length; i += 4)
          bytes[i] | bytes[i + 1] << 8 | bytes[i + 2] << 16 | bytes[i + 3] << 24,
      ];
}

/// Compiles [source] for [slot] (0 warp, 1 scan, 2 vertex). [fast] drops the saturation
/// of q_mul / q_div and the zero-divisor test: overflow wraps instead of clamping, and
/// x / 0 gives +-0x7fffffff instead of 0. Everything else is unchanged.
CompiledStage compileStage(String source, {int slot = 0, bool fast = false, Map<String, Register>? registers}) {
  final Program prog = parse(source, registers: registers);
  final lowered = lowerSmoothstep(eliminateCommon(propagateConstants(prog, fast: fast), fast: fast));
  // fewer register-resident locals when an expression runs out of registers, or when the
  // stage would not fit the upload (more locals on the stack can come out smaller)
  String? asm;
  Assembled? best;
  for (var homes = 6; homes >= 0; homes--) {
    final String a;
    try {
      a = CodeGen(lowered, regLocals: homes, fast: fast).generate();
    } on CompileError catch (e) {
      if ((homes == 0 && asm == null) || !e.message.contains('registers')) rethrow;
      continue;
    }
    final c = assemble(a, slotAddr[slot]!);
    int padded(Assembled x) => (x.bytes.length + 3) & ~3;
    if (best == null || (padded(best) > maxBlobBytes && padded(c) < padded(best))) {
      (asm, best) = (a, c);
    }
    if (padded(best) <= maxBlobBytes) break;
  }
  final code = best!, text = asm!;
  final bytes = [...code.bytes];
  while (bytes.length % 4 != 0) {
    bytes.add(0);
  }
  if (bytes.length > maxBlobBytes) {
    throw CompileError('stage is ${bytes.length} bytes; the upload limit is $maxBlobBytes');
  }
  final asmLines = text.split('\n');
  final firstRoutine = asmLines.indexWhere((l) => RegExp(r'^__\w+:').hasMatch(l));
  final tag = RegExp(r'// @L(\d+)');
  final sourceLines = <int, int>{
    for (final e in code.lineAddr.entries)
      if (firstRoutine < 0 || e.key <= firstRoutine) e.value: int.parse(tag.firstMatch(asmLines[e.key - 1])?.group(1) ?? '0'),
  };
  return CompiledStage(slot, bytes, text, prog.outMap, sourceLines, code.lineAddr);
}
