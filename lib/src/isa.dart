// AE32000 (EISC) instruction set: encoder and decoder.
//
// Encodings from ADChips' AE32000C-Lucida user guide, Table 2.3; immediate-extension
// rules and LERI counts from the vendor assembler (test/golden/gas.txt), which is
// what built the code that runs on the device. See docs/AE32000_ISA.md.
//
// Where gas silently corrupts an operand (misaligned offsets, odd MUL destinations,
// shift counts of 32) the encoder throws instead. Forms gas encodes with three LERIs
// are not emitted: that composition has not been checked on hardware.

/// Register numbers 0..15 are %R0..%R15; [sp] stands for %SP as a memory base.
const sp = -1;

class EncodeError implements Exception {
  final String message;
  EncodeError(this.message);
  @override
  String toString() => 'EncodeError: $message';
}

/// One instruction, without its LERI prefixes (the encoder adds those as needed).
///
/// Field meaning per form:
/// - memory: [rd] data register (loaded or stored), [rb] base register or [sp], [imm] offset
/// - ALU / shift / ldi / lea / mrs / rotate: [rd] destination, [rs] source register,
///   or [imm] when the source is an immediate
/// - branches: [target] absolute address
/// - push/pop: [regs] register names ('%R3', '%lr', ...), one group per instruction
class Insn {
  final String m;
  final int? rd, rs, rb, imm, target;
  final List<String>? regs;
  const Insn(this.m, {this.rd, this.rs, this.rb, this.imm, this.target, this.regs});

  @override
  bool operator ==(Object other) =>
      other is Insn && other.m == m && other.rd == rd && other.rs == rs && other.rb == rb &&
      other.imm == imm && other.target == target && _listEq(other.regs, regs);
  @override
  int get hashCode => Object.hash(m, rd, rs, rb, imm, target, regs?.join(','));
  @override
  String toString() => format(this);
}

