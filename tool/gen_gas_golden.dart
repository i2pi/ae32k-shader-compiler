// Regenerates test/golden/gas.txt: what the vendor assembler emits for every
// instruction form the compiler or emulator cares about, across edge-case operand
// values. gas built the code that runs on the device, so this is the encoding
// authority (objdump mis-prints some extended immediates; see docs/AE32000_ISA.md).
//
// One line per instruction: "<asm><TAB><addr><TAB><hex words>", or "<asm><TAB>-<TAB>ERROR" when gas
// rejects it. Only values gas encodes faithfully are generated: it silently drops
// misaligned offset bits and rounds MUL's destination to an even register, and the
// encoder rejects those instead of copying the behaviour.
//
//   dart run tool/gen_gas_golden.dart
import 'dart:io';

const imms = [
  0, 1, -1, 2, 7, 8, -8, -9, 15, 16, -16, -17, 31, 32, 100, -100, 127, 128, -128, -129, 255, 256,
  0x1fff, 0x2000, -0x2000, -0x2001, 0x3fff, 0x4000, 0xffff, 0x10000, -0x10000, 0x3ffff, 0x40000,
  0x7ffff, 0x123456, 0x1fffff, 0x200000, 0x7fffffff, -0x80000000, 0x12345678, -0x12345678,
  0x40000000, -0x40000001, 0x0FFFFFFF, -0x10000000, 0x1555f, 0xaaaa5555 - 0x100000000,
];

/// Offsets whose ER sits on either side of the 13- and 14-bit signed limits, with the
/// instruction's own field both empty and full.
List<int> erEdges(int shift, int align) => [
      for (final er in [0xfff, 0x1000, -0x1000, -0x1001, 0x1fff, 0x2000, -0x2000, -0x2001])
        for (final low in [0, (1 << shift) - align]) (er << shift) + low,
    ];

List<String> forms() {
  final out = <String>[];
  String r(int n) => '%R$n';
  final regs = [0, 1, 7, 8, 14, 15];

  // index-register memory forms: (mnemonic, alignment)
  for (final (m, align, store) in [
    ('ld', 4, false), ('st', 4, true), ('lds', 2, false), ('ldsu', 2, false), ('sts', 2, true),
    ('ldb', 1, false), ('ldbu', 1, false), ('stb', 1, true),
  ]) {
    for (final v in imms) {
      final off = v * align ~/ (v.abs() > 0x1fffffff ? align : 1); // keep within 32 bits
      if (off % align != 0) continue;
      for (final (a, b) in [(1, 2), (15, 0)]) {
        out.add(store ? '$m ${r(a)},(${r(b)},$off)' : '$m (${r(b)},$off),${r(a)}');
      }
    }
    for (final v in imms) {
      final off = v * align ~/ (v.abs() > 0x1fffffff ? align : 1);
      if (off % align != 0) continue;
      out.add(store ? '$m ${r(3)},(%SP,$off)' : '$m (%SP,$off),${r(3)}');
    }
    // where gas switches from one LERI to two (ER = offset >> 4, or >> 3 for bytes)
    for (final off in erEdges(align == 1 ? 3 : 4, align)) {
      out.add(store ? '$m ${r(1)},(${r(2)},$off)' : '$m (${r(2)},$off),${r(1)}');
      out.add(store ? '$m ${r(3)},(%SP,$off)' : '$m (%SP,$off),${r(3)}');
    }
  }
  for (final off in erEdges(4, 4)) {
    out.add('lea (%SP,$off),%SP');
  }
  for (final v in imms) {
    for (final d in [0, 9, 15]) {
      out.add('ldi $v,${r(d)}');
    }
    final off = v * 4 ~/ (v.abs() > 0x1fffffff ? 4 : 1);
    if (off % 4 == 0) out.add('lea (%SP,$off),%SP'); // gas drops the low bits otherwise
    out.add('lea (${r(3)},$v),${r(12)}');
    out.add('lea (${r(3)},$v),%SP'); // LSEA
    out.add('lea (%SP,$v),${r(3)}'); // LESA
  }
  out.add('lea (${r(3)}),${r(12)}');

  const alu = ['add', 'adc', 'sub', 'sbc', 'and', 'or', 'xor', 'cmp', 'tst', 'mac'];
  for (final m in alu) {
    for (final s in regs) {
      for (final d in regs) {
        out.add('$m ${r(s)},${r(d)}');
      }
    }
    for (final v in imms) {
      out.add('$m $v,${r(5)}');
    }
  }
  for (final m in ['mul', 'mulu']) {
    for (final s in regs) {
      for (final d in [0, 2, 8, 14]) {
        out.add('$m ${r(s)},${r(d)}');
      }
    }
    for (final v in imms) {
      out.add('$m $v,${r(6)}');
    }
  }
  for (final m in ['addq', 'cmpq']) {
    for (var v = -17; v <= 16; v++) {
      out.add('$m $v,${r(4)}');
    }
  }
  for (final m in ['asr', 'lsr', 'asl', 'ssl']) {
    for (final n in [0, 1, 15, 16, 31, 32]) {
      out.add('$m $n,${r(6)}');
    }
    for (final s in regs) {
      out.add('$m ${r(s)},${r(9)}');
    }
  }
  for (final m in [
    'extb', 'exts', 'cvb', 'cvs', 'neg', 'not', 'jr', 'jalr', 'mfmh', 'mfml', 'mtmh', 'mtml',
    'cnt0', 'cnt1', 'mfcr0', 'mfcr1', 'mtcr0', 'mtcr1', 'abs',
  ]) {
    for (final d in regs) {
      out.add('$m ${r(d)}');
    }
  }
  for (final m in ['jplr', 'nop', 'sync']) {
    out.add(m);
  }
  for (final m in ['min', 'max', 'sadd', 'avgs', 'avgb']) {
    for (final s in regs) {
      for (final d in [0, 7, 8]) {
        out.add('$m ${r(s)},${r(d)}');
      }
    }
    for (final v in [0, 5, -5, 0x12345]) {
      out.add('$m $v,${r(3)}');
    }
  }
  for (var n = 0; n <= 8; n++) {
    out.add('mrs $n,${r(3)}');
  }
  for (final m in ['rol', 'ror']) {
    for (final n in [0, 1, 7, 8, 31]) {
      out.add('$m $n,${r(3)}');
    }
  }
  for (final list in [
    '%R0', '%R7', '%R0,%R1,%R6', '%R8', '%R15', '%R8,%R14', '%lr', '%mh,%ml', '%sr,%pc,%lr',
    '%R0,%R8', '%R0,%lr', '%R0,%R1,%R2,%R3,%R4,%R5,%R6,%R7',
  ]) {
    out.add('push $list');
    out.add('pop $list');
  }
  for (final m in ['set', 'clr', 'swi', 'halt']) {
    for (final n in [0, 15]) {
      out.add('$m $n');
    }
  }
  return out;
}

