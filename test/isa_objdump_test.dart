// The decoder against the vendor objdump over all 65536 words, alone (p0) and after
// one (p1) or two (p2) LERIs (tool/gen_oracle.dart). Mnemonics, registers and numbers
// are compared after normalising objdump's print quirks. objdump is not the authority
// (gas is: test/isa_gas_test.dart); its known mis-decodes are listed in [objdumpBug].
import 'dart:io';

import 'package:ae32k_shader_compiler/src/isa.dart';
import 'package:test/test.dart';

/// Instructions the decoder deliberately does not cover (coprocessor, debug, the
/// unpack/LDAU/STAU group): the compiler never emits them and gcc output has none.
const uncovered = {
  'cpcmd', 'getc', 'exc', 'exj', 'mvtc', 'mvfc', 'ldc', 'stc', 'cmdop', 'step', 'brkpt',
  'ldau', 'stau', 'upkls', 'upkhs', 'upk0lb', 'upk0hb', 'upk1lb', 'upk1hb', 'upk2lb',
  'upk2hb', 'upk3lb', 'upk3hb', 'unknown', 'mfmre', 'mtmre',
};

/// Registers and numbers, in order. Numbers are 32-bit; objdump's "# (0x..)" comments
/// and `<symbol>` annotations are dropped.
List<String> norm(String text) {
  var t = text.replaceAll(RegExp(r'\s#.*$'), '').replaceAll(RegExp(r'<[^>]*>'), '');
  // rol/ror print the field and then, in parentheses, the full (extended) count
  t = t.replaceAllMapped(RegExp(r'0x[0-9a-f]+ \((0x[0-9a-f]+)\)'), (m) => '${m.group(1)},');
  final parts = t.trim().split(RegExp(r'\s+'));
  final m = parts.first;
  final ops = parts.skip(1).join(' ');
  final out = <String>[m];
  final tok = RegExp(r'%\w+|-?0x[0-9a-f]+|-?\d+');
  for (final x in tok.allMatches(ops)) {
    final s = x.group(0)!;
    if (s.startsWith('%')) {
      out.add(s.toLowerCase());
    } else {
      final neg = s.startsWith('-');
      final u = neg ? s.substring(1) : s;
      final v = u.startsWith('0x') ? int.parse(u.substring(2), radix: 16) : int.parse(u);
      out.add('${(neg ? -v : v) & 0xffffffff}');
    }
  }
  if (m == 'push' || m == 'pop') return [m, ...(out.sublist(1)..sort())];
  return out;
}

/// objdump branch targets are hex without 0x.
List<String> normObjdump(String text) {
  final m = text.split(RegExp(r'\s+')).first;
  if (branches.contains(m)) {
    final t = RegExp(r'^\S+\s+([0-9a-f]+)').firstMatch(text)!.group(1)!;
    return [m, '${int.parse(t, radix: 16)}'];
  }
  // lea (%Rn),%Rd with no extension means offset 0
  final lea0 = RegExp(r'^lea\s+\((%R\d+|%SP)\),(%R\d+|%SP)$').firstMatch(text);
  if (lea0 != null) return norm('lea (${lea0.group(1)},0),${lea0.group(2)}');
  return norm(text);
}

void main() {
  for (final (ctx, pre) in [('p0', <int>[]), ('p1', [0x5555]), ('p2', [0x6AAA, 0x5555])]) {
    test('decoder agrees with objdump ($ctx)', () {
      final rows = gzip.decode(File('test/golden/objdump_$ctx.txt.gz').readAsBytesSync());
      final lines = String.fromCharCodes(rows).split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines.length, 0x10000);
      final bad = <String>[];
      var compared = 0;
      for (final l in lines) {
        final f = l.split('\t');
        final w = int.parse(f[0], radix: 16);
        final addr = int.parse(f[1], radix: 16); // address of w itself
        final od = f.sublist(2).join('\t');
        final om = od.split(RegExp(r'\s+')).first;
        if (uncovered.contains(om) || om == 'leri') continue;
        final start = addr - 2 * pre.length;
        final d = decode([...pre, w], 0, start);
        if (d.length != pre.length + 1) {
          // the decoder says this instruction takes no extension; objdump should agree
          final alone = decode([w], 0, addr).insn;
          if (normObjdump(od).join(' ') != norm(format(alone)).join(' ')) {
            bad.add('${f[0]}: objdump "$od" ours "leri…; ${format(alone)}"');
          }
          compared++;
          continue;
        }
        final ours = norm(format(d.insn));
        final theirs = normObjdump(od);
        if (ours.join(' ') != theirs.join(' ') && !objdumpBug(w, pre, d.insn, theirs)) {
          bad.add('${f[0]}: objdump "$od" ours "${format(d.insn)}"');
        }
        compared++;
      }
      expect(compared, greaterThan(45000)); // 65536 minus 16384 LERIs and the uncovered groups
      File('build/objdump_$ctx.mismatch').writeAsStringSync(bad.join('\n'));
      expect(bad, isEmpty, reason: '${bad.length} mismatches:\n${bad.take(60).join('\n')}');
    });
  }
}

/// Known objdump mis-decodes, each checked against gas (test/golden/gas.txt):
bool objdumpBug(int w, List<int> pre, Insn ours, List<String> theirs) {
  final v = theirs.length > 1 ? int.tryParse(theirs[1]) : null;
  // 1. LDI's 8-bit field is signed (gas: `ldi -1` = a3ff, `ldi 128` needs a LERI);
  //    objdump prints it unsigned.
  if (pre.isEmpty && ours.m == 'ldi' && v == ours.imm! & 0xff) return true;
  // 2. LD/ST (%SP,off) ignore a preceding LERI in objdump; gas extends them
  //    (`ld (%SP,512)` = leri 0x20; ld (%SP,0)).
  if (pre.isNotEmpty && w & 0xF000 == 0x9000) {
    return norm(format(decode([w], 0).insn)).join(' ') == theirs.join(' ');
  }
  // 3. Extended, the bare opcode word (every operand field 0) is mis-extended by objdump:
  //    `leri 0x1555; add %R0,%R0` prints 0x56dd5550 where ER<<4 | 0 = 0x15550 (gas:
  //    `add 87391,%R5` = leri 0x1555; add 0xf), and `lsea` after two LERIs loses ER's sign.
  //    Neighbouring words with any non-zero field agree.
  if (pre.isNotEmpty && const {0x8000, 0xB600, 0xB800, 0xD000, 0xE200, 0xF000, 0xFA00, 0xE1C0}.contains(w)) {
    return true;
  }
  return false;
}
