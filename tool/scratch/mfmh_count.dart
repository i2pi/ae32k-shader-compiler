import 'dart:io';
import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
void main(List<String> a) {
  var n = 0, inl = 0;
  for (final p in a) {
    for (final fast in [false, true]) {
      try {
        final asm = compileStage(File(p).readAsStringSync(), fast: fast).asm;
        final i = asm.indexOf('\n__qmul:');
        final body = i < 0 ? asm : asm.substring(0, i);
        n++;
        if (body.contains('mfmh')) inl++;
      } catch (_) {}
    }
  }
  print('$inl of $n builds use the inline mfmh');
}
