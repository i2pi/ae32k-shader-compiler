// Reads the examples folder (zephyr_scion tools/imcu/examples) from disk.
import 'dart:io';
import 'dart:typed_data';

const bool examplesSupported = true;

/// The examples folder: [saved] if it still holds an examples.json, else the first
/// tools/imcu/examples above the working directory or the app (the IDE lives in
/// zephyr_scion/external/ae32k_shader_compiler/ide).
String? findExamplesDir([String? saved]) {
  bool ok(String d) => File('$d/examples.json').existsSync() || Directory(d).existsSync() && saved == d;
  if (saved != null && ok(saved)) return saved;
  for (final start in [Directory.current.path, File(Platform.resolvedExecutable).parent.path]) {
    var d = Directory(start).absolute;
    for (var i = 0; i < 14; i++) {
      final c = '${d.path}/tools/imcu/examples';
      if (Directory(c).existsSync()) return c;
      if (d.parent.path == d.path) break;
      d = d.parent;
    }
  }
  return null;
}

class ExampleFiles {
  final String dir;
  const ExampleFiles(this.dir);
  String path(String rel) => '$dir/$rel';
  bool exists(String rel) => File(path(rel)).existsSync();
  Future<String> text(String rel) => File(path(rel)).readAsString();
  Future<Uint8List> bytes(String rel) => File(path(rel)).readAsBytes();

  /// Every .ss file below the folder, relative and sorted.
  Future<List<String>> shaders() async => [
        await for (final f in Directory(dir).list(recursive: true))
          if (f is File && f.path.endsWith('.ss')) f.path.substring(dir.length + 1),
      ]..sort();
}
