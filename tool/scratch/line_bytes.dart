import 'dart:io';
import 'package:ae32k_shader_compiler/src/asm.dart';
import 'package:ae32k_shader_compiler/src/codegen.dart';
import 'package:ae32k_shader_compiler/src/constprop.dart';
import 'package:ae32k_shader_compiler/src/lower.dart';
import 'package:ae32k_shader_compiler/src/cse.dart';
import 'package:ae32k_shader_compiler/src/lang/parser.dart';

void main(List<String> a) {
  final src = File(a[0]).readAsStringSync();
  final slot = int.parse(a[1]);
  final asm = CodeGen(lowerSmoothstep(eliminateCommon(propagateConstants(parse(src)))), regLocals: int.parse(a[2])).generate();
  final code = assemble(asm, 0x1000A000);
  print('total ${code.bytes.length}');
  final lines = asm.split('\n');
  final per = <String, int>{};
  final addrs = code.lineAddr.entries.toList()..sort((x, y) => x.key.compareTo(y.key));
  for (var i = 0; i < addrs.length; i++) {
    final end = i + 1 < addrs.length ? addrs[i + 1].value : 0x1000A000 + code.bytes.length;
    final l = lines[addrs[i].key - 1];
    final m = RegExp(r'@L(\d+)').firstMatch(l);
    final key = m != null ? 'L${m[1]}' : (RegExp(r'^__\w+:').hasMatch(l) ? l : '?');
    per[key] = (per[key] ?? 0) + end - addrs[i].value;
  }
  final cur = <String, int>{};
  String sect = 'body';
  for (var i = 0; i < addrs.length; i++) {
    final end = i + 1 < addrs.length ? addrs[i + 1].value : 0x1000A000 + code.bytes.length;
    final l = lines[addrs[i].key - 1];
    final r = RegExp(r'^(__[a-z0-9]+):').firstMatch(l);
    if (r != null) sect = r[1]!;
    final m = RegExp(r'@L(\d+)').firstMatch(l);
    final key = sect != 'body' ? sect : (m != null ? 'L${m[1]}' : 'other');
    cur[key] = (cur[key] ?? 0) + end - addrs[i].value;
  }
  final sl = src.split('\n');
  for (final e in cur.entries) {
    final t = e.key.startsWith('L') ? sl[int.parse(e.key.substring(1)) - 1].trim() : '';
    print('${e.value.toString().padLeft(5)} ${e.key} ${t.length > 90 ? t.substring(0, 90) : t}');
  }
}
