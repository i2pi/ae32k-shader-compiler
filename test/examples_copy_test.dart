// examples/ is a copy of zephyr_scion's tools/imcu/examples (the IDE bundles it): it must match.
import 'dart:io';

import 'package:test/test.dart';

import '../tool/sync_examples.dart' show kept;

const src = '../../tools/imcu/examples';

Map<String, List<int>> _files(String dir) => {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>())
        if (kept.any(f.path.endsWith) && !f.path.substring(dir.length + 1).split('/').any((p) => p.startsWith('.') || p == '__pycache__'))
          f.path.substring(dir.length + 1): f.readAsBytesSync(),
    };

void main() {
  test('examples/ matches zephyr_scion tools/imcu/examples (dart run tool/sync_examples.dart)', () {
    if (!Directory(src).existsSync()) return markTestSkipped('no zephyr_scion checkout around this package');
    final want = _files(src), have = _files('examples');
    expect(have.keys.toSet(), want.keys.toSet());
    final differ = [for (final k in want.keys) if (have[k] != null && '${have[k]}' != '${want[k]}') k];
    expect(differ, isEmpty);
  });
}
