// Runs an example on the device: compile every stage first (nothing is sent if one fails), then
// stop what is running, upload blobs and stages, the scan map and knobs, then the setup and start
// steps. Each step's outcome goes to the log.
import 'dart:async';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';

import 'device.dart';
import 'example_files.dart';
import 'examples.dart';
import 'osc_decode.dart';

/// What a run needs from the device link (a fake in the tests).
abstract class RunTarget {
  Future<String?> uploadBlob(List<int> bytes, int slot);
  Future<String> sendScanMap(List<OutMapEntry> map);
  void sendKnob(int k, double v);
  void sendOsc(String address, String types, List<Object> args);
  Future<OscReply?> requestOsc(String address, String types, List<Object> args, String reply, Duration timeout);
}

class LinkTarget implements RunTarget {
  final DeviceLink link;
  final void Function(String)? progress;
  LinkTarget(this.link, {this.progress});
  @override
  Future<String?> uploadBlob(List<int> bytes, int slot) => link.uploadBlob(bytes, slot, progress: progress);
  @override
  Future<String> sendScanMap(List<OutMapEntry> map) => link.sendScanMap(map);
  @override
  void sendKnob(int k, double v) => link.sendKnob(k, v);
  @override
  void sendOsc(String address, String types, List<Object> args) => link.sendOsc(address, types, args);
  @override
  Future<OscReply?> requestOsc(String address, String types, List<Object> args, String reply, Duration timeout) =>
      link.requestOsc(address, types, args, reply, timeout);
}

class ExampleRunner {
  /// The example last started, whose stop steps run before the next one starts.
  Example? running;

  /// Compiles [ex]'s stages. [sources] overrides a stage file's text (the editor's buffer when
  /// it holds that file). Returns the stages by slot, or null after logging the errors.
  Future<Map<int, CompiledStage>?> compile(Example ex, ExampleFiles files, void Function(String) log,
      {Map<String, String> sources = const {}}) async {
    final out = <int, CompiledStage>{};
    var ok = true;
    for (final MapEntry(key: slot, value: rel) in ex.stages.entries) {
      try {
        final src = sources[rel] ?? await files.text(rel);
        out[slot] = compileStage(src, slot: slot, fast: ex.fast);
      } catch (e) {
        log('$rel (${stageLabels[slot]}): ${e is CompileError || e is ShaderSyntaxError ? e : 'cannot read: $e'}');
        ok = false;
      }
    }
    return ok ? out : null;
  }

  /// Runs [ex]. Returns whether every step succeeded; [knobs] receives the example's knob values.
  Future<bool> run(Example ex, ExampleFiles files, RunTarget dev, void Function(String) log,
      {Map<String, String> sources = const {}, List<double>? knobs}) async {
    if (!ex.runnable) {
      log('${ex.id} is a probe, not a runnable example');
      return false;
    }
    final stages = await compile(ex, files, log, sources: sources);
    if (stages == null) return false;
    final blobs = <(int, String, List<int>)>[];
    for (final (slot, rel) in ex.blobs) {
      try {
        blobs.add((slot, rel, await files.bytes(rel)));
      } catch (e) {
        log('$rel: cannot read ($e)');
        return false;
      }
    }

    // stop whatever ran before, then this example's own stop (the clean starting state)
    final prev = running;
    running = null;
    if (prev != null && prev.id != ex.id) await _steps(prev.stop, dev, log, stopOnError: false);
    await _steps(ex.stop, dev, log, stopOnError: false);

    for (final (slot, rel, bytes) in blobs) {
      final r = await dev.uploadBlob(bytes, slot);
      log(r == null ? 'armed $rel (${bytes.length} bytes) in slot $slot' : '$rel: $r');
      if (r != null) return false;
    }
    for (final slot in [0, 2, 1]) {
      final st = stages[slot];
      if (st == null) continue;
      final rel = ex.stages[slot]!;
      final r = await dev.uploadBlob(st.bytes, slot);
      log(r == null
          ? 'armed $rel (${st.bytes.length} bytes, ${stageLabels[slot]}${ex.fast ? ', --fast' : ''})'
          : '$rel: $r');
      if (r != null) return false;
    }
    final map = stages[1]?.outMap ?? const [];
    if (map.isNotEmpty) log('scan map: ${await dev.sendScanMap(map)}');
    for (var k = 0; k < 8; k++) {
      final v = ex.knobs[k] ?? 0;
      knobs?[k] = v;
      dev.sendKnob(k, v);
    }
    running = ex;
    return await _steps([...ex.setup, ...ex.start], dev, log, stopOnError: true);
  }

  /// Runs the stop steps of the example that is running.
  Future<void> stop(RunTarget dev, void Function(String) log) async {
    final ex = running;
    if (ex == null) return;
    running = null;
    await _steps(ex.stop, dev, log, stopOnError: false);
  }

  Future<bool> _steps(List<ExampleStep> steps, RunTarget dev, void Function(String) log,
      {required bool stopOnError}) async {
    for (final s in steps) {
      final ok = await _step(s, dev, log);
      if (!ok && stopOnError) return false;
    }
    return true;
  }

  /// A reply that reports failure: a negative first number, or "refused" / "busy" / "error".
  static bool _refused(List<Object> args) {
    final a = args.firstOrNull;
    return a is int && a < 0 ||
        a is String && RegExp(r'^\s*(-\d+\b|refused|busy|error)', caseSensitive: false).hasMatch(a);
  }

  Future<bool> _step(ExampleStep s, RunTarget dev, void Function(String) log) async {
    switch (s) {
      case OscStep(:final address, :final types, :final args, :final reply, :final timeoutMs):
        if (reply == null) {
          dev.sendOsc(address, types, args);
          log('$s');
          return true;
        }
        final r = await dev.requestOsc(address, types, args, reply, Duration(milliseconds: timeoutMs));
        log(r == null ? '$s: no reply' : '$s: ${r.args.join(' ')}');
        return r != null && !_refused(r.args);
      case WaitStep(:final ms):
        await Future<void>.delayed(Duration(milliseconds: ms));
        return true;
    }
  }
}
