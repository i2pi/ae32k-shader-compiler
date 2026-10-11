// Token spans for syntax highlighting. Lenient: it classifies whatever is typed, including
// half-finished code, and never throws.
import '../abi.dart';
import '../registers.dart' as reg_inc;
import 'parser.dart' show functions, constants, outModes;

enum TokenKind {
  comment, number, keyword, input, output, function, constant, local, op, directive, register, mode, unknown,
}

class Highlight {
  final int start, end;
  final TokenKind kind;
  const Highlight(this.start, this.end, this.kind);
  @override
  String toString() => '$kind[$start,$end)';
}

const _keywords = {'let', 'if', 'else'};
final _tok = RegExp(r'(//[^\n]*)|(\d+\.\d*|\.\d+|\d+)|([A-Za-z_]\w*)|(<=|>=|==|!=|&&|\|\||[-+*/%<>=!(){};,.])|(\S)');
final _outLine = RegExp(r'^([ \t]*)(@out)\b(.*)$', multiLine: true);

List<Highlight> highlight(String src) {
  final out = <Highlight>[];
  // @out directive lines first; the code scanner skips them
  final directive = <(int, int)>[];
  for (final m in _outLine.allMatches(src)) {
    final s = m.start + m.group(1)!.length;
    directive.add((s, m.end));
    out.add(Highlight(s, s + 4, TokenKind.directive));
    final rest = m.group(3)!;
    var off = s + 4;
    final c = rest.indexOf('//');
    final body = c >= 0 ? rest.substring(0, c) : rest;
    var field = 0;
    for (final w in RegExp(r'\S+').allMatches(body)) {
      final a = off + w.start, b = off + w.end, t = w.group(0)!;
      final kind = switch (field) {
        0 => TokenKind.output,
        _ when outModes.containsKey(t) => TokenKind.mode,
        _ when RegExp(r'^(0x[0-9a-fA-F]+|\d+)$').hasMatch(t) => TokenKind.number,
        1 => reg_inc.registers.containsKey(t) ? TokenKind.register : TokenKind.unknown,
        _ => TokenKind.unknown,
      };
      out.add(Highlight(a, b, kind));
      field++;
    }
    if (c >= 0) out.add(Highlight(off + c, m.end, TokenKind.comment));
  }
  bool inDirective(int p) => directive.any((d) => p >= d.$1 && p < d.$2);

  final locals = <String>{};
  String? prev, prev2;
  for (final m in _tok.allMatches(src)) {
    if (inDirective(m.start)) continue;
    final t = m.group(0)!;
    TokenKind kind;
    if (m.group(1) != null) {
      kind = TokenKind.comment;
    } else if (m.group(2) != null) {
      kind = TokenKind.number;
    } else if (m.group(3) != null) {
      if (prev == '.' && prev2 == 'in') {
        kind = ctxInput.containsKey(t) ? TokenKind.input : TokenKind.unknown;
      } else if (prev == '.' && prev2 == 'out') {
        kind = TokenKind.output;
      } else if (t == 'in' || t == 'out') {
        kind = TokenKind.keyword;
      } else if (_keywords.contains(t)) {
        kind = TokenKind.keyword;
      } else if (functions.containsKey(t)) {
        kind = TokenKind.function;
      } else if (constants.containsKey(t)) {
        kind = TokenKind.constant;
      } else {
        if (prev == 'let') locals.add(t);
        kind = locals.contains(t) ? TokenKind.local : TokenKind.unknown;
      }
    } else if (m.group(4) != null) {
      kind = TokenKind.op;
    } else {
      kind = TokenKind.unknown;
    }
    if (kind != TokenKind.comment) {
      prev2 = prev;
      prev = t;
    }
    out.add(Highlight(m.start, m.end, kind));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}
