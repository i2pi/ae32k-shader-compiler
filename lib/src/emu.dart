// AE32000 emulator for stage blobs: runs `int stage(struct ctx *)` the way the resident
// calls it, so native code can be checked against the reference interpreter without
// hardware, and its cost estimated.
//
// Semantics from the ADChips quick reference (docs/); flag behaviour where the reference
// is silent is marked. Instructions a stage never needs (coprocessor, debug, interrupts,
// SIMD) raise [EmuError].
import 'dart:typed_data';

import 'abi.dart';
import 'isa.dart';
import 'sin_table.dart';

class EmuError implements Exception {
  final String message;
  EmuError(this.message);
  @override
  String toString() => 'EmuError: $message';
}

class _Region {
  final int base;
  final ByteData data;
  _Region(this.base, int size) : data = ByteData(size);
  bool has(int a, int n) => a >= base && a + n <= base + data.lengthInBytes;
}

/// Data reads from ISPM cost 3 cycles, instruction fetch from DSPM likewise (MIT's
/// EmbeddedMCU datasheet); everything else is counted as one cycle per instruction word.
class Cpu {
  static const ispm = 0x10000000, dspm = 0x20000000, spmSize = 0x10000;
  static const returnMagic = 0x0FFFFFF0; // LR on entry; reaching it ends the call

  final r = Int32List(16);
  int stackPtr = 0, pc = 0, lr = 0, mh = 0, ml = 0;
  bool c = false, z = false, s = false, v = false;
  int cycles = 0, insns = 0;
  final _mem = [_Region(ispm, spmSize), _Region(dspm, spmSize)];
  final _decoded = <int, Decoded>{};

  _Region _at(int a, int n) {
    for (final m in _mem) {
      if (m.has(a, n)) return m;
    }
    throw EmuError('bus error: ${n * 8}-bit access at 0x${a.toRadixString(16)} (pc 0x${pc.toRadixString(16)})');
  }

  int read32(int a) {
    if (a & 3 != 0) throw EmuError('misaligned word read at 0x${a.toRadixString(16)}');
    final m = _at(a, 4);
    if (m.base == ispm) cycles += 2;
    return m.data.getInt32(a - m.base, Endian.little);
  }

  int read16(int a) {
    final m = _at(a, 2);
    if (m.base == ispm) cycles += 2;
    return m.data.getUint16(a - m.base, Endian.little);
  }

  int read8(int a) {
    final m = _at(a, 1);
    if (m.base == ispm) cycles += 2;
    return m.data.getUint8(a - m.base);
  }

  void write32(int a, int x) {
    if (a & 3 != 0) throw EmuError('misaligned word write at 0x${a.toRadixString(16)}');
    final m = _at(a, 4);
    m.data.setInt32(a - m.base, _s(x), Endian.little);
    _decoded.removeWhere((k, _) => k >= a - 6 && k < a + 4);
  }

  void write16(int a, int x) {
    final m = _at(a, 2);
    m.data.setUint16(a - m.base, x & 0xffff, Endian.little);
    _decoded.removeWhere((k, _) => k >= a - 6 && k < a + 2);
  }

  void write8(int a, int x) {
    final m = _at(a, 1);
    m.data.setUint8(a - m.base, x & 0xff);
    _decoded.removeWhere((k, _) => k >= a - 6 && k < a + 1);
  }

  void load(int addr, List<int> bytes) {
    for (var i = 0; i < bytes.length; i++) {
      write8(addr + i, bytes[i]);
    }
  }

  /// Calls the function at [entry] with [arg] in R8 until it returns; returns R8.
  int call(int entry, int arg, {int maxInsns = 2000000}) {
    r[8] = arg;
    lr = returnMagic;
    pc = entry;
    while (pc != returnMagic) {
      if (insns++ > maxInsns) throw EmuError('no return after $maxInsns instructions');
      step();
    }
    return r[8];
  }

  Decoded _fetch() {
    final hit = _decoded[pc];
    if (hit != null) return hit;
    final words = [for (var k = 0; k < 4; k++) _peek16(pc + 2 * k)];
    final d = decode(words, 0, pc);
    _decoded[pc] = d;
    return d;
  }

  int _peek16(int a) {
    for (final m in _mem) {
      if (m.has(a, 2)) return m.data.getUint16(a - m.base, Endian.little);
    }
    return 0;
  }

  static int _s(int x) => x.toSigned(32);
  static int _u(int x) => x & 0xffffffff;

  void _nz(int x) {
    z = _s(x) == 0;
    s = _s(x) < 0;
  }

  int _add(int a, int b, int cin) {
    final res = _u(a) + _u(b) + cin;
    final out = _s(res);
    c = res > 0xffffffff;
    v = (_s(a) >= 0) == (_s(b) >= 0) && (out >= 0) != (_s(a) >= 0);
    _nz(out);
    return out;
  }

