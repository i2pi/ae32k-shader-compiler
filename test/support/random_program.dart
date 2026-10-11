// Random shader programs for differential tests: every operator and function, locals,
// nested ifs with else, outputs read back, and constants at awkward magnitudes.
import 'dart:math';

import 'package:ae32k_shader_compiler/src/lang/parser.dart' show functions;

const _inputs = ['x', 'y', 'u', 'v', 't', 'frame', 'rnd', 'w', 'h', 'k0', 'k1', 'k2', 'k3', 'heat', 'mvx', 'mvy', 'p0', 'p1'];
const _bin = ['+', '-', '*', '/', '%', '<', '<=', '>', '>=', '==', '!=', '&&', '||'];
const _consts = ['0', '1', '2', '0.5', '0.25', '3.75', '100', '0.001', '1920', '0.0001', '7', '32767', '32767.99998'];

class RandomProgram {
  final Random rng;
  RandomProgram(this.rng);

  String expr(int depth, List<String> locals) {
    if (depth <= 0 || rng.nextDouble() < 0.25) {
      final k = rng.nextDouble();
      if (k < 0.45) return 'in.${_inputs[rng.nextInt(_inputs.length)]}';
      if (k < 0.6 && locals.isNotEmpty) return locals[rng.nextInt(locals.length)];
      if (k < 0.65) return rng.nextBool() ? 'pi' : 'tau';
      if (k < 0.7) return 'out.o${rng.nextInt(4)}';
      return _consts[rng.nextInt(_consts.length)];
    }
    final k = rng.nextDouble();
    if (k < 0.45) return '(${expr(depth - 1, locals)} ${_bin[rng.nextInt(_bin.length)]} ${expr(depth - 1, locals)})';
    if (k < 0.55) return '${rng.nextBool() ? '-' : '!'}${expr(depth - 1, locals)}';
    final names = functions.keys.toList()..sort();
    final f = names[rng.nextInt(names.length)];
    return '$f(${[for (var i = 0; i < functions[f]!; i++) expr(depth - 1, locals)].join(', ')})';
  }

  String block(int depth, List<String> locals, int indent) {
    final pad = '  ' * indent;
    final out = StringBuffer();
    for (var n = 0; n < 1 + rng.nextInt(3); n++) {
      final r = rng.nextDouble();
      if (r < 0.2 && depth > 0) {
        out.writeln('${pad}if (${expr(2, locals)}) {');
        out.write(block(depth - 1, locals, indent + 1));
        if (rng.nextBool()) {
          out.writeln('$pad} else {');
          out.write(block(depth - 1, locals, indent + 1));
        }
        out.writeln('$pad}');
      } else if (r < 0.45 && locals.isNotEmpty) {
        out.writeln('$pad${locals[rng.nextInt(locals.length)]} = ${expr(3, locals)};');
      } else {
        out.writeln('${pad}out.o${rng.nextInt(6)} = ${expr(1 + rng.nextInt(4), locals)};');
      }
    }
    return out.toString();
  }

  String program() {
    final locals = <String>[];
    final out = StringBuffer();
    for (var n = 0; n < rng.nextInt(9); n++) {
      final name = 'l$n';
      out.writeln('let $name = ${expr(1 + rng.nextInt(3), locals)};');
      locals.add(name);
    }
    out.write(block(2, locals, 0));
    return out.toString();
  }
}
