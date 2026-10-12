// Named @out lines (`@out <output> <name> [mode]`, rows of zephyr_scion tools/imcu/registers.inc):
// the compiled-in table must match the repo's file, and every example's output map must match
// what shader.py (the reference front end) builds, byte for byte.
import 'dart:convert';
import 'dart:io';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:ae32k_shader_compiler/src/lang/parser.dart';
import 'package:ae32k_shader_compiler/src/registers_inc.dart';
import 'package:test/test.dart';

const imcu = '../../tools/imcu';

void main() {
  test('compiled-in registers.inc is current (dart run tool/gen_registers.dart)', () {
    final f = File('$imcu/registers.inc');
    if (!f.existsSync()) return markTestSkipped('no zephyr_scion checkout next to this package');
    expect(registersInc, f.readAsStringSync());
  });

  test('named form: row values, default and explicit mode, errors', () {
    final r = registers['in_swap']!;
    final p = parse('@out swap in_swap\n@out g out0_csc_y0 gain\n@out g in_csc_c0\nout.swap = 1;');
    expect(p.outMap[0].reg, r.reg);
    expect(p.outMap[0].mask, r.mask);
    expect(p.outMap[0].shift, r.shift);
    expect(p.outMap[0].mode, outModes[r.mode]); // a pixel register: no hold flag
    // a line / frame register carries the hold flag (mode bit 4: line-latched, as shader.py sets it)
    expect(registers['out0_csc_y0']!.granularity, anyOf('line', 'frame'));
    expect(p.outMap[1].mode, outModes['gain']! | 0x10);
    expect(p.outMap[2].slot, p.outMap[1].slot); // a name used twice shares one output
    expect(() => parse('@out a no_such_register'), throwsA(isA<ShaderSyntaxError>()));
    expect(() => parse('@out a in_swap sideways'), throwsA(isA<ShaderSyntaxError>()));
    // the numeric form still works and wins when there are five fields
    expect(parse('@out a 0x0111 0x0700 8 raw').outMap.single.reg, 0x0111);
  });

  test("every example's @out map matches shader.py's", () async {
    if (!File('$imcu/shader.py').existsSync()) return markTestSkipped('no shader.py');
    final files = Directory('$imcu/examples').listSync(recursive: true).whereType<File>()
        .where((f) => f.path.endsWith('.ss') && f.readAsStringSync().contains('@out')).toList();
    final py = '''
import json, sys
sys.path.insert(0, "$imcu")
import shader
out = {}
for p in sys.argv[1:]:
    try:
        out[p] = shader.parse_outmap(open(p).read())[1]
    except Exception as e:
        out[p] = str(e)
print(json.dumps(out))
''';
    final r = await Process.run('python3', ['-c', py, ...files.map((f) => f.path)]);
    if (r.exitCode != 0) return markTestSkipped('python3: ${r.stderr}');
    final want = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    expect(files, isNotEmpty);
    for (final f in files) {
      final w = want[f.path];
      if (w is String) {
        expect(() => parse(f.readAsStringSync()), throwsA(isA<ShaderSyntaxError>()), reason: '${f.path}: shader.py says $w');
        continue;
      }
      final got = [for (final e in parse(f.readAsStringSync()).outMap) [e.reg, e.mask, e.shift, e.mode, e.slot]];
      expect(got, w, reason: f.path);
    }
  });
}