const branches = [
  'jnv', 'jv', 'jp', 'jm', 'jnz', 'jz', 'jnc', 'jc', 'jgt', 'jlt', 'jge', 'jle', 'jhi', 'jls',
  'jmp', 'jal',
];

Future<void> main() async {
  final tc = Platform.environment['EISC_TOOLCHAIN'] ??
      '${Platform.environment['HOME']}/src/superchromat/eisc-toolchain';
  final work = await Directory.systemTemp.createTemp('ae32k_gas');
  // Branches to labels at known distances (gas emits the long form for all of them).
  final dists = [-0x10000, -258, -256, -2, 0, 2, 254, 256, 0x10000];
  final all = {
    ...forms(),
    for (final b in branches)
      for (final d in dists) '$b .${d >= 0 ? '+' : ''}$d',
  }.toList();
  var items = all;

  final rejected = <String>{};
  for (var attempt = 0;; attempt++) {
    final live = [for (final s in items) if (!rejected.contains(s)) s];
    // padding both sides so the +-64 KB branch targets stay inside the section
    final src = StringBuffer('.text\n\t.space 0x10010\nstart:\n\tnop\n');
    final lineOf = <int, String>{};
    var line = 5;
    for (var i = 0; i < live.length; i++) {
      src.write('i$i:\n');
      line++;
      src.write('\t${live[i]}\n');
      lineOf[line] = live[i];
      line++;
    }
    src.write('i${live.length}:\n\tnop\n\t.space 0x10010\n');
    File('${work.path}/g.s').writeAsStringSync(src.toString());
    final as = await Process.run('$tc/bin/ae32000-elf-as', ['g.s', '-o', 'g.o'], workingDirectory: work.path);
    final errs = RegExp(r'g\.s:(\d+): Error').allMatches('${as.stderr}').map((m) => int.parse(m.group(1)!));
    if (errs.isEmpty && as.exitCode == 0) {
      items = live;
      break;
    }
    if (errs.isEmpty || attempt > 20) throw StateError('as failed: ${as.stderr}');
    for (final l in errs) {
      // gas sometimes reports the line after the offending one (the next label)
      rejected.add(lineOf[l] ?? lineOf[l - 1] ?? (throw StateError('error on unmapped line $l')));
    }
  }

  // Branches to labels are relocations until link time: link at 0, then slice the flat
  // binary between consecutive labels (objdump names only one symbol per address).
  await _run('$tc/bin/ae32000-elf-ld', ['--section-start=.text=0', '-e', 'start', '-o', 'g.elf', 'g.o'], work.path);
  await _run('$tc/bin/ae32000-elf-objcopy', ['-O', 'binary', 'g.elf', 'g.bin'], work.path);
  final nm = await _run('$tc/bin/ae32000-elf-nm', ['g.elf'], work.path);
  final addr = <int, int>{};
  for (final m in RegExp(r'^([0-9a-f]+) t i(\d+)$', multiLine: true).allMatches(nm)) {
    addr[int.parse(m.group(2)!)] = int.parse(m.group(1)!, radix: 16);
  }
  final bin = File('${work.path}/g.bin').readAsBytesSync();

  final out = StringBuffer();
  final index = {for (var i = 0; i < items.length; i++) items[i]: i};
  for (final s in all) {
    if (rejected.contains(s)) {
      out.writeln('$s\t-\tERROR');
      continue;
    }
    final i = index[s]!;
    final a = addr[i], b = addr[i + 1];
    if (a == null || b == null || b <= a) throw StateError('no words for "$s"');
    final w = [for (var p = a; p < b; p += 2) (bin[p] | bin[p + 1] << 8).toRadixString(16).padLeft(4, '0')];
    out.writeln('$s\t${a.toRadixString(16)}\t${w.join(' ')}');
  }
  File('test/golden/gas.txt').writeAsStringSync(out.toString());
  stdout.writeln('${all.length} forms, ${rejected.length} rejected by gas');
  await work.delete(recursive: true);
}

Future<String> _run(String exe, List<String> args, String cwd) async {
  final r = await Process.run(exe, args, workingDirectory: cwd);
  if (r.exitCode != 0) throw ProcessException(exe, args, '${r.stderr}', r.exitCode);
  return r.stdout as String;
}
