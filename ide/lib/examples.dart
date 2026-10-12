// The examples manifest (zephyr_scion tools/imcu/examples/examples.json): one entry per runnable
// example, with its stages, prebuilt C-stage blobs, knobs, and the OSC steps that set it up, start
// it and stop it. Paths are relative to the examples folder.
import 'dart:convert';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart' show oscNoArgTypes;

/// One setup / start / stop step: an OSC message (optionally waiting for a reply) or a pause.
/// There are no shell-command steps: the device takes no commands over OSC.
sealed class ExampleStep {
  const ExampleStep();
  factory ExampleStep.fromJson(Map<String, dynamic> j) {
    if (j.containsKey('cmd')) throw const FormatException('"cmd" steps are not supported; use the OSC endpoint');
    if (j['osc'] is String) {
      final args = [for (final a in (j['args'] as List? ?? const [])) a as Object];
      var types = j['types'] as String?;
      if (types == null) {
        types = args.map((a) => a is bool ? (a ? 'T' : 'F') : a is int ? 'i' : (a is num ? 'f' : 's')).join();
        args.removeWhere((a) => a is bool);
      }
      // T and F carry no argument: "types": "T", "args": []
      final valued = types.split('').where((t) => !oscNoArgTypes.contains(t)).join();
      if (RegExp(r'[^ifsbTFN]').hasMatch(types)) throw FormatException('${j['osc']}: unknown OSC type in "$types"');
      if (valued.length != args.length) {
        throw FormatException('${j['osc']}: types "$types" for ${args.length} args');
      }
      for (var i = 0; i < args.length; i++) {
        final t = valued[i], a = args[i];
        if (!(t == 'i' && a is num || t == 'f' && a is num || t == 's' && a is String || t == 'b' && a is List)) {
          throw FormatException('${j['osc']}: argument ${i + 1} ($a) is not of type $t');
        }
      }
      return OscStep(j['osc'] as String, types, [
        for (var i = 0; i < args.length; i++)
          switch (valued[i]) {
            'i' => (args[i] as num).round(),
            'b' => [for (final v in args[i] as List) (v as num).round() & 0xFF],
            _ => args[i],
          }
      ],
          reply: j['reply'] as String?,
          timeoutMs: ((j['timeout'] as num? ?? 10) * 1000).round());
    }
    if (j['wait'] is num) return WaitStep((j['wait'] as num).round());
    throw FormatException('a step needs "osc" or "wait": $j');
  }
}

/// An OSC message; with [reply], the run waits for the device's answer on that path (and logs it).
class OscStep extends ExampleStep {
  final String address, types;
  final List<Object> args;
  final String? reply;
  final int timeoutMs;
  const OscStep(this.address, this.types, this.args, {this.reply, this.timeoutMs = 10000});
  @override
  String toString() {
    var n = 0;
    return [address, for (final t in types.split('')) oscNoArgTypes.contains(t) ? t : '${args[n++]}'].join(' ');
  }
}

class WaitStep extends ExampleStep {
  final int ms;
  const WaitStep(this.ms);
  @override
  String toString() => 'wait $ms ms';
}

const stageKeys = {'warp': 0, 'scan': 1, 'vert': 2};
const stageLabels = ['warp', 'scan', 'vertex'];

class Example {
  final String id, title, desc, kind;

  /// Slot (0 warp, 1 scan, 2 vertex) -> .ss path.
  final Map<int, String> stages;

  /// Prebuilt blobs (C pixel runners): (slot, path).
  final List<(int, String)> blobs;
  final bool fast;
  final Map<int, double> knobs;
  final List<ExampleStep> setup, start, stop;
  const Example(
      {required this.id,
      required this.title,
      this.desc = '',
      this.kind = 'run',
      this.stages = const {},
      this.blobs = const [],
      this.fast = false,
      this.knobs = const {},
      this.setup = const [],
      this.start = const [],
      this.stop = const []});

  String get group => id.contains('/') ? id.substring(0, id.indexOf('/')) : '';
  bool get runnable => kind != 'probe';

