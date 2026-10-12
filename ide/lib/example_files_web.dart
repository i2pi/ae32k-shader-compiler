// Browsers cannot read the examples folder.
import 'dart:typed_data';

const bool examplesSupported = false;

String? findExamplesDir([String? saved]) => null;

class ExampleFiles {
  final String dir;
  const ExampleFiles(this.dir);
  String path(String rel) => '$dir/$rel';
  bool exists(String rel) => false;
  Future<String> text(String rel) => throw UnsupportedError('no file access in a browser');
  Future<Uint8List> bytes(String rel) => throw UnsupportedError('no file access in a browser');
  Future<List<String>> shaders() async => const [];
}
