// Shader IDE: edit a Scion shader stage, see compile errors and per-line cycle costs as you type,
// and upload it to a SCION over OSC. The compiler is ae32k_shader_compiler (pure Dart).
import 'package:flutter/material.dart';

import 'ide_page.dart';
import 'theme.dart';

void main() => runApp(const ShaderIde());

class ShaderIde extends StatelessWidget {
  const ShaderIde({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Shader IDE',
        debugShowCheckedModeBanner: false,
        theme: Sc.theme(),
        home: const IdePage(),
      );
}
