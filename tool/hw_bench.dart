// Times code on the device with the resident's run-once hook (`imcu hybrun a <slot> <reps>`,
// timer 0 = cpu/4 ticks) and compares it with the emulator.
//
//   dart run tool/hw_bench.dart [--host IP] [--dry] [--local] [--only name,...] [--stages]
//
// Microbenchmarks: each body is assembled at two repeat counts. The cost of one body is
// d(ticks)*4 / (reps * dN), so the hook's call overhead and the blob's setup cancel. Every
// blob first stores its id in out[0], so the reply proves that the intended blob ran.
// --stages also runs compiled examples (native, and the gcc corpus blobs for slot 0) and
// checks out[0..7] against the reference for the hook's fixed inputs.
// --local adds the LOCAL register store (0x0111 <- 0); only with the scan engine stopped.
//
// Only slot 0 is used. Each run is kept under ~40000 ticks: the hook reads the 16-bit timer
// twice, so a run must not wrap it more than once.
import 'dart:io';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:ae32k_shader_compiler/src/asm.dart';
import 'package:ae32k_shader_compiler/src/emu.dart';
import 'package:ae32k_shader_compiler/src/lang/eval.dart';
import 'package:ae32k_shader_compiler/src/lang/parser.dart';
import 'package:ae32k_shader_compiler/src/osc.dart';
import 'package:ae32k_shader_compiler/src/runtime.dart';

const slot = 0, base = 0x1000C000;
const tickCycles = 4, maxRunCycles = 160000;

class Bench {
  final String name, setup, teardown;
  final String Function(int k) body;
  final int n1, n2;
  final bool emulate, loop;
  const Bench(this.name, this.body,
      {this.setup = '', this.teardown = '', this.n1 = 64, this.n2 = 512, this.emulate = true, this.loop = false});
}

// Round 2 (--round2): round 1's branch and LERI costs did not add up on real stages (the
// per-instruction model overpredicted them by 15-20%), so these separate fetch alignment,
// loop branches, load-use into a compare, and time the runtime routines directly.
const _flagsNz = 'ldi 0,%R9\n    cmpq 1,%R9';
const _saveRt = 'push %lr\n    push %R10,%R11,%R12,%R13,%R14\n    lea (%R8,0),%R14';
String _rt(String names) => 'pop %R10,%R11,%R12,%R13,%R14\n    pop %lr\n    jmp done\n${runtimeFor(names.split(','))}\ndone:';
final benches2 = <Bench>[
  Bench('jmp_al', (k) => 'jmp b$k\n    nop\nb$k:', setup: '.align 4', n2: 400),
  Bench('jmp_mis', (k) => 'jmp b$k\n    nop\nb$k:', setup: '.align 4\n    nop', n2: 400),
  Bench('jnz_skip_al', (k) => 'jnz b$k\n    nop\nb$k:', setup: '$_flagsNz\n    .align 4', n2: 400),
  Bench('jnz_skip_mis', (k) => 'jnz b$k\n    nop\nb$k:', setup: '$_flagsNz\n    .align 4\n    nop', n2: 400),
  Bench('leri_al', (k) => 'add 1000,%R9', setup: '.align 4'),
  Bench('leri_mis', (k) => 'add 1000,%R9', setup: '.align 4\n    nop'),
  Bench('nop_leri', (k) => 'nop\n    add 1000,%R9', n2: 400),
  Bench('nop_ldi32', (k) => 'nop\n    ldi 0x12345678,%R9', n2: 300),
  Bench('ld_cmp', (k) => 'ld (%R8,0),%R9\n    cmp %R9,%R9'),
  Bench('ld_st', (k) => 'ld (%R8,0),%R9\n    st %R9,(%SP,0)', setup: 'lea (%SP,-8),%SP', teardown: 'lea (%SP,8),%SP'),
  Bench('st_ld', (k) => 'st %R9,(%SP,0)\n    ld (%SP,0),%R9', setup: 'lea (%SP,-8),%SP', teardown: 'lea (%SP,8),%SP'),
  // counted loops: the body count is the iteration count
  Bench('loop3_al', (k) => '', setup: '.align 4', loop: true, n1: 50, n2: 2000),
  Bench('loop3_mis', (k) => '', setup: '.align 4\n    nop', loop: true, n1: 50, n2: 2000),
  Bench('loop5_al', (k) => 'nop\n    nop', setup: '.align 4', loop: true, n1: 50, n2: 2000),
  // runtime routines with fixed arguments (body = ldi, ldi, jal)
  Bench('rt_qmul', (k) => 'ldi 98304,%R8\n    ldi -147456,%R9\n    jal __qmul', setup: _saveRt, teardown: _rt('__qmul'), n1: 4, n2: 24),
  Bench('rt_qdiv', (k) => 'ldi 196608,%R8\n    ldi 458752,%R9\n    jal __qdiv', setup: _saveRt, teardown: _rt('__qdiv'), n1: 2, n2: 12),
  Bench('rt_qsin', (k) => 'ldi 19661,%R8\n    ldi 0,%R9\n    jal __qsin', setup: _saveRt, teardown: _rt('__qsin'), n1: 4, n2: 24),
  Bench('rt_qsqrt', (k) => 'ldi 131072,%R8\n    ldi 0,%R9\n    jal __qsqrt', setup: _saveRt, teardown: _rt('__qsqrt'), n1: 2, n2: 12),
  Bench('rt_qatan2', (k) => 'ldi 65536,%R8\n    ldi 131072,%R9\n    jal __qatan2', setup: _saveRt, teardown: _rt('__qatan2'), n1: 2, n2: 12),
];

