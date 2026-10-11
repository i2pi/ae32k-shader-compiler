import 'package:ae32k_shader_compiler/src/lang/eval.dart';
import 'package:ae32k_shader_compiler/src/lang/parser.dart';
import 'package:test/test.dart';

void main() {
  test('else and else if parse (shader.py rejects them)', () {
    final p = parse('if (in.u > 0.5) { out.dx = 1; } else if (in.u > 0.25) { out.dx = 2; } else { out.dx = 3; }');
    expect(evaluate(p, {'u': 40000})[0], 65536);
    expect(evaluate(p, {'u': 20000})[0], 2 * 65536);
    expect(evaluate(p, {'u': 100})[0], 3 * 65536);
  });
  test('constants beyond the Q16 range are refused', () {
    expect(() => parse('out.dx = 65535.5;'), throwsA(isA<ShaderSyntaxError>()));
    expect(parse('out.dx = 32767.99998;').body, hasLength(1));
  });
  test('constants round half to even, as Python round()', () {
    expect(q16(0.5 / 65536), 0);
    expect(q16(1.5 / 65536), 2);
    expect(q16(2.5 / 65536), 2);
  });
  test('errors carry line numbers', () {
    expect(() => parse('let a = 1;\nout.dx = in.nope;'), throwsA(predicate((e) => '$e'.contains('line 2'))));
  });
}
