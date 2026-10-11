/// Compiles Scion shader stages to native AE32000 code for the MDIN's internal MCU.
library;

import 'src/abi.dart';
import 'src/asm.dart';
import 'src/codegen.dart';
import 'src/lang/ast.dart';
import 'src/lang/parser.dart';
import 'src/registers.dart';

export 'src/abi.dart' show slotAddr, maxBlobBytes;
export 'src/codegen.dart' show CompileError;
export 'src/lang/ast.dart' show OutMapEntry;
export 'src/lang/parser.dart' show ShaderSyntaxError;
export 'src/registers.dart' show Register, parseRegisters, registers;

class CompiledStage {
  final int slot;
  final List<int> bytes; // padded to a multiple of 4
  final String asm;
  final List<OutMapEntry> outMap;
  const CompiledStage(this.slot, this.bytes, this.asm, this.outMap);

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
  // fewer register-resident locals when an expression runs out of registers
  String? asm;
  for (final homes in [6, 3, 0]) {
    try {
      asm = CodeGen(prog, regLocals: homes, fast: fast).generate();
      break;
    } on CompileError catch (e) {
      if (homes == 0 || !e.message.contains('registers')) rethrow;
    }
  }
  final code = assemble(asm!, slotAddr[slot]!);
  final bytes = [...code.bytes];
  while (bytes.length % 4 != 0) {
    bytes.add(0);
  }
  if (bytes.length > maxBlobBytes) {
    throw CompileError('stage is ${bytes.length} bytes; the upload limit is $maxBlobBytes');
  }
  return CompiledStage(slot, bytes, asm, prog.outMap);
}