final benches = <Bench>[
  Bench('nop', (k) => 'nop'),
  Bench('addq', (k) => 'addq 1,%R9'),
  Bench('alu_leri', (k) => 'add 1000,%R9'),
  Bench('ldi32', (k) => 'ldi 0x12345678,%R9', n2: 400),
  Bench('ld_dspm', (k) => 'ld (%R8,0),%R9'),
  Bench('ld_dspm_use', (k) => 'ld (%R8,0),%R9\n    addq 1,%R9'),
  Bench('ld_ispm', (k) => 'ld (%R8,0),%R9', setup: 'ldi 0x1000C000,%R8'),
  Bench('st_dspm', (k) => 'st %R9,(%SP,0)', setup: 'lea (%SP,-8),%SP', teardown: 'lea (%SP,8),%SP'),
  Bench('jmp', (k) => 'jmp b$k\nb$k:'),
  Bench('jnz_taken', (k) => 'jnz b$k\nb$k:', setup: 'ldi 0,%R9\n    cmpq 1,%R9'),
  Bench('jz_not', (k) => 'jz b$k\nb$k:', setup: 'ldi 0,%R9\n    cmpq 1,%R9'),
  Bench('mul', (k) => 'mul %R9,%R8', setup: 'ldi 3,%R9'),
  Bench('push_pop', (k) => 'push %R9\n    pop %R9'),
  Bench('jal_jplr', (k) => 'jal sub', setup: 'push %lr', teardown: 'pop %lr\n    jmp done\nsub:\n    jplr\ndone:', n1: 16, n2: 112), // jal stays one word (+-256 words)
  // c_delay(n) from hyb.elf, called with n = N (the "body" count is the loop count).
  Bench('c_delay_iter', (k) => '', n1: 20, n2: 200),
];

const localBench = Bench('local_st', _localBody, setup: 'ldi 0x70000444,%R8\n    ldi 0,%R9', n1: 16, n2: 128, emulate: false);
String _localBody(int k) => 'sts %R9,(%R8,0)';

const cDelay = '''
c_delay:
    lea (%SP,-4),%SP
    lea (%R8,0),%R9
    ldi 0,%R8
    jmp cd_test
cd_loop:
    ld (%SP,0),%R8
    addq 1,%R8
cd_test:
    st %R8,(%SP,0)
    ld (%SP,0),%R8
    cmp %R9,%R8
    jc cd_loop
    lea (%SP,4),%SP
    jplr''';

