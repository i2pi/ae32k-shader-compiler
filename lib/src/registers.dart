// Named MDIN registers for `@out <output> <name> [mode]` lines: the rows of zephyr_scion's
// tools/imcu/registers.inc (name reg mask shift default-mode granularity description; `#`
// comments), parsed exactly as shader.py's REGISTERS() does.
import 'registers_inc.dart';

class Register {
  final String name, mode, granularity, description;
  final int reg, mask, shift;
  const Register(this.name, this.reg, this.mask, this.shift, this.mode, this.granularity, this.description);
}

int _int(String s) => s.startsWith('0x') || s.startsWith('0X') ? int.parse(s.substring(2), radix: 16) : int.parse(s);

/// Parses registers.inc text; rows with fewer than six columns are skipped, as in shader.py.
Map<String, Register> parseRegisters(String text) {
  final out = <String, Register>{};
  for (final raw in text.split('\n')) {
    final line = raw.split('#').first.trim();
    if (line.isEmpty) continue;
    final f = line.split(RegExp(r'\s+'));
    if (f.length < 6) continue;
    out[f[0]] = Register(f[0], _int(f[1]), _int(f[2]), _int(f[3]), f[4], f[5], f.skip(6).join(' '));
  }
  return out;
}

/// The table compiled into the package (tool/gen_registers.dart).
final Map<String, Register> registers = parseRegisters(registersInc);

/// Per-Send PIP area ports, resolved by the firmware when the map is set:
/// `send<N>.pip<M>.<field>` (Send 1..3, PIP layer 1..4). A layer's blend stage depends on how
/// many layers are enabled and each Send has its own output channel, so the map carries a
/// symbolic register, 0xF000 | kind << 8 | send << 4 | layer (kind 0 = area address port,
/// 1 = area data port), and the resident's map setter turns it into the port address.
const pipFields = {
  'area_addr': (0, 0xFFFF, 0, 'PIP area address port (area select and field address)'),
  'area_data': (1, 0xFFFF, 0, 'PIP area data port (the value written to the selected field)'),
  'area_wr': (0, 0x8000, 15, 'PIP area address port, write strobe bit'),
  'area_val': (1, 0x1FFF, 0, 'PIP area data port, 13-bit value field'),
};

final _pipRe = RegExp(r'^send(\d+)\.pip(\d+)\.(\w+)$');

/// A `send<N>.pip<M>.<field>` name as a register; null for anything else. Throws a
/// [FormatException] for a well-formed name out of range (Send 1..3, layer 1..4, a known field).
Register? symbolicRegister(String name) {
  final m = _pipRe.firstMatch(name);
  if (m == null) return null;
  final send = int.parse(m.group(1)!), layer = int.parse(m.group(2)!);
  final f = pipFields[m.group(3)!];
  if (send < 1 || send > 3) throw FormatException('$name: Send $send? (1..3)');
  if (layer < 1 || layer > 4) throw FormatException('$name: PIP layer $layer? (1..4)');
  if (f == null) throw FormatException('$name: field ${m.group(3)}? (${pipFields.keys.join(', ')})');
  final (kind, mask, shift, what) = f;
  return Register(name, 0xF000 | kind << 8 | send << 4 | layer, mask, shift, 'raw', 'port',
      'Send $send, PIP $layer: $what (resolved by the firmware)');
}

/// A named register: a registers.inc row or a symbolic per-Send name.
Register? lookupRegister(String name, [Map<String, Register>? table]) => (table ?? registers)[name] ?? symbolicRegister(name);
