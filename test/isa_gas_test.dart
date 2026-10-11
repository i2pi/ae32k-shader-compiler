// The encoder against the vendor assembler: every line of test/golden/gas.txt
// (tool/gen_gas_golden.dart) must encode to the same words, decode back to the same
// instruction, and gas's rejections must be rejected here too.
import 'dart:io';

import 'package:ae32k_shader_compiler/src/isa.dart';
import 'package:test/test.dart';

/// Lines gas accepts but encodes wrongly, or with an unverified 3-LERI composition:
/// the encoder refuses them.
bool encoderRefuses(String asm, List<int> words) =>
    gasCorrupts(asm) || words.where((w) => w & 0xC000 == 0x4000).length >= 3; // three LERIs

/// gas accepts these but the bytes mean something else.
bool gasCorrupts(String asm) => RegExp(r'^(asr|lsr|asl|ssl) 32,').hasMatch(asm); // count spills into the register-form bit

void main() {
  final lines = File('test/golden/gas.txt').readAsLinesSync();
  final rows = [
    for (final l in lines)
      if (l.isNotEmpty) l.split('\t'),
  ];

  test('golden file is complete', () => expect(rows.length, greaterThan(3000)));

  test('encodes like gas', () {
    final bad = <String>[];
    for (final r in rows) {
      final asm = r[0];
      if (r[2] == 'ERROR') continue;
      final addr = int.parse(r[1], radix: 16);
      final want = [for (final w in r[2].split(' ')) int.parse(w, radix: 16)];
      if (encoderRefuses(asm, want)) continue;
      try {
        final got = encode(parse(asm, addr), addr);
        if (got.join(',') != want.join(',')) bad.add('$asm: want ${_hex(want)} got ${_hex(got)}');
      } catch (e) {
        bad.add('$asm: want ${_hex(want)} threw $e');
      }
    }
    expect(bad, isEmpty, reason: '${bad.length} mismatches:\n${bad.take(40).join('\n')}');
  });

  test('refuses what gas rejects or corrupts', () {
    final bad = <String>[];
    for (final r in rows) {
      final asm = r[0];
      final refuse = r[2] == 'ERROR' ||
          encoderRefuses(asm, [for (final w in r[2].split(' ')) int.parse(w, radix: 16)]);
      if (!refuse) continue;
      try {
        final got = encode(parse(asm, 0x10000), 0x10000);
        bad.add('$asm: encoded ${_hex(got)}');
      } on EncodeError {
        // expected
      } on FormatException {
        // expected (syntax gas also rejects)
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('decodes gas output back to the same instruction', () {
    final bad = <String>[];
    for (final r in rows) {
      if (r[2] == 'ERROR' || gasCorrupts(r[0])) continue;
      final addr = int.parse(r[1], radix: 16);
      final words = [for (final w in r[2].split(' ')) int.parse(w, radix: 16)];
      final d = decode(words, 0, addr);
      final want = parse(r[0], addr);
      final text = format(d.insn, addr);
      if (d.length != words.length || format(want, addr) != text) {
        bad.add('${r[0]}: ${_hex(words)} decoded as "$text" (${d.length} words)');
      }
    }
    expect(bad, isEmpty, reason: '${bad.length} mismatches:\n${bad.take(40).join('\n')}');
  });
}

String _hex(List<int> w) => w.map((x) => x.toRadixString(16).padLeft(4, '0')).join(' ');