bool _listEq(List<String>? a, List<String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------- tables

/// Memory forms. Unextended: `field * scale`. Extended: `ER << erShift | field << scale`.
class MemForm {
  final int base, fieldBits, fieldShift, scale, erShift;
  final bool store, spBase;
  const MemForm(this.base, this.fieldBits, this.fieldShift, this.scale, this.erShift,
      {this.store = false, this.spBase = false});
}

const memIdx = {
  'ld': MemForm(0x0000, 4, 4, 4, 4),
  'st': MemForm(0x1000, 4, 4, 4, 4, store: true),
  'ldb': MemForm(0x2000, 3, 4, 1, 3),
  'lds': MemForm(0x2080, 3, 4, 2, 4),
  'stb': MemForm(0x3000, 3, 4, 1, 3, store: true),
  'sts': MemForm(0x3080, 3, 4, 2, 4, store: true),
  'ldbu': MemForm(0x8000, 3, 4, 1, 3),
  'ldsu': MemForm(0x8080, 3, 4, 2, 4),
};
const memSp = {
  'ld': MemForm(0x9000, 7, 0, 4, 4, spBase: true),
  'st': MemForm(0x9080, 7, 0, 4, 4, store: true, spBase: true),
  'ldb': MemForm(0xE800, 3, 4, 1, 3, spBase: true),
  'lds': MemForm(0xE880, 3, 4, 2, 4, spBase: true),
  'ldbu': MemForm(0xE900, 3, 4, 1, 3, spBase: true),
  'ldsu': MemForm(0xE980, 3, 4, 2, 4, spBase: true),
  'stb': MemForm(0xEA00, 3, 4, 1, 3, store: true, spBase: true),
  'sts': MemForm(0xEA80, 3, 4, 2, 4, store: true, spBase: true),
};

/// `op %Rs/imm, %Rd` with the destination in bits 7:4 and the source in 3:0.
/// An immediate source always takes a LERI: `ER << 4 | field`.
const alu = {
  'add': 0xB800, 'adc': 0xB900, 'sub': 0xBA00, 'sbc': 0xBB00,
  'and': 0xBC00, 'or': 0xBD00, 'xor': 0xBE00, 'cmp': 0xBF00,
  'tst': 0xE300, 'mac': 0xE700,
  'macb': 0xF000, 'macs': 0xF100, 'msopb': 0xF200, 'msops': 0xF300,
  'saddb': 0xF400, 'sadds': 0xF500, 'sadub': 0xF600, 'sadus': 0xF700, 'sadd': 0xF800,
};

/// As [alu] but with a 3-bit destination in bits 7:5 (bit 4 selects the operation).
/// MUL/MULU's field names an even register (field * 2); the others R0..R7.
const alu3 = {'avgb': 0xE200, 'avgs': 0xE210, 'mul': 0xE600, 'mulu': 0xE610, 'min': 0xFA00, 'max': 0xFA10};
const alu3Even = {'mul', 'mulu'};

/// Immediates gas loads with one LERI only up to 13 signed bits (the rest use 14).
const narrowImm = {'tst', 'mac', 'mul', 'mulu'};

const shifts = {'asr': 0, 'lsr': 1, 'asl': 2, 'ssl': 3};
const quick = {'addq': 0xC0C0, 'cmpq': 0xC0E0};

const branches = [
  'jnv', 'jv', 'jp', 'jm', 'jnz', 'jz', 'jnc', 'jc',
  'jgt', 'jlt', 'jge', 'jle', 'jhi', 'jls', 'jmp', 'jal',
];

/// Single-register instructions, register in bits 3:0.
const reg1 = {
  'extb': 0xE000, 'exts': 0xE010, 'mfmre': 0xE020, 'mtmre': 0xE030, 'cvb': 0xE040, 'cvs': 0xE050,
  'neg': 0xE060, 'not': 0xE070, 'jr': 0xE080, 'jalr': 0xE090,
  'cnt0': 0xE100, 'cnt1': 0xE110, 'mtml': 0xE140, 'mtmh': 0xE150, 'mfml': 0xE160, 'mfmh': 0xE170,
  'mtcr0': 0xE180, 'mtcr1': 0xE190, 'mfcr0': 0xE1E0, 'mfcr1': 0xE1F0, 'abs': 0xFB00,
};
const none = {'jplr': 0xE0A0, 'nop': 0xE0B0, 'sync': 0xE1A0};

/// 4-bit immediate in bits 3:0.
const imm4 = {'swi': 0xE0C0, 'halt': 0xE0E0, 'set': 0xE120, 'clr': 0xE130};

/// PUSH/POP special-register group, bit 7 down to bit 0.
const sprBits = ['%sr', '%pc', '%lr', '%er', '%mh', '%ml', '%cr1', '%cr0'];

// ---------------------------------------------------------------- LERI helpers

int sext(int v, int bits) {
  final m = 1 << (bits - 1);
  return (v & ((1 << bits) - 1) ^ m) - m;
}

int s32(int v) => sext(v, 32);

bool _fits(int v, int bits) => v >= -(1 << (bits - 1)) && v < (1 << (bits - 1));

/// LERI words that load [er]. gas uses one LERI over the whole 14-bit signed range for
/// most forms, but only 13 bits for memory offsets ([narrow]); two LERIs give 28 bits.
List<int> leris(int er, {bool narrow = false}) {
  if (narrow ? _fits(er, 13) : _fits(er, 14)) return [0x4000 | (er & 0x3fff)];
  if (!_fits(er, 28)) throw EncodeError('extension $er needs more than two LERIs');
  return [0x4000 | ((er >> 14) & 0x3fff), 0x4000 | (er & 0x3fff)];
}

void _reg(int? r, String what, {int max = 15}) {
  if (r == null || r < 0 || r > max) throw EncodeError('$what: register R$r out of range 0..$max');
}

// ---------------------------------------------------------------- encoder

/// Encodes [i] at address [addr] (needed for branches), LERIs included.
List<int> encode(Insn i, [int addr = 0]) {
  final m = i.m;
  final mem = i.rb == sp ? memSp[m] : memIdx[m];
  if (mem != null) return _encodeMem(i, mem);
  if (m == 'ldi') {
    _reg(i.rd, m);
    final v = s32(i.imm!);
    if (_fits(v, 8)) return [0xA000 | i.rd! << 8 | (v & 0xff)];
    return [...leris(v >> 4), 0xA000 | i.rd! << 8 | (v & 0xf)];
  }
  if (alu.containsKey(m)) {
    _reg(i.rd, m);
    final w = alu[m]! | i.rd! << 4;
    if (i.imm == null) {
      _reg(i.rs, m);
      return [w | i.rs!];
    }
    final v = s32(i.imm!);
    return [...leris(v >> 4, narrow: narrowImm.contains(m)), w | (v & 0xf)];
  }
  if (alu3.containsKey(m)) {
    final even = alu3Even.contains(m);
    _reg(i.rd, m, max: even ? 14 : 7);
    if (even && i.rd!.isOdd) throw EncodeError('$m: destination must be an even register');
    final w = alu3[m]! | (even ? i.rd! ~/ 2 : i.rd!) << 5;
    if (i.imm == null) {
      _reg(i.rs, m);
      return [w | i.rs!];
    }
    final v = s32(i.imm!);
    return [...leris(v >> 4, narrow: narrowImm.contains(m)), w | (v & 0xf)];
  }
  if (shifts.containsKey(m)) {
    _reg(i.rd, m);
    final w = 0xC000 | i.rd! << 8 | shifts[m]!;
    if (i.imm == null) {
      _reg(i.rs, m);
      return [w | 0x80 | i.rs! << 2];
    }
    if (i.imm! < 0 || i.imm! > 31) throw EncodeError('$m: shift count ${i.imm} out of range 0..31');
    return [w | i.imm! << 2];
  }
  if (quick.containsKey(m)) {
    _reg(i.rd, m);
    if (!_fits(i.imm!, 5)) throw EncodeError('$m: ${i.imm} out of range -16..15');
    return [quick[m]! | i.rd! << 8 | (i.imm! & 0x1f)];
  }
  final b = branches.indexOf(m);
  if (b >= 0) return _encodeBranch(0xD000 | b << 8, i.target! - addr);
  if (reg1.containsKey(m)) {
    _reg(i.rd, m);
    return [reg1[m]! | i.rd!];
  }
  if (none.containsKey(m)) return [none[m]!];
  if (imm4.containsKey(m)) {
    if (i.imm! < 0 || i.imm! > 15) throw EncodeError('$m: ${i.imm} out of range 0..15');
    return [imm4[m]! | i.imm!];
  }
  switch (m) {
    case 'leri':
      return [0x4000 | (i.imm! & 0x3fff)];
    case 'lea':
      if (i.rb == sp || i.rd == sp) {
        if (i.rb != sp || i.rd != sp) {
          // LSEA (%Rn,imm),%SP / LESA (%SP,imm),%Rd: the offset is ER itself, as for E4
          final r = i.rb == sp ? i.rd : i.rb;
          _reg(r, m);
          final w = (i.rb == sp ? 0xE1D0 : 0xE1C0) | r!;
          final v = s32(i.imm ?? 0);
          return v == 0 ? [w] : [...leris(v), w];
        }
        final v = s32(i.imm!);
        if (v % 4 != 0) throw EncodeError('lea (%SP,$v): offset must be a multiple of 4');
        if (_fits(v >> 2, 8)) return [0xB600 | ((v >> 2) & 0xff)];
        return [...leris(v >> 4), 0xB600 | ((v >> 2) & 3)];
      }
      _reg(i.rd, m);
      _reg(i.rb, m);
      final v = s32(i.imm ?? 0);
      final w = 0xE400 | i.rd! << 4 | i.rb!;
      if (v == 0) return [w];
      return [...leris(v), w];
    case 'mrs':
      _reg(i.rd, m);
      if (i.imm! < 0 || i.imm! > 7) throw EncodeError('mrs: ${i.imm} out of range 0..7');
      return [0xB700 | i.imm! << 4 | i.rd!];
    case 'rol' || 'ror':
      _reg(i.rd, m);
      final w = (m == 'rol' ? 0xE580 : 0xE500) | i.rd!;
      final v = i.imm!;
      if (v < 0 || v > 31) throw EncodeError('$m: count $v out of range 0..31');
      if (v < 8) return [w | v << 4];
      return [...leris(v >> 3), w | (v & 7) << 4];
    case 'push' || 'pop':
      return [_encodeList(m, i.regs!)];
  }
  throw EncodeError('unknown instruction $m');
}

List<int> _encodeMem(Insn i, MemForm f) {
  _reg(i.rd, i.m);
  if (!f.spBase) _reg(i.rb, i.m);
  final v = s32(i.imm ?? 0);
  if (v % f.scale != 0) throw EncodeError('${i.m}: offset $v is not a multiple of ${f.scale}');
  var w = f.base | i.rd! << 8 | (f.spBase ? 0 : i.rb!);
  if (f.spBase && f.fieldShift == 4) w = f.base | i.rd!; // E8..EA: register in 3:0
  final field = v ~/ f.scale;
  if (field >= 0 && field < (1 << f.fieldBits)) return [w | field << f.fieldShift];
  final low = (v & ((1 << f.erShift) - 1)) >> (f.scale == 4 ? 2 : f.scale == 2 ? 1 : 0);
  return [...leris(v >> f.erShift, narrow: true), w | low << f.fieldShift];
}

List<int> _encodeBranch(int w, int dist) {
  // dist is from the first word of the sequence; the branch itself follows its LERIs
  // and jumps relative to its own address + 2, in halfwords.
  if (dist.isOdd) throw EncodeError('branch distance $dist is odd');
  final d0 = (dist - 2) >> 1;
  if (_fits(d0, 8)) return [w | (d0 & 0xff)];
  final d1 = (dist - 4) >> 1;
  if (_fits(d1 >> 8, 14)) return [0x4000 | ((d1 >> 8) & 0x3fff), w | (d1 & 0xff)];
  final d2 = (dist - 6) >> 1;
  return [...leris(d2 >> 8), w | (d2 & 0xff)];
}

int _encodeList(String m, List<String> regs) {
  final pop = m == 'pop' ? 0x100 : 0;
  final gprs = [for (final r in regs) if (r.startsWith('%R')) int.parse(r.substring(2))];
  if (gprs.isEmpty) {
    var mask = 0;
    for (final r in regs) {
      final b = sprBits.indexOf(r);
      if (b < 0) throw EncodeError('$m: unknown register $r');
      mask |= 0x80 >> b;
    }
    return 0xB400 | pop | mask;
  }
  if (gprs.length != regs.length) throw EncodeError('$m: GPRs and special registers need separate instructions');
  final hi = gprs.every((r) => r >= 8 && r <= 15);
  if (!hi && !gprs.every((r) => r >= 0 && r <= 7)) {
    throw EncodeError('$m: R0..R7 and R8..R15 need separate instructions');
  }
  var mask = 0;
  for (final r in gprs) {
    mask |= 1 << (r & 7);
  }
  return (hi ? 0xB200 : 0xB000) | pop | mask;
}

// ---------------------------------------------------------------- decoder

class Decoded {
  final Insn insn;
  final int length; // words, LERIs included
  const Decoded(this.insn, this.length);
}

/// Decodes the instruction starting at [words][i], folding any LERI prefixes into it.
/// [addr] is the byte address of words[i] (for branch targets).
Decoded decode(List<int> words, int i, [int addr = 0]) {
  final pre = <int>[];
  var j = i;
  while (j < words.length && words[j] & 0xC000 == 0x4000) {
    pre.add(words[j] & 0x3fff);
    j++;
  }
  if (j >= words.length || pre.length > 3) return Decoded(Insn('leri', imm: words[i] & 0x3fff), 1);
  final w = words[j];
  final insn = _decodeOne(w, pre, addr + 2 * pre.length);
  if (insn == null) {
    // the instruction does not take an extension (or not this many): LERI stands alone
    if (pre.isNotEmpty) return Decoded(Insn('leri', imm: words[i] & 0x3fff), 1);
    return Decoded(Insn('.short', imm: w), 1);
  }
  return Decoded(insn, pre.length + 1);
}

/// ER from 1 or 2 LERIs; null when there are none.
int? _er(List<int> pre) => switch (pre.length) {
      0 => null,
      1 => sext(pre[0], 14),
      2 => s32(sext(pre[0], 14) << 14 | pre[1]),
      3 => s32(sext(pre[0], 14) << 28 | pre[1] << 14 | pre[2]), // gas: byte offsets past 28 bits
      _ => null,
    };

Insn? _decodeOne(int w, List<int> pre, int addr) {
  final n = pre.length;
  final er = _er(pre);
  final hi4 = w >> 12;
  final rA = (w >> 8) & 0xf, rB = (w >> 4) & 0xf, rC = w & 0xf;

  Insn? mem(String m, MemForm f, int rd, int rb, int field) {
    final int v;
    if (er == null) {
      v = field * f.scale;
    } else {
      // gas only puts the bits below erShift in the field; mirror objdump for the rest
      final sh = f.scale == 4 ? 2 : f.scale == 2 ? 1 : 0;
      v = s32(er << f.erShift | ((field << sh) & ((1 << f.erShift) - 1)));
    }
    return Insn(m, rd: rd, rb: rb, imm: v);
  }

  for (final e in memIdx.entries) {
    final f = e.value;
    final mask = f.fieldBits == 4 ? 0xF000 : 0xF080;
    if (w & mask == f.base) return mem(e.key, f, rA, rC, (w >> 4) & ((1 << f.fieldBits) - 1));
  }
  if (hi4 == 0x9) {
    final f = memSp[w & 0x80 != 0 ? 'st' : 'ld']!;
    return mem(w & 0x80 != 0 ? 'st' : 'ld', f, rA, sp, w & 0x7f);
  }
  if (w & 0xFE00 == 0xE800 || w & 0xFF00 == 0xEA00) {
    for (final e in memSp.entries) {
      if (e.value.fieldShift == 4 && w & 0xFF80 == e.value.base) return mem(e.key, e.value, rC, sp, (w >> 4) & 7);
    }
  }
  if (hi4 == 0xA) {
    if (n > 2) return null;
    return Insn('ldi', rd: rA, imm: er == null ? sext(w & 0xff, 8) : s32(er << 4 | (w & 0xf)));
  }
  if (w & 0xFE00 == 0xB000 || w & 0xFE00 == 0xB200 || w & 0xFE00 == 0xB400) {
    if (n > 0) return null;
    final m = w & 0x100 != 0 ? 'pop' : 'push';
    final mask = w & 0xff;
    final List<String> regs;
    if (w & 0xFE00 == 0xB400) {
      regs = [for (var b = 0; b < 8; b++) if (mask & (0x80 >> b) != 0) sprBits[b]];
    } else {
      final base = w & 0xFE00 == 0xB200 ? 8 : 0;
      regs = [for (var b = 0; b < 8; b++) if (mask & (1 << b) != 0) '%R${base + b}'];
    }
    return Insn(m, regs: regs);
  }
  if (w & 0xFF00 == 0xB600) {
    if (n > 2) return null;
    final v = er == null ? sext(w & 0xff, 8) * 4 : s32(er << 4 | (w & 3) << 2);
    return Insn('lea', rd: sp, rb: sp, imm: v);
  }
  if (w & 0xFF80 == 0xB700) return n > 0 ? null : Insn('mrs', rd: rC, imm: (w >> 4) & 7);
  for (final e in alu.entries) {
    if (w & 0xFF00 == e.value) {
      if (n > 2) return null;
      return er == null ? Insn(e.key, rd: rB, rs: rC) : Insn(e.key, rd: rB, imm: s32(er << 4 | rC));
    }
  }
  for (final e in alu3.entries) {
    if (w & 0xFF10 == e.value) {
      if (n > 2) return null;
      final f = (w >> 5) & 7;
      final rd = alu3Even.contains(e.key) ? f * 2 : f;
      return er == null ? Insn(e.key, rd: rd, rs: rC) : Insn(e.key, rd: rd, imm: s32(er << 4 | rC));
    }
  }
  if (hi4 == 0xC) {
    if (n > 0) return null;
    if (w & 0xC0 == 0xC0) {
      return Insn(w & 0x20 != 0 ? 'cmpq' : 'addq', rd: rA, imm: sext(w & 0x1f, 5));
    }
    final m = shifts.keys.elementAt(w & 3);
    if (w & 0x80 == 0) return Insn(m, rd: rA, imm: (w >> 2) & 0x1f);
    return Insn(m, rd: rA, rs: (w >> 2) & 0xf);
  }
  if (hi4 == 0xD) {
    if (n > 2) return null;
    final off = er == null ? sext(w & 0xff, 8) : s32(er << 8 | (w & 0xff));
    return Insn(branches[rA], target: s32(addr + 2 + off * 2));
  }
  for (final e in reg1.entries) {
    if (w & 0xFFF0 == e.value) return n > 0 ? null : Insn(e.key, rd: rC);
  }
  for (final e in none.entries) {
    if (w & 0xFFF0 == e.value) return n > 0 ? null : Insn(e.key);
  }
  for (final e in imm4.entries) {
    if (w & 0xFFF0 == e.value) return n > 0 ? null : Insn(e.key, imm: rC);
  }
  // LEA/LSEA/LESA take ER itself as the offset. With three LERIs gas composes
  // L1<<18 | L2<<4 | L3[3:0] (unverified on hardware; the encoder never emits it).
  final leaImm = n == 3 ? s32(sext(pre[0], 14) << 18 | pre[1] << 4 | (pre[2] & 0xf)) : er ?? 0;
  if (w & 0xFFE0 == 0xE1C0) {
    return w & 0x10 == 0 ? Insn('lea', rd: sp, rb: rC, imm: leaImm) : Insn('lea', rd: rC, rb: sp, imm: leaImm);
  }
  if (w & 0xFF00 == 0xE400) return Insn('lea', rd: rB, rb: rC, imm: leaImm);
  if (w & 0xFF00 == 0xE500) {
    if (n > 2) return null;
    final f = (w >> 4) & 7;
    return Insn(w & 0x80 != 0 ? 'rol' : 'ror', rd: rC, imm: er == null ? f : s32(er << 3 | f));
  }
  return null;
}

// ---------------------------------------------------------------- text

String _r(int r) => r == sp ? '%SP' : '%R$r';

/// gas syntax. Branch targets print as `.+d` relative to [addr] when given, else absolute.
String format(Insn i, [int? addr]) {
  final m = i.m;
  if (i.regs != null) return '$m ${i.regs!.join(',')}';
  if (i.target != null) {
    if (addr == null) return '$m 0x${i.target!.toRadixString(16)}';
    final d = i.target! - addr;
    return '$m .${d >= 0 ? '+' : ''}$d';
  }
  final isMem = (i.rb == sp ? memSp : memIdx).containsKey(m) && i.rb != null && m != 'lea';
  if (isMem) {
    final st = (i.rb == sp ? memSp : memIdx)[m]!.store;
    final a = '(${_r(i.rb!)},${i.imm})';
    return st ? '$m ${_r(i.rd!)},$a' : '$m $a,${_r(i.rd!)}';
  }
  if (m == 'lea') return 'lea (${_r(i.rb!)},${i.imm ?? 0}),${_r(i.rd!)}';
  if (m == '.short') return '.short 0x${i.imm!.toRadixString(16).padLeft(4, '0')}';
  if (m == 'leri') return 'leri 0x${i.imm!.toRadixString(16)}';
  if (i.rd == null) return i.imm == null ? m : '$m ${i.imm}';
  final src = i.imm != null ? '${i.imm}' : i.rs != null ? _r(i.rs!) : null;
  return src == null ? '$m ${_r(i.rd!)}' : '$m $src,${_r(i.rd!)}';
}

final _tok = RegExp(r'^\s*([a-z0-9.]+)\s*(.*?)\s*$');

/// Parses one line of gas syntax. Branch targets may be `.+d`/`.-d` (relative to [addr])
/// or a number.
Insn parse(String line, [int addr = 0]) {
  final mt = _tok.firstMatch(line);
  if (mt == null) throw FormatException('bad line: $line');
  final m = mt.group(1)!;
  final ops = mt.group(2)!;
  int reg(String s) {
    s = s.trim();
    if (s == '%SP') return sp;
    final r = RegExp(r'^%R(\d+)$').firstMatch(s);
    if (r == null) throw FormatException('expected a register, got "$s" in: $line');
    return int.parse(r.group(1)!);
  }

  int num(String s) {
    s = s.trim();
    final neg = s.startsWith('-');
    final t = neg ? s.substring(1) : s;
    final v = t.startsWith('0x') ? int.parse(t.substring(2), radix: 16) : int.parse(t);
    return neg ? -v : v;
  }

  bool isReg(String s) => s.trim().startsWith('%');

  if (branches.contains(m)) {
    final t = ops.trim();
    if (t.startsWith('.')) return Insn(m, target: addr + num(t.substring(1).replaceFirst('+', '')));
    return Insn(m, target: num(t));
  }
  if (m == 'push' || m == 'pop') return Insn(m, regs: [for (final r in ops.split(',')) r.trim()]);
  if (ops.isEmpty) return Insn(m);

  final memM = RegExp(r'^\((%\w+),([^)]+)\)$');
  final parts = <String>[];
  // split on commas outside parentheses
  var depth = 0, start = 0;
  for (var k = 0; k < ops.length; k++) {
    if (ops[k] == '(') depth++;
    if (ops[k] == ')') depth--;
    if (ops[k] == ',' && depth == 0) {
      parts.add(ops.substring(start, k).trim());
      start = k + 1;
    }
  }
  parts.add(ops.substring(start).trim());

  if (parts.length == 2 && parts.any((p) => p.startsWith('('))) {
    final memIsSrc = parts[0].startsWith('(');
    final mm = memM.firstMatch(memIsSrc ? parts[0] : parts[1]);
    if (mm == null) throw FormatException('bad memory operand in: $line');
    final rb = reg(mm.group(1)!), off = num(mm.group(2)!);
    final other = reg(memIsSrc ? parts[1] : parts[0]);
    return Insn(m, rd: other, rb: rb, imm: off);
  }
  if (parts.length == 1) {
    return isReg(parts[0]) ? Insn(m, rd: reg(parts[0])) : Insn(m, imm: num(parts[0]));
  }
  if (parts.length == 2) {
    final rd = reg(parts[1]);
    return isReg(parts[0]) ? Insn(m, rd: rd, rs: reg(parts[0])) : Insn(m, rd: rd, imm: num(parts[0]));
  }
  throw FormatException('cannot parse: $line');
}
