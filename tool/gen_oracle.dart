// Regenerates the objdump oracle in test/golden/ from the vendor EISC toolchain
// (ae32000-elf-gcc 3.4.5 / binutils 2.14 under Wine; see EISC_TOOLCHAIN).
//
// Every 16-bit word is disassembled in three contexts: alone (after a NOP), after
// one LERI and after two, so the immediate extension rules are covered too. Each
// word gets its own label because objdump steps one byte over a reserved encoding
// (0xB780..) and would decode the rest of the section misaligned; it restarts at
// every symbol.
//
// Output: test/golden/objdump_<ctx>.txt.gz, one line per word: "wwww<TAB>addr<TAB>text"
// (addr in hex, text as objdump prints it with trailing whitespace removed). -z keeps
// objdump from collapsing zero words to "...".
//
//   dart run tool/gen_oracle.dart
import 'dart:io';

const contexts = {
  'p0': [0xE0B0], // nop
  'p1': [0x5555], // leri 0x1555
  'p2': [0x6AAA, 0x5555], // leri 0x2aaa; leri 0x1555
};

Future<void> main() async {
  final tc = Platform.environment['EISC_TOOLCHAIN'] ??
      '${Platform.environment['HOME']}/src/superchromat/eisc-toolchain';
  final work = await Directory.systemTemp.createTemp('ae32k_oracle');
  final golden = Directory('test/golden')..createSync(recursive: true);
  final line = RegExp(r'^\s*([0-9a-f]+):\t((?:[0-9a-f]{2} )+)\s*\t?(.*)$');
  final label = RegExp(r'^[0-9a-f]+ <w([0-9a-f]{4})>:');

  for (final MapEntry(key: name, value: pre) in contexts.entries) {
    final s = StringBuffer('.text\nstart:\n\t.short 0xe0b0\n'); // address 0 would print as <.text>
    for (var x = 0; x < 0x10000; x++) {
      s.write('w${x.toRadixString(16).padLeft(4, '0')}:\n');
      for (final p in pre) {
        s.write('\t.short 0x${p.toRadixString(16)}\n');
      }
      s.write('\t.short 0x${x.toRadixString(16)}\n');
    }
    s.write('wend:\n\t.short 0xe0b0\n');
    // The Wine gcc cannot open paths under /var/folders: run inside the dir, relative names.
    File('${work.path}/$name.s').writeAsStringSync(s.toString());
    await _run('$tc/bin/ae32000-elf-as', ['$name.s', '-o', '$name.o'], work.path);
    final dis = await _run('$tc/bin/ae32000-elf-objdump', ['-d', '-z', '$name.o'], work.path);

    final out = <int, String>{};
    int? word, base;
    for (final l in dis.split('\n')) {
      final lm = label.firstMatch(l);
      if (lm != null) {
        word = int.parse(lm.group(1)!, radix: 16);
        base = null;
        continue;
      }
      final m = line.firstMatch(l);
      if (m == null || word == null) continue;
      final addr = int.parse(m.group(1)!, radix: 16);
      base ??= addr;
      if (addr == base + 2 * pre.length) {
        out[word] = '${word.toRadixString(16).padLeft(4, '0')}\t${addr.toRadixString(16)}\t${m.group(3)!.trimRight()}';
      }
    }
    if (out.length != 0x10000) {
      final miss = [for (var x = 0; x < 0x10000; x++) if (!out.containsKey(x)) x.toRadixString(16)];
      throw StateError("$name: only ${out.length} words decoded, missing ${miss.take(8)}");
    }
    final text = [for (var x = 0; x < 0x10000; x++) out[x]!].join('\n');
    File('${golden.path}/objdump_$name.txt.gz').writeAsBytesSync(gzip.encode('$text\n'.codeUnits));
    stdout.writeln('$name: ${out.length} words');
  }
  await work.delete(recursive: true);
}

Future<String> _run(String exe, List<String> args, String cwd) async {
  final r = await Process.run(exe, args, workingDirectory: cwd);
  if (r.exitCode != 0) throw ProcessException(exe, args, '${r.stderr}', r.exitCode);
  return r.stdout as String;
}