String source(Bench b, int id, int n) {
  final s = StringBuffer('    ldi $id,%R9\n    st %R9,(%R8,84)\n');
  if (b.name == 'c_delay_iter') {
    s.write('    push %lr\n    ldi $n,%R8\n    jal c_delay\n    pop %lr\n    jplr\n$cDelay\n');
    return s.toString();
  }
  if (b.setup.isNotEmpty) s.write('    ${b.setup}\n');
  if (b.loop) {
    final body = b.body(0);
    s.write('    ldi $n,%R9\n    jmp l_top\n    .align 4\n${b.setup.endsWith('nop') ? '    nop\n' : ''}l_top:\n${body.isEmpty ? '' : '    $body\n'}    addq -1,%R9\n    cmpq 0,%R9\n    jnz l_top\n    jplr\n');
    return s.toString();
  }
  for (var k = 0; k < n; k++) {
    s.write('    ${b.body(k)}\n');
  }
  if (b.teardown.isNotEmpty) s.write('    ${b.teardown}\n');
  s.write('    jplr\n');
  return s.toString();
}

// The hook's fixed inputs (zephyr-scion-94, 2026-10-11).
const hookInputs = {
  'x': 960 << 16, 'y': 540 << 16, 'u': 0x8000, 'v': 0x8000, 't': 0x10000, 'frame': 0x10000,
  'rnd': 0x4000, 'w': 1920 << 16, 'h': 1080 << 16, 'p0': 0x8000, 'p1': 0x8000, 'p2': 0x8000, 'p3': 0x8000,
};

int emuCycles(List<int> blob) {
  final st = <String, int>{};
  StageRunner(blob, slot: slot).run(hookInputs, stats: st);
  return st['cycles']!;
}

/// The device arms len/4 words: pad, or the tail (the final jplr) is lost.
List<int> pad4(List<int> b) => [...b, ...List.filled(-b.length % 4 & 3, 0)];

int repsFor(int cycles) => (maxRunCycles ~/ (cycles * 2 + 200)).clamp(1, 20000);

class Device {
  final String host;
  late final Socket _tel;
  final _buf = StringBuffer();
  late final RawDatagramSocket _udp;
  Device(this.host);

