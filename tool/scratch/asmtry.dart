import 'package:ae32k_shader_compiler/src/asm.dart';
void main() {
  for (final s in ['min %R2,%R1', 'max %R2,%R1', 'abs %R1', 'min 3,%R1', 'max 65536,%R1', 'min -1,%R1', 'mul %R2,%R0', 'mfmh %R3', 'mfml %R3', 'mulu %R2,%R0']) {
    try { final a = assemble('    $s\n', 0x1000C000); print('$s -> ${a.bytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join(' ')}'); } catch (e) { print('$s !! $e'); }
  }
}
