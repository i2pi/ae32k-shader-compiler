import 'dart:io';
import 'package:ae32k_shader_compiler/src/codegen.dart';
import 'package:ae32k_shader_compiler/src/constprop.dart';
import 'package:ae32k_shader_compiler/src/lower.dart';
import 'package:ae32k_shader_compiler/src/cse.dart';
import 'package:ae32k_shader_compiler/src/lang/parser.dart';
void main(List<String> a) {
  print(CodeGen(lowerSmoothstep(eliminateCommon(propagateConstants(parse(File(a[0]).readAsStringSync())))), regLocals: int.parse(a[1])).generate());
}