  /// a - b - bin; C is the borrow (set when unsigned a < b + bin), so JNC means
  /// "unsigned higher or same" and JHI/JLS test C|Z, as in the quick reference.
  int _sub(int a, int b, int bin) {
    final res = _u(a) - _u(b) - bin;
    final out = _s(res);
    c = res < 0;
    v = (_s(a) >= 0) != (_s(b) >= 0) && (out >= 0) != (_s(a) >= 0);
    _nz(out);
    return out;
  }

  bool _cond(int k) => switch (k) {
        0 => !v, 1 => v, 2 => !s, 3 => s, 4 => !z, 5 => z, 6 => !c, 7 => c,
        8 => !(z || (s != v)), 9 => s != v, 10 => s == v, 11 => z || (s != v),
        12 => !(c || z), 13 => c || z, _ => true,
      };

  int _src(Insn i) => i.imm ?? r[i.rs!];

  int _get(int reg) => reg == sp ? stackPtr : r[reg];
  void _set(int reg, int x) {
    if (reg == sp) {
      stackPtr = _s(x);
    } else {
      r[reg] = _s(x);
    }
  }

  void step() {
    final d = _fetch();
    final i = d.insn;
    final next = pc + 2 * d.length;
    cycles += d.length;
    if (pc < dspm + spmSize && pc >= dspm) cycles += 2 * d.length;
    var npc = next;
    final m = i.m;
    final bi = branches.indexOf(m);
    if (bi >= 0) {
      if (m == 'jal') lr = next;
      if (_cond(bi)) npc = i.target!;
      pc = npc;
      return;
    }
    switch (m) {
      case 'ld' || 'ldb' || 'ldbu' || 'lds' || 'ldsu':
        final a = _s(_get(i.rb!) + i.imm!);
        r[i.rd!] = switch (m) {
          'ld' => read32(a),
          'ldb' => read8(a).toSigned(8),
          'ldbu' => read8(a),
          'lds' => read16(a).toSigned(16),
          _ => read16(a),
        };
      case 'st' || 'stb' || 'sts':
        final a = _s(_get(i.rb!) + i.imm!);
        switch (m) {
          case 'st':
            write32(a, r[i.rd!]);
          case 'stb':
            write8(a, r[i.rd!]);
          default:
            write16(a, r[i.rd!]);
        }
      case 'ldi':
        r[i.rd!] = _s(i.imm!);
      case 'lea':
        _set(i.rd!, _get(i.rb!) + i.imm!);
      case 'add':
        r[i.rd!] = _add(r[i.rd!], _src(i), 0);
      case 'adc':
        r[i.rd!] = _add(r[i.rd!], _src(i), c ? 1 : 0);
      case 'sub':
        r[i.rd!] = _sub(r[i.rd!], _src(i), 0);
      case 'sbc':
        r[i.rd!] = _sub(r[i.rd!], _src(i), c ? 1 : 0);
      case 'cmp':
        _sub(r[i.rd!], _src(i), 0);
      case 'addq':
        r[i.rd!] = _add(r[i.rd!], i.imm!, 0);
      case 'cmpq':
        _sub(r[i.rd!], i.imm!, 0);
      case 'and' || 'or' || 'xor':
        final x = switch (m) { 'and' => r[i.rd!] & _src(i), 'or' => r[i.rd!] | _src(i), _ => r[i.rd!] ^ _src(i) };
        r[i.rd!] = _s(x);
        _nz(x);
      case 'tst':
        _nz(r[i.rd!] & _src(i));
      case 'not':
        r[i.rd!] = ~r[i.rd!];
        _nz(r[i.rd!]);
      case 'neg':
        // flags: not stated in the quick reference; left unchanged (gcc never branches on them)
        r[i.rd!] = _s(-r[i.rd!]);
      case 'extb' || 'exts' || 'cvb' || 'cvs':
        final x = r[i.rd!];
        r[i.rd!] = switch (m) { 'extb' => x.toSigned(8), 'exts' => x.toSigned(16), 'cvb' => x & 0xff, _ => x & 0xffff };
        _nz(r[i.rd!]);
      case 'asr' || 'lsr' || 'asl' || 'ssl':
        final n = (i.imm ?? r[i.rs!]) & 31;
        final x = _u(r[i.rd!]);
        if (n > 0) {
          switch (m) {
            case 'asr':
              c = (_s(x) >> (n - 1)) & 1 != 0;
              r[i.rd!] = _s(x) >> n;
            case 'lsr':
              c = (x >> (n - 1)) & 1 != 0;
              r[i.rd!] = _s(x >> n);
            case 'asl':
              c = (x >> (32 - n)) & 1 != 0;
              r[i.rd!] = _s(x << n);
            default:
              c = (x >> (32 - n)) & 1 != 0;
              r[i.rd!] = _s(x << n | ((1 << n) - 1));
          }
        }
        _nz(r[i.rd!]);
      case 'mul' || 'mulu':
        final a = m == 'mul' ? _s(r[i.rd!]) : _u(r[i.rd!]);
        final b = m == 'mul' ? _s(_src(i)) : _u(_src(i));
        final p = BigInt.from(a) * BigInt.from(b);
        ml = _s((p & BigInt.from(0xffffffff)).toInt());
        mh = _s(((p >> 32) & BigInt.from(0xffffffff)).toInt());
        r[i.rd!] = ml;
      case 'mfmh':
        r[i.rd!] = mh;
      case 'mfml':
        r[i.rd!] = ml;
      case 'mtmh':
        mh = r[i.rd!];
      case 'mtml':
        ml = r[i.rd!];
      case 'jr':
        npc = _u(r[i.rd!]);
      case 'jalr':
        lr = next;
        npc = _u(r[i.rd!]);
      case 'jplr':
        npc = lr;
      case 'nop' || 'sync':
        break;
      case 'push':
        cycles += i.regs!.length - 1; // one memory access per register
        for (final reg in _order(i.regs!).reversed) {
          stackPtr = _s(stackPtr - 4);
          write32(stackPtr, _readReg(reg, next));
        }
      case 'pop':
        cycles += i.regs!.length - 1;
        for (final reg in _order(i.regs!)) {
          final x = read32(stackPtr);
          stackPtr = _s(stackPtr + 4);
          if (reg == '%pc') {
            npc = _u(x);
          } else {
            _writeReg(reg, x);
          }
        }
      default:
        throw EmuError('unsupported instruction ${format(i)} at 0x${pc.toRadixString(16)}');
    }
    pc = npc;
  }

