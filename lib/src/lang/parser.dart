// Lexer and parser, a port of zephyr_scion tools/imcu/shader.py (same tokens, precedence,
// constant rounding and name rules) with one fix: `else` works as the language reference
// documents (shader.py's accept() only matches operator tokens, so it rejects `else`).
import '../abi.dart';
import '../registers.dart' as reg_inc;
import '../registers.dart' show Register;
import 'ast.dart';

class ShaderSyntaxError implements Exception {
  final String message;
  final int? line;

  /// 1-based column of the offending token, when known.
  final int? column;
  ShaderSyntaxError(this.message, [this.line, this.column]);
  @override
  String toString() => line == null ? 'syntax error: $message' : 'line $line: $message';
}

const functions = {
  'sin': 1, 'cos': 1, 'atan2': 2, 'sqrt': 1, 'abs': 1, 'min': 2, 'max': 2, 'clamp': 3,
  'floor': 1, 'frac': 1, 'lerp': 3, 'smoothstep': 3, 'step': 2, 'sign': 1, 'noise': 2, 'mod': 2,
};
const constants = {'pi': 3.141592653589793, 'tau': 6.283185307179586};
const precedence = {
  '||': 1, '&&': 2, '==': 3, '!=': 3, '<': 4, '<=': 4, '>': 4, '>=': 4,
  '+': 5, '-': 5, '*': 6, '/': 6, '%': 6,
};
const outModes = {'raw': 0, 'gain': 1, 'add': 2, 'unit': 3, 'strobe': 4};

/// Python's round(v * 65536): halves go to the even neighbour.
int q16(double v) {
  final x = v * 65536;
  final f = x.floorToDouble();
  final d = x - f;
  final n = f.toInt();
  if (d > 0.5) return n + 1;
  if (d < 0.5) return n;
  return n.isEven ? n : n + 1;
}

enum _K { num, id, op, eof }

class _Tok {
  final _K k;
  final String s;
  final int line, col;
  const _Tok(this.k, this.s, this.line, [this.col = 0]);
  @override
  String toString() => k == _K.eof ? 'end of input' : '"$s"';
}

final _tokRe = RegExp(r'\s*(?:(//[^\n]*)|(\d+\.\d*|\.\d+|\d+)|([A-Za-z_]\w*)|(<=|>=|==|!=|&&|\|\||[-+*/%<>=!(){};,.]))');

List<_Tok> _lex(String src) {
  final out = <_Tok>[];
  var pos = 0, line = 1, lineStart = 0;
  // line and column of the token starting at [p] (advancing over the newlines before it)
  (int, int) at(int p) {
    for (var k = lineStart; k < p; k++) {
      if (src.codeUnitAt(k) == 10) {
        line++;
        lineStart = k + 1;
      }
    }
    return (line, p - lineStart + 1);
  }

  while (pos < src.length) {
    final m = _tokRe.matchAsPrefix(src, pos);
    if (m == null) {
      var p = pos;
      while (p < src.length && ' \t\r\n'.contains(src[p])) {
        p++;
      }
      if (p >= src.length) break;
      final (l, c) = at(p);
      throw ShaderSyntaxError('bad token at "${src.substring(p, (p + 20).clamp(0, src.length))}"', l, c);
    }
    pos = m.end;
    if (m.group(1) != null) continue;
    final text = m.group(2) ?? m.group(3) ?? m.group(4)!;
    final (l, c) = at(m.end - text.length);
    out.add(_Tok(m.group(2) != null ? _K.num : (m.group(3) != null ? _K.id : _K.op), text, l, c));
  }
  final (l, c) = at(src.length);
  out.add(_Tok(_K.eof, '', l, c));
  return out;
}

/// Parses a stage. `@out` lines (scan stage) name output slots; those names take precedence
/// over the built-in output names, as in shader.py. An `@out` line is either
/// `@out <output> <reg> <mask> <shift> <mode>` or `@out <output> <register name> [mode]`, the
/// name a row of [registers] (default: tools/imcu/registers.inc as compiled in).
Program parse(String src, {Map<String, Register>? registers}) {
  final (body, outMap, outNames) = _outMap(src, registers ?? reg_inc.registers);
  final p = _Parser(_lex(body), {...outputSlot, ...outNames});
  final stmts = <Stmt>[];
  while (p.peek.k != _K.eof) {
    stmts.add(p.stmt());
  }
  return Program(stmts, p.locals, outMap, outNames);
}

final _outRe = RegExp(r'^\s*@out\s+(\w+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\w+)\s*;?\s*(//.*)?$');
final _outNamedRe = RegExp(r'^\s*@out\s+(\w+)\s+([A-Za-z_]\w*)(?:\s+(\w+))?\s*;?\s*(//.*)?$');

(String, List<OutMapEntry>, Map<String, int>) _outMap(String src, Map<String, Register> registers) {
  final entries = <OutMapEntry>[];
  final names = <String, int>{};
  final kept = <String>[];
  final lines = src.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final m = _outRe.firstMatch(lines[i]);
    final mn = m == null ? _outNamedRe.firstMatch(lines[i]) : null;
    if (m == null && mn == null) {
      kept.add(lines[i]);
      continue;
    }
    kept.add(''); // keep line numbers
    int n(String s) => s.startsWith('0x') || s.startsWith('0X') ? int.parse(s.substring(2), radix: 16) : int.parse(s);
    final String name, mode;
    final int reg, mask, shift;
    if (m != null) {
      (name, mode) = (m.group(1)!, m.group(5)!);
      (reg, mask, shift) = (n(m.group(2)!), n(m.group(3)!), n(m.group(4)!));
    } else {
      // @out <output> <register name> [mode]: reg, mask, shift from the row, mode from the
      // line or the row's default
      name = mn!.group(1)!;
      final r = registers[mn.group(2)!] ??
          (throw ShaderSyntaxError('@out $name: unknown register name ${mn.group(2)} (see tools/imcu/registers.inc)', i + 1));
      mode = mn.group(3) ?? r.mode;
      (reg, mask, shift) = (r.reg, r.mask, r.shift);
    }
    final modeN = outModes[mode] ?? (throw ShaderSyntaxError('@out $name: mode $mode? (raw gain add unit strobe)', i + 1));
    names.putIfAbsent(name, () => names.length);
    entries.add(OutMapEntry(reg, mask, shift, modeN, names[name]!));
  }
  if (names.length > 16) throw ShaderSyntaxError('more than 16 named outputs');
  return (kept.join('\n'), entries, names);
}