  Future<void> open() async {
    _tel = await Socket.connect(host, 23, timeout: const Duration(seconds: 5));
    _tel.listen((d) => _buf.write(String.fromCharCodes(d)));
    _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  Future<void> upload(List<int> blob) async {
    for (final p in stageParts(blob, slot)) {
      _udp.send(p, InternetAddress(host), 9000);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  /// The hook's reply words (hex): delta ticks, reps, out[0..7].
  Future<List<int>> run(int reps) async {
    _buf.clear();
    _tel.write('imcu hybrun a $slot ${reps.toRadixString(16)}\r\n');
    final end = DateTime.now().add(const Duration(seconds: 7));
    final re = RegExp(r"'= ([0-9A-Fa-f]+(?: [0-9A-Fa-f]+)+)'");
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final m = re.firstMatch(_buf.toString());
      if (m != null) return m.group(1)!.trim().split(' ').map((w) => int.parse(w, radix: 16)).toList();
    }
    throw StateError('no reply to hybrun; got: $_buf');
  }

  Future<void> close() async {
    await _tel.close();
    _udp.close();
  }
}

Future<void> main(List<String> args) async {
  String? opt(String n) => args.contains(n) ? args[args.indexOf(n) + 1] : null;
  final dry = args.contains('--dry');
  final only = opt('--only')?.split(',');
  final list = [...args.contains('--round2') ? benches2 : benches, if (args.contains('--local')) localBench].where((b) => only == null || only.contains(b.name)).toList();
  final dev = dry ? null : Device(opt('--host') ?? Platform.environment['SCION_IP'] ?? '192.168.100.221');
  await dev?.open();
  try {
    // Baseline: the hook's own per-call cost with a stage that only stores its id.
    final ids = <String, int>{};
    var id = 0x100;
    Future<(double, int)?> time(String what, List<int> blob, int emu, int reps) async {
      final myId = ids[what] = id++;
      if (dev == null) return null;
      await dev.upload(blob);
      final r = await dev.run(reps);
      if (r[1] != reps) throw StateError('$what: hook echoed reps ${r[1]}, sent $reps (radix?)');
      if (r[2] != myId) throw StateError('$what: out[0] = ${r[2].toRadixString(16)}, expected ${myId.toRadixString(16)} (blob not armed?)');
      return (r[0] * tickCycles / reps, r[0]);
    }

    print('${'bench'.padRight(14)} ${'emu/body'.padLeft(9)} ${'hw/body'.padLeft(9)}   (hw ticks n1, n2; reps)');
    for (final b in list) {
      final blobs = [for (final n in [b.n1, b.n2]) pad4(assemble(source(b, id + (n == b.n1 ? 0 : 1), n), base).bytes)];
      final emu = b.emulate ? [for (final bl in blobs) emuCycles(bl)] : null;
      final reps = repsFor(emu?.last ?? 40 * b.n2);
      final emuPer = emu == null ? null : (emu[1] - emu[0]) / (b.n2 - b.n1);
      final t1 = await time('${b.name}#1', blobs[0], emu?[0] ?? 0, reps);
      final t2 = await time('${b.name}#2', blobs[1], emu?[1] ?? 0, reps);
      final hwPer = t1 == null ? null : (t2!.$1 - t1.$1) / (b.n2 - b.n1);
      print('${b.name.padRight(14)} ${emuPer?.toStringAsFixed(3).padLeft(9) ?? '        -'} '
          '${hwPer?.toStringAsFixed(3).padLeft(9) ?? '        -'}   ${t1 == null ? '' : '(${t1.$2}, ${t2!.$2}; $reps)'}');
    }

    if (args.contains('--stages')) {
      // The hook's per-rep overhead (call + its tm_rd): an empty stage, emulator vs device.
      final empty = pad4(assemble('    jplr\n', base).bytes);
      var hwEmpty = 0.0, emuEmpty = 0;
      if (dev != null) {
        await dev.upload(empty);
        final r = await dev.run(2000);
        hwEmpty = r[0] * tickCycles / 2000;
        emuEmpty = emuCycles(empty);
        print('\nempty stage: ${hwEmpty.toStringAsFixed(2)} cycles per rep on the device (emulator $emuEmpty); subtracted below');
      }
      print('\nstage                 emu cyc   hw cyc   out[0..7] vs reference (reps = 1)');
      final ex = Directory('test/golden/gcc').listSync().whereType<File>().where((f) => f.path.endsWith('.ss')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      final manifest = {
        for (final l in File('test/golden/gcc/manifest.txt').readAsLinesSync()) l.split('\t')[0]: int.parse(l.split('\t')[1]),
      };
      for (final f in ex) {
        final name = f.uri.pathSegments.last.replaceAll('.ss', '');
        if (!name.startsWith('rand') || name.compareTo('rand004') < 0) {
          final src = f.readAsStringSync();
          final prog = parse(src);
          final want = evaluate(prog, hookInputs, List.filled(16, 0)).sublist(0, 8);
          final variants = <String, List<int>>{'native': compileStage(src, slot: slot).bytes};
          if (manifest[name] == slot) variants['gcc'] = File('test/golden/gcc/$name.bin').readAsBytesSync();
          for (final v in variants.entries) {
            final st = <String, int>{};
            final got = StageRunner(v.value, slot: slot).run(hookInputs, stats: st).sublist(0, 8);
            final label = '$name/${v.key}'.padRight(20);
            if (got.join(',') != want.join(',')) throw StateError('$label emulator disagrees with the reference');
            if (dev == null) {
              print('$label ${st['cycles'].toString().padLeft(8)}        -');
              continue;
            }
            // out[] is zeroed once per command, so check outputs with one rep, then time many.
            await dev.upload(v.value);
            final hw = (await dev.run(1)).sublist(2, 10);
            final reps = repsFor(st['cycles']!);
            final r = await dev.run(reps);
            final ok = hw.join(',') == want.map((w) => w & 0xffffffff).join(',');
            print('$label ${st['cycles'].toString().padLeft(8)} ${(r[0] * tickCycles / reps - hwEmpty + emuEmpty).toStringAsFixed(1).padLeft(8)}   '
                '${ok ? 'match' : 'MISMATCH hw ${hw.map((w) => w.toRadixString(16))} want ${want.map((w) => (w & 0xffffffff).toRadixString(16))}'}');
          }
        }
      }
    }
  } finally {
    await dev?.close();
  }
}