  /// Push stores the highest-numbered register first, so the lowest ends at the lowest
  /// address; the special-register group counts CR0 as 0 up to SR as 7.
  List<String> _order(List<String> regs) {
    int key(String x) => x.startsWith('%R') ? int.parse(x.substring(2)) : 7 - sprBits.indexOf(x);
    return [...regs]..sort((a, b) => key(a).compareTo(key(b)));
  }

  int _readReg(String reg, int next) => switch (reg) {
        '%lr' => lr,
        '%pc' => next,
        '%mh' => mh,
        '%ml' => ml,
        '%er' => 0, // the core folds LERI; pushing ER pushes 0
        _ when reg.startsWith('%R') => r[int.parse(reg.substring(2))],
        _ => throw EmuError('push $reg unsupported'),
      };

  void _writeReg(String reg, int x) {
    switch (reg) {
      case '%lr':
        lr = _u(x);
      case '%mh':
        mh = x;
      case '%ml':
        ml = x;
      case '%er':
        break;
      default:
        if (!reg.startsWith('%R')) throw EmuError('pop $reg unsupported');
        r[int.parse(reg.substring(2))] = x;
    }
  }
}

/// A stage ready to run: blob at its slot, ctx and the sine table in DSPM, stack at the
/// top of DSPM (as the resident has it).
class StageRunner {
  static const ctxAddr = Cpu.dspm + 0x1000, sinAddr = Cpu.dspm + 0x1400, stackTop = Cpu.dspm + 0x10000;
  final int slot;
  final List<int> blob;
  StageRunner(this.blob, {this.slot = 0}) {
    if (blob.length > slotBytes) throw ArgumentError('blob larger than a slot');
  }

  /// Runs the stage once. Returns the 16 outputs, and the cycle estimate in [stats].
  List<int> run(Map<String, int> inputs, {List<int>? outInit, Map<String, int>? stats}) {
    final cpu = Cpu();
    cpu.load(slotAddr[slot]!, blob);
    for (var k = 0; k < 256; k++) {
      cpu.write16(sinAddr + 2 * k, sin256[k]);
    }
    for (final e in ctxInput.entries) {
      cpu.write32(ctxAddr + e.value, inputs[e.key] ?? 0);
    }
    final init = outInit ?? List.filled(16, 0);
    for (var k = 0; k < 16; k++) {
      cpu.write32(ctxAddr + ctxOut + 4 * k, init[k]);
    }
    cpu.write32(ctxAddr + ctxSin, sinAddr);
    cpu.stackPtr = stackTop;
    final saved = [for (final k in [0, 1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14]) k];
    for (final k in saved) {
      cpu.r[k] = 0x5A5A0000 + k; // detect callee-saved registers the stage fails to restore
    }
    cpu.call(slotAddr[slot]!, ctxAddr);
    for (final k in saved) {
      if (cpu.r[k] != 0x5A5A0000 + k) throw EmuError('stage clobbered callee-saved R$k');
    }
    if (cpu.stackPtr != stackTop) throw EmuError('stage returned with SP off by ${cpu.stackPtr - stackTop}');
    stats?['cycles'] = cpu.cycles;
    stats?['insns'] = cpu.insns;
    return [for (var k = 0; k < 16; k++) cpu.read32(ctxAddr + ctxOut + 4 * k)];
  }
}
