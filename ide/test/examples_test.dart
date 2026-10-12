// The examples manifest, the run sequence (against a fake device), every example compiling, and
// the browser itself (screenshot to build/screenshots/).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_ide/example_files.dart';
import 'package:shader_ide/example_runner.dart';
import 'package:shader_ide/examples.dart';
import 'package:shader_ide/examples_dialog.dart';
import 'package:shader_ide/osc_decode.dart';
import 'package:shader_ide/theme.dart';

const _ex = '../../../tools/imcu/examples';

const _manifest = '''
{"examples": [
 {"id":"pip/sphere", "title":"Lit sphere", "desc":"PIP area blend",
  "stages":{"warp":null, "scan":"s.ss", "vert":"v.ss"},
  "fast":true, "knobs":{"k0":0.25,"k2":0.15},
  "setup":[{"osc":"/send/1/pip/2/enabled","types":"T","args":[]},
           {"osc":"/send/1/shader/cells","types":"i","args":[78],"reply":"/send/1/shader/cells"}],
  "start":[{"osc":"/send/1/shader/run","types":"s","args":["cells"],"reply":"/send/1/shader/run"}],
  "stop":[{"osc":"/send/1/shader/stop","reply":"/send/1/shader/stop"}]},
 {"id":"ddr/osd", "title":"OSD pixels", "stages":{"scan":"px.ss"}, "blobs":[{"slot":2,"file":"r.bin"}],
  "setup":[{"osc":"/send/1/shader/canvas","types":"siiii","args":["yc",640,360,640,360],"reply":"/send/1/shader/canvas","timeout":2}],
  "start":[{"wait":10}], "stop":[{"osc":"/send/1/shader/canvas","types":"s","args":["off"]}]},
 {"id":"bad/types", "stages":{"scan":"s.ss"}, "setup":[{"osc":"/x","types":"i","args":["no"]}]},
 {"id":"fx/pattern", "kind":"run", "stages":{"scan":"s.ss"},
  "start":[{"osc":"/send/1/shader/run","types":"siiiiii","args":["pattern",2,900,456,4,0,1],"reply":"/send/1/shader/run"}]},
 {"id":"bad/count", "stages":{"scan":"s.ss"}, "setup":[{"osc":"/x","types":"Ti","args":[]}]},
 {"id":"bad/cmd", "stages":{"scan":"s.ss"}, "setup":[{"cmd":"imcu scan stop"}]},
 {"id":"cal/probe", "kind":"probe", "stages":{"warp":"w.ss"}}
]}''';

class _Fake implements RunTarget {
  final log = <String>[];
  String? failAt; // a request to this address is refused
  @override
  Future<String?> uploadBlob(List<int> bytes, int slot) async {
    log.add('blob $slot ${bytes.length}');
    return null;
  }

  @override
  Future<String> sendScanMap(List<OutMapEntry> map) async {
    log.add('map ${map.length}');
    return '${map.length} entries';
  }

  @override
  void sendKnob(int k, double v) => log.add('k$k $v');
  @override
  void sendOsc(String address, String types, List<Object> args) => log.add('osc $address $args');
  @override
  Future<OscReply?> requestOsc(String address, String types, List<Object> args, String reply, Duration timeout) async {
    log.add('req $address $args');
    return OscReply(reply, [address == failAt ? 'error: nope' : 0]);
  }
}

