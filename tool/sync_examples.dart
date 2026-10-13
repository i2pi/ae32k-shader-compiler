// Copies zephyr_scion's tools/imcu/examples (stage sources, examples.json, prebuilt C-stage
// blobs and their C sources) into examples/ here, so the IDE bundles them and runs without
// reading outside the app. Lists every examples/ folder as an asset in pubspec.yaml.
// test/examples_copy_test.dart fails when the copy is stale.
//   dart run tool/sync_examples.dart [path/to/tools/imcu/examples]
import 'dart:io';

const kept = ['.ss', '.json', '.bin', '.c', '.h', '.md'];

void main(List<String> args) {
  final src = Directory(args.isEmpty ? '../../tools/imcu/examples' : args.first);
  if (!src.existsSync()) throw StateError('${src.path}: no such folder');
  final dst = Directory('examples');
  if (dst.existsSync()) dst.deleteSync(recursive: true);
  var n = 0;
  final dirs = <String>{''};
  for (final f in src.listSync(recursive: true).whereType<File>()) {
    final rel = f.path.substring(src.path.length + 1);
    if (!kept.any(rel.endsWith) || rel.split('/').any((p) => p.startsWith('.') || p == '__pycache__')) continue;
    final out = File('examples/$rel')..createSync(recursive: true);
    out.writeAsBytesSync(f.readAsBytesSync());
    final d = rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '';
    // every parent folder too (Flutter asset folders are not recursive)
    for (var p = d; p.isNotEmpty; p = p.contains('/') ? p.substring(0, p.lastIndexOf('/')) : '') {
      dirs.add(p);
    }
    n++;
  }
  final pub = File('pubspec.yaml');
  final text = pub.readAsStringSync();
  final i = text.indexOf('\n# examples assets');
  final assets = (dirs.toList()..sort()).map((d) => '    - examples/${d.isEmpty ? '' : '$d/'}').join('\n');
  pub.writeAsStringSync('${(i < 0 ? text : text.substring(0, i)).trimRight()}\n\n'
      '# examples assets (written by tool/sync_examples.dart): the IDE loads them as\n'
      '# packages/ae32k_shader_compiler/examples/...\n'
      'flutter:\n  assets:\n$assets\n');
  stdout.writeln('examples/: $n files in ${dirs.length} folders');
}
