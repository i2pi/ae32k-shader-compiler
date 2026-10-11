// Disassemble a raw ISPM image with the gas-verified decoder: disasm.dart <bin> <from> <to>
// (bin loaded at 0x10000000; e.g. objcopy -O binary -j .ispm hyb.elf).
import 'dart:io';
import 'package:ae32k_shader_compiler/src/isa.dart';
void main(List<String> a) {
  final b = File(a[0]).readAsBytesSync();
  final base = 0x10000000;
  final words = [for (var i = 0; i + 1 < b.length; i += 2) b[i] | b[i + 1] << 8];
  var i = (int.parse(a[1]) - base) >> 1;
  final end = (int.parse(a[2]) - base) >> 1;
  while (i < end) {
    final d = decode(words, i, base + 2 * i);
    final raw = words.sublist(i, i + d.length).map((w) => w.toRadixString(16).padLeft(4, '0')).join(' ');
    print('${(base + 2 * i).toRadixString(16)}  ${raw.padRight(20)} ${format(d.insn)}');
    i += d.length;
  }
}
