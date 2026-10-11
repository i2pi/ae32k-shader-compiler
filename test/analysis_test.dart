// The editor API: positions of errors, per-line cycle attribution, and the highlighter.
import 'dart:io';
import 'dart:math';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:test/test.dart';

void main() {
  test('errors carry line and column', () {
    Diagnostic d(String s) => analyzeStage(s).diagnostics.single;
    expect((d('let a = 1;\nout.dx = a +* 2;').line, d('let a = 1;\nout.dx = a +* 2;').column), (2, 13));
    expect((d('out.dx = sin(1, 2);').line, d('out.dx = sin(1, 2);').column), (1, 10));
    expect(d('out.dx = in.nope;').line, 1);
    expect(d('  \n\n   out.dx = 1 \$ 2;').column, 15);
    expect(d('@out a no_such_register').line, 1);
    expect(d('out.dx = 1').line, 1); // missing ;
  });

  test('per-line cycles add up to the stage total, for every example', () {
    final files = Directory('../../tools/imcu/examples').listSync(recursive: true).whereType<File>()
        .where((f) => f.path.endsWith('.ss'));
    for (final f in files) {
      final b = f.uri.pathSegments.last, src = f.readAsStringSync();
      final slot = b.startsWith('v') ? 2 : (src.contains('@out') ? 1 : 0);
      final a = analyzeStage(src, slot: slot, samples: 8);
      expect(a.diagnostics.where((d) => d.isError), isEmpty, reason: f.path);
      final sum = a.lines.values.fold(0.0, (s, c) => s + c.cycles);
      expect(sum, closeTo(a.meanCycles, 0.5), reason: f.path); // totals round half-cycles up per run
      // every line with cost is a real source line (or 0, entry/exit)
      final n = src.split('\n').length;
      expect(a.lines.keys.every((l) => l >= 0 && l <= n), isTrue, reason: f.path);
    }
  });

  test('a call is charged to the line that makes it; untaken branches cost nothing', () {
    final a = analyzeStage('let a = in.u;\nlet b = sin(a) * 3;\nif (in.u > 2) {\n  out.dx = sqrt(a);\n}\nout.dy = b;');
    expect(a.lines[2]!.cycles, greaterThan(20)); // sin's routine (~27)
    expect(a.lines[4], isNull); // u < 1: never runs
  });

  test('the highlighter never throws and covers code tokens', () {
    final rng = Random(4);
    const alphabet = 'let if else in out . ( ) { } ; = + - * / % < > ! & | @out sin x 1 2.5 // \n " # \$';
    final parts = alphabet.split(' ');
    for (var n = 0; n < 2000; n++) {
      final s = List.generate(rng.nextInt(30), (_) => parts[rng.nextInt(parts.length)]).join(rng.nextBool() ? ' ' : '');
      highlight(s);
    }
    final hs = highlight('@out gr out0_csc_y0 gain\nlet x = sin(in.u) * pi; // c\nout.dx = x;');
    expect(hs.map((h) => h.kind).toList(), containsAllInOrder([TokenKind.directive, TokenKind.output, TokenKind.register,
      TokenKind.mode, TokenKind.keyword, TokenKind.local, TokenKind.function, TokenKind.input, TokenKind.constant,
      TokenKind.comment, TokenKind.output, TokenKind.local]));
  });
}
