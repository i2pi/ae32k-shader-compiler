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