void main() {
  test('manifest: entries, step types, a bad entry reported and left out', () {
    final errors = <String>[];
    final ex = parseManifest(_manifest, errors: errors);
    expect(ex.map((e) => e.id), ['pip/sphere', 'ddr/osd', 'fx/pattern', 'cal/probe']);
    expect(errors, [contains('bad/types'), contains('bad/count'), contains('"cmd" steps are not supported')]);
    final s = ex[0];
    expect(s.stages, {1: 's.ss', 2: 'v.ss'});
    expect(s.knobs, {0: 0.25, 2: 0.15});
    expect(s.fast, isTrue);
    expect(s.group, 'pip');
    expect(s.primarySlot, 1);
    final en = s.setup[0] as OscStep;
    expect(en.args, isEmpty);
    expect((en.types, '$en'), ('T', '/send/1/pip/2/enabled T'));
    expect(s.vertexCount, 78);
    expect(s.patternArgs, isNull);
    expect(ex[2].patternArgs, [2, 900, 456, 4, 0, 1]);
    expect(oscMessage('/a', 'Ti', [5]), oscMessage('/a', 'Ti', [5]));
    expect(oscMessage('/a', 'T', []).length, 8); // "/a" + ",T": no argument bytes
    final o = ex[1];
    expect(o.blobs, [(2, 'r.bin')]);
    final c = o.setup.single as OscStep;
    expect(c.args, ['yc', 640, 360, 640, 360]);
    expect((c.types, c.reply, c.timeoutMs), ('siiii', '/send/1/shader/canvas', 2000));
    expect(ex[3].runnable, isFalse);
  });

  test('slot guess: vertex places points, scan writes registers, else warp', () {
    expect(guessSlot('out.vx = 1;\nout.vy = 2;'), 2);
    expect(guessSlot('@out g out0_csc_y0\nout.g = 1;'), 1);
    expect(guessSlot('// out.vx in a comment\nout.dx = 1;'), 0);
  });

  group('run sequence', () {
    late Directory dir;
    late ExampleFiles files;
    late List<Example> ex;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('ex');
      File('${dir.path}/s.ss').writeAsStringSync('@out g out0_csc_y0\nout.g = 1 - 0.5 * in.p0;\n');
      File('${dir.path}/v.ss').writeAsStringSync('out.vx = in.x * 10;\nout.vy = 100;\n');
      File('${dir.path}/px.ss').writeAsStringSync('out.dx = in.x;\n');
      File('${dir.path}/r.bin').writeAsBytesSync(List.filled(64, 0));
      files = ExampleFiles(dir.path);
      ex = parseManifest(_manifest);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('previous stop, own stop, blobs, warp/vertex/scan, map, knobs, setup, start', () async {
      final dev = _Fake(), r = ExampleRunner(), out = <String>[], knobs = List<double>.filled(8, 9);
      expect(await r.run(ex[1], files, dev, out.add), isTrue);
      dev.log.clear();
      expect(await r.run(ex[0], files, dev, out.add, knobs: knobs), isTrue);
      expect(dev.log.take(3), ['osc /send/1/shader/canvas [off]', 'req /send/1/shader/stop []', startsWith('blob 2 ')]);
      expect(dev.log[3], startsWith('blob 1 '));
      expect(dev.log[4], 'map 1');
      expect(dev.log.sublist(5, 13), ['k0 0.25', 'k1 0.0', 'k2 0.15', 'k3 0.0', 'k4 0.0', 'k5 0.0', 'k6 0.0', 'k7 0.0']);
      expect(dev.log.sublist(13), [
        'osc /send/1/pip/2/enabled []',
        'req /send/1/shader/cells [78]',
        'req /send/1/shader/run [cells]',
      ]);
      expect(knobs, [0.25, 0, 0.15, 0, 0, 0, 0, 0]);
      expect(r.running?.id, 'pip/sphere');
      dev.log.clear();
      await r.stop(dev, out.add);
      expect(dev.log, ['req /send/1/shader/stop []']);
      expect(r.running, isNull);
    });

    test('a stage that does not compile: nothing reaches the device', () async {
      File('${dir.path}/s.ss').writeAsStringSync('out.g = ;');
      final dev = _Fake(), out = <String>[];
      expect(await ExampleRunner().run(ex[0], files, dev, out.add), isFalse);
      expect(dev.log, isEmpty);
      expect(out.single, startsWith('s.ss (scan)'));
    });

    test('a failing setup step stops the run there; an edited buffer replaces the file', () async {
      final dev = _Fake()..failAt = '/send/1/shader/cells', out = <String>[];
      expect(await ExampleRunner().run(ex[0], files, dev, out.add, sources: {'v.ss': 'out.vx = 5;\nout.vy = 6;\n'}), isFalse);
      expect(dev.log.last, 'req /send/1/shader/cells [78]');
      expect(out.last, contains('error: nope'));
      expect(await ExampleRunner().run(ex[3], files, dev, out.add), isFalse); // a probe
    });
  });

  test('every .ss in the examples folder compiles (slot from the source, --fast)', () async {
    final files = ExampleFiles(_ex);
    final failed = <String>[];
    final all = await files.shaders();
    for (final rel in all) {
      final src = await files.text(rel);
      try {
        compileStage(src, slot: guessSlot(src), fast: true);
      } catch (e) {
        failed.add('$rel: $e');
      }
    }
    expect(all.length, greaterThan(100));
    expect(failed, isEmpty);
  });

  test('examples.json: parses, every stage compiles, blobs exist, every shader step waits for its reply', () async {
    final files = ExampleFiles(_ex);
    if (!files.exists('examples.json')) return markTestSkipped('no examples.json yet');
    final errors = <String>[];
    final ex = parseManifest(await files.text('examples.json'), errors: errors);
    expect(errors, isEmpty);
    final bad = <String>[];
    for (final e in ex) {
      for (final MapEntry(key: slot, value: rel) in e.stages.entries) {
        try {
          final st = compileStage(await files.text(rel), slot: slot, fast: e.fast);
          if (st.outMap.isNotEmpty && slot != 1) bad.add('${e.id}: @out in a ${stageLabels[slot]} stage');
        } catch (x) {
          bad.add('${e.id}: $rel: $x');
        }
      }
      for (final (_, rel) in e.blobs) {
        if (!files.exists(rel)) bad.add('${e.id}: $rel missing');
      }
      if (e.runnable && e.stages.isEmpty && e.blobs.isEmpty) bad.add('${e.id}: nothing to upload');
      for (final s in e.allSteps.whereType<OscStep>()) {
        // shader endpoints answer the sender; PIP sets relay only to other clients (a wait follows)
        if (s.reply == null && s.address.startsWith('/send/1/shader/')) bad.add('${e.id}: $s has no reply');
      }
    }
    expect(bad, isEmpty);
    expect(ex.where((e) => e.runnable).length, greaterThan(40));
  });

  testWidgets('browser (screenshot)', (tester) async {
    await _fonts();
    tester.view.physicalSize = const Size(1400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final set = (await tester.runAsync(() => ExampleSet.load(_ex)))!;
    final root = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: root,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: Sc.theme(),
        home: Scaffold(
          body: Builder(builder: (c) => ExamplesDialog(set: set, canRun: true, onChooseDir: (_) {}, selectedId: set.examples.firstWhere((e) => e.id.startsWith('pip/'), orElse: () => set.examples[3]).id)),
        ),
      ),
    ));
    for (var i = 0; i < 40 && find.textContaining('checking').evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump();
    }
    expect(find.textContaining('all compile'), findsOneWidget);
    expect(find.text('EXAMPLES'), findsOneWidget);

    await tester.runAsync(() async {
      final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(root));
      final img = await ro.toImage();
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/screenshots').createSync(recursive: true);
      File('build/screenshots/examples_browser.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}

Future<void> _fonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      final f = File(p);
      if (f.existsSync()) loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await loader.load();
  }

  await load('DINPro', ['assets/fonts/D-DIN-Regular.otf', 'assets/fonts/D-DIN-Bold.otf']);
  await load('Menlo', ['assets/fonts/D-DIN-Regular.otf']); // stands in for the monospace face (legible screenshots)
  await load('MaterialIcons', ['${Platform.environment['FLUTTER_ROOT'] ?? '/Users/josh/src/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}