  /// The stage the editor opens first: the scan stage, else the vertex, else the warp.
  int? get primarySlot => [1, 2, 0].where(stages.containsKey).firstOrNull;

  Iterable<ExampleStep> get allSteps => [...setup, ...start, ...stop];

  /// The vertex count of `/send/1/shader/cells`, for the simulator.
  int? get vertexCount {
    for (final s in [...setup, ...start]) {
      if (s is OscStep && s.address == '/send/1/shader/cells' && s.args.firstOrNull is int) return s.args.first as int;
    }
    return null;
  }

  /// `/send/1/shader/run "pattern" lstep lines ipl xn xstep lphase`, for the simulator's pattern
  /// mode; null entries were not given.
  List<int?>? get patternArgs {
    for (final s in [...setup, ...start]) {
      if (s is OscStep && s.address == '/send/1/shader/run' && s.args.firstOrNull == 'pattern') {
        final a = s.args.skip(1).whereType<int>().toList();
        return [for (var i = 0; i < 6; i++) i < a.length ? a[i] : null];
      }
    }
    return null;
  }

  factory Example.fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || id.isEmpty) throw FormatException('an example without an "id": $j');
    try {
      final st = <int, String>{};
      for (final e in (j['stages'] as Map? ?? const {}).entries) {
        final slot = stageKeys[e.key];
        if (slot == null) throw FormatException('unknown stage "${e.key}" (warp, scan or vert)');
        if (e.value != null) st[slot] = e.value as String;
      }
      List<ExampleStep> steps(String k) =>
          [for (final s in (j[k] as List? ?? const [])) ExampleStep.fromJson(Map<String, dynamic>.from(s as Map))];
      return Example(
        id: id,
        title: j['title'] as String? ?? id,
        desc: j['desc'] as String? ?? '',
        kind: j['kind'] as String? ?? 'run',
        stages: st,
        blobs: [
          for (final b in (j['blobs'] as List? ?? const []).cast<Map>())
            if (b['slot'] case final int s when s >= 0 && s <= 2)
              (s, b['file'] as String)
            else
              throw FormatException('blob slot ${b['slot']} (0, 1 or 2)'),
        ],
        fast: j['fast'] as bool? ?? false,
        knobs: {
          for (final e in (j['knobs'] as Map? ?? const {}).entries)
            int.parse((e.key as String).replaceFirst('k', '')): (e.value as num).toDouble(),
        },
        setup: steps('setup'),
        start: steps('start'),
        stop: steps('stop'),
      );
    } on FormatException catch (e) {
      throw FormatException('$id: ${e.message}');
    } on TypeError catch (e) {
      throw FormatException('$id: $e');
    }
  }
}

/// Parses examples.json: either a list of entries or {"examples": [...]}. Entries that do not
/// parse are reported in [errors] and left out, so one bad entry does not hide the rest.
List<Example> parseManifest(String json, {List<String>? errors}) {
  final d = jsonDecode(json);
  final list = d is Map ? d['examples'] : d;
  if (list is! List) throw const FormatException('examples.json: expected a list of examples');
  final out = <Example>[];
  for (final e in list) {
    try {
      out.add(Example.fromJson(Map<String, dynamic>.from(e as Map)));
    } on FormatException catch (x) {
      errors?.add(x.message);
    }
  }
  return out;
}

/// The slot a stage file is written for: a vertex stage places points (out.vx / out.vy), a scan
/// stage writes registers (@out), anything else is a warp.
int guessSlot(String src) {
  final code = src.split('\n').map((l) => l.split('//').first).join('\n');
  if (RegExp(r'\bout\.v[xy]\b').hasMatch(code)) return 2;
  if (RegExp(r'^\s*@out\b', multiLine: true).hasMatch(code)) return 1;
  return 0;
}

/// Without a manifest: one upload-only entry per .ss file, its slot guessed from the source.
Example fileExample(String rel, String src) =>
    Example(id: rel.replaceAll(RegExp(r'\.ss$'), ''), title: rel.split('/').last, kind: 'file', stages: {guessSlot(src): rel});