class _Parser {
  final List<_Tok> t;
  final Map<String, int> outs;
  final locals = <String>[];
  var i = 0;
  _Parser(this.t, this.outs);

  _Tok get peek => t[i];

  _Tok take([_K? k, String? s]) {
    final tok = t[i];
    if ((k != null && tok.k != k) || (s != null && tok.s != s)) {
      throw ShaderSyntaxError('expected ${s ?? k!.name}, got $tok', tok.line, tok.col);
    }
    i++;
    return tok;
  }

  bool accept(String s) {
    if ((peek.k == _K.op || peek.k == _K.id) && peek.s == s) {
      i++;
      return true;
    }
    return false;
  }

  Expr expr([int minp = 1]) {
    var left = unary();
    while (peek.k == _K.op && precedence.containsKey(peek.s) && precedence[peek.s]! >= minp) {
      final op = take().s;
      final right = expr(precedence[op]! + 1);
      left = Binary(op, left, right);
    }
    return left;
  }

  Expr unary() {
    if (peek.k == _K.op && accept('-')) return Unary('-', unary());
    if (peek.k == _K.op && accept('!')) return Unary('!', unary());
    return primary();
  }

  Expr primary() {
    final tok = take();
    if (tok.k == _K.num) {
      // shader.py passes larger constants to C as literals that do not fit an int, which
      // C89 types as unsigned long: comparisons with them silently turn unsigned.
      final q = q16(double.parse(tok.s));
      if (q > 0x7fffffff) throw ShaderSyntaxError('constant ${tok.s} is outside the Q16 range (max 32767.99998)', tok.line, tok.col);
      return Num(q);
    }
    if (tok.k == _K.op && tok.s == '(') {
      final e = expr();
      take(_K.op, ')');
      return e;
    }
    if (tok.k == _K.id) {
      final name = tok.s;
      if (name == 'in') {
        take(_K.op, '.');
        final f = take(_K.id);
        if (!ctxInput.containsKey(f.s)) throw ShaderSyntaxError('unknown input in.${f.s}', f.line, f.col);
        return In(f.s);
      }
      if (name == 'out') {
        take(_K.op, '.');
        final f = take(_K.id);
        return OutRead(outs[f.s] ?? (throw ShaderSyntaxError('unknown output out.${f.s}', f.line, f.col)));
      }
      if (constants.containsKey(name)) return Num(q16(constants[name]!));
      if (functions.containsKey(name)) {
        take(_K.op, '(');
        final args = [expr()];
        while (peek.k == _K.op && accept(',')) {
          args.add(expr());
        }
        take(_K.op, ')');
        if (args.length != functions[name]) {
          throw ShaderSyntaxError('$name takes ${functions[name]} args', tok.line, tok.col);
        }
        return Call(name, args);
      }
      if (locals.contains(name)) return Local(name);
      throw ShaderSyntaxError('unknown name $name', tok.line, tok.col);
    }
    throw ShaderSyntaxError('unexpected $tok', tok.line, tok.col);
  }

  List<Stmt> block() {
    take(_K.op, '{');
    final out = <Stmt>[];
    while (!(peek.k == _K.op && accept('}'))) {
      if (peek.k == _K.eof) throw ShaderSyntaxError('missing }', peek.line, peek.col);
      out.add(stmt());
    }
    return out;
  }

  Stmt stmt() {
    final tok = peek;
    if (tok.k == _K.id && tok.s == 'let') {
      take();
      final name = take(_K.id).s;
      take(_K.op, '=');
      if (!locals.contains(name)) locals.add(name);
      final e = expr();
      take(_K.op, ';');
      return Assign(name, e, line: tok.line);
    }
    if (tok.k == _K.id && tok.s == 'if') {
      take();
      take(_K.op, '(');
      final c = expr();
      take(_K.op, ')');
      final body = block();
      var els = <Stmt>[];
      if (peek.k == _K.id && accept('else')) {
        els = peek.k == _K.id && peek.s == 'if' ? [stmt()] : block();
      }
      return If(c, body, els, line: tok.line);
    }
    if (tok.k == _K.id && tok.s == 'out') {
      take();
      take(_K.op, '.');
      final f = take(_K.id);
      final slot = outs[f.s] ?? (throw ShaderSyntaxError('unknown output out.${f.s}', f.line, f.col));
      take(_K.op, '=');
      final e = expr();
      take(_K.op, ';');
      return OutAssign(slot, e, line: tok.line);
    }
    if (tok.k == _K.id && locals.contains(tok.s)) {
      final name = take().s;
      take(_K.op, '=');
      final e = expr();
      take(_K.op, ';');
      return Assign(name, e, line: tok.line);
    }
    throw ShaderSyntaxError('unexpected statement at $tok', tok.line, tok.col);
  }
}
