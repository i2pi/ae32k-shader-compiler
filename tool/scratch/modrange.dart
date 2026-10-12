import 'dart:math';
import 'package:ae32k_shader_compiler/src/lang/q16.dart';
void main() {
  final rng = Random(3);
  for (final k in [2, 3, 4, 5, 7, 24, 100, 1000, 32767, 32768, 65535]) {
    final c = k << 16;
    for (final sgn in [1, -1]) {
      final cc = i32(sgn * c);
      var lo = 1 << 40, hi = -(1 << 40);
      void t(int a) { final m = qMod(i32(a), cc); lo = min(lo, m); hi = max(hi, m); }
      for (var a = -0x80000000; a < -0x80000000 + 300000; a++) t(a);
      for (var a = 0x7fffffff - 300000; a <= 0x7fffffff; a++) t(a);
      for (var a = -300000; a < 300000; a++) t(a);
      for (var i = 0; i < 2000000; i++) t(rng.nextInt(1 << 32) - (1 << 31));
      final m = c;
      final ok = lo >= -m && hi <= 2 * m;
      print('k=$k sign=$sgn  [$lo, $hi]  c=$m ${ok ? '' : 'OUT'}');
    }
  }
}
