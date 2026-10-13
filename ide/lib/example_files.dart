// The examples: bundled into the app from this repo's examples/ (a copy of zephyr_scion's
// tools/imcu/examples, tool/sync_examples.dart), so the IDE needs no file access to run them.
import 'package:flutter/services.dart';

const _prefix = 'packages/ae32k_shader_compiler/examples/';

abstract class ExampleFiles {
  /// Where the examples come from, for the browser's header.
  String get label;

  /// [rel]'s identity as an editor file name (not a path on disk for bundled examples).
  String path(String rel);
  bool exists(String rel);
  Future<String> text(String rel);
  Future<Uint8List> bytes(String rel);

  /// Every .ss file, relative and sorted.
  Future<List<String>> shaders();
}

class BundledExamples implements ExampleFiles {
  final AssetBundle bundle;
  final Set<String> _files;
  BundledExamples._(this.bundle, this._files);

  static Future<BundledExamples> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    final m = await AssetManifest.loadFromAssetBundle(b);
    return BundledExamples._(b, {
      for (final a in m.listAssets())
        if (a.startsWith(_prefix)) a.substring(_prefix.length),
    });
  }

  @override
  String get label => 'bundled examples';
  @override
  String path(String rel) => 'examples/$rel';
  @override
  bool exists(String rel) => _files.contains(rel);
  @override
  Future<String> text(String rel) => bundle.loadString('$_prefix$rel', cache: false);
  @override
  Future<Uint8List> bytes(String rel) async => (await bundle.load('$_prefix$rel')).buffer.asUint8List();
  @override
  Future<List<String>> shaders() async => _files.where((f) => f.endsWith('.ss')).toList()..sort();
}
