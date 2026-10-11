// OSC packets must match tools/imcu/shader.py byte for byte (hex captured from
// shader.osc_msg / outmap_blob).
import 'package:ae32k_shader_compiler/src/lang/ast.dart';
import 'package:ae32k_shader_compiler/src/osc.dart';
import 'package:test/test.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('stage part', () {
    final blob = [0x44, 0x33, 0x22, 0x11, 0x88, 0x77, 0x66, 0x55, 0xcc, 0xbb, 0xaa, 0x99];
    expect(hex(stageParts(blob, 1).single),
        '2f73656e642f312f7368616465722f7363616e70617274002c69696200000000000000000000000c0000000c4433221188776655ccbbaa99');
  });
  test('parts are 1 KB with offset and total', () {
    final parts = stageParts(List.filled(2500, 7), 0);
    expect(parts, hasLength(3));
  });
  test('knob', () => expect(hex(knobMessage(3, 0.25)), '2f73656e642f312f7368616465722f6b2f3300002c6600003e800000'));
  test('scan map', () {
    final m = scanMapMessage(const [OutMapEntry(0x0237, 0x0080, 7, 0, 0), OutMapEntry(0x1C0E, 0xFFFF, 0, 1, 1)]);
    expect(hex(m),
        '2f73656e642f312f7368616465722f7363616e6d617000002c620000000000160200370280000700000000000e1cffff0000010001000000');
  });
}
