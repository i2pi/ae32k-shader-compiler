import 'package:flutter_test/flutter_test.dart';
import 'package:shader_ide/completion.dart';

List<String> labels(String src, int slot, [int? at]) =>
    complete(src, at ?? src.length, slot)?.items.map((c) => c.label).toList() ?? const [];

void main() {
  test('in. lists the stage inputs', () {
    expect(labels('out.dx = in.', 0), containsAll(['x', 'y', 'u', 'v', 't', 'heat', 'k0']));
    expect(labels('out.dx = in.', 2), isNot(contains('y'))); // vertex: index in x, no y
    expect(labels('out.dx = in.', 1), containsAll(['p0', 'p3']));
    expect(labels('out.dx = in.k', 0), ['k0', 'k1', 'k2', 'k3', 'k4', 'k5', 'k6', 'k7']);
  });

  test('out. lists outputs: built-in per stage, @out names for scan', () {
    expect(labels('out.', 0), ['dx', 'dy']);
    expect(labels('out.', 2), ['vx', 'vy', 'p0', 'p1', 'p2', 'p3']);
    expect(labels('@out gy out0_csc_y0 gain\n@out gy out0_csc_y1\n@out sw in_swap\nout.', 1), ['gy', 'sw']);
  });

  test('@out lines: register names, then modes', () {
    expect(labels('@out sw in_sw', 1), contains('in_swap'));
    expect(labels('@out g out0_csc_y0 ga', 1), ['gain']);
    expect(labels('@out g', 1), isEmpty); // still typing the output's name
  });

  test('identifiers: functions with signatures, keywords, locals, constants', () {
    expect(labels('let a = s', 0), containsAll(['sin(x)', 'sqrt(x)', 'smoothstep(e0, e1, x)', 'step(edge, x)', 'sign(x)']));
    expect(labels('let speed = 1;\nout.dx = sp', 0), contains('speed'));
    expect(labels('l', 0), contains('let'));
    expect(labels('out.dx = p', 0), contains('pi'));
    final sin = complete('let a = si', 10, 0)!.items.firstWhere((c) => c.label == 'sin(x)');
    expect((sin.insert, sin.caret), ('sin()', 4));
  });

  test('nothing in comments or numbers', () {
    expect(complete('// si', 5, 0), isNull);
    expect(complete('let a = 12', 10, 0), isNull);
  });
}
