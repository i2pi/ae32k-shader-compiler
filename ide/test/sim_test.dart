// The frame simulator: the engine's cell and register model on known shapes, and the page
// itself with real example stages (screenshots to build/screenshots/).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_ide/sim/sim_engine.dart';
import 'package:shader_ide/sim/sim_page.dart';
import 'package:shader_ide/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ex = '../../../tools/imcu/examples';
String _read(String p) => File('$_ex/$p').readAsStringSync();

// one cell at (100, 100), 200 x 50, whose scan stage halves the output CSC Y row (line-latched)
const _oneCell = '''
out.vx = 100;
out.vy = 100 + 2000 * (in.x > 0);
out.p0 = 1;
out.p2 = 200;
out.p3 = 50;
''';
const _halfY = '''
@out g out0_csc_y0
out.g = 1 - 0.5 * in.p0;
''';

void main() {
  test('circle cells with a per-pixel swap: the swap covers the disc, nothing else', () {
    final e = SimEngine(
        w: 1920, h: 1080, fps: 24, fast: true, vertex: _read('shapes/sh01_circle.ss'), scan: _read('shapes/fx01_swap.ss'), points: 72);
    expect(e.errors, isEmpty);
    final f = e.frame(0, const {});
    expect(f.outputs.single.pixel, isTrue);
    int at(int x, int y) => f.rows[y].firstWhere((s) => s.x0 <= x && x < s.x1).fields[0];
    final r = (0.28 * 1080).round(); // t = 0
    expect(at(960, 540), 2);
    expect(at(960, 540 - r + 8), 2);
    expect(at(960 - r + 10, 540), 2);
    expect(at(960 + r + 10, 540), 0);
    expect(at(960, 540 + r + 10), 0);
    expect(at(100, 540), 0);
    expect(at(960, 100), 0);
  });

  test('a line-latched register: the cell decides the whole line, from the next line, then back to base', () {
    final e = SimEngine(w: 1920, h: 1080, fps: 24, fast: false, vertex: _oneCell, scan: _halfY, points: 2);
    final f = e.frame(0, const {});
    final o = f.outputs.single;
    expect(o.hold, isTrue);
    int at(int x, int y) => f.rows[y].firstWhere((s) => s.x0 <= x && x < s.x1).fields[0];
    expect(at(150, 100), o.base); // written during line 100, sampled from 101
    expect(at(150, 101), o.base ~/ 2);
    expect(at(1800, 101), o.base ~/ 2); // the whole line
    expect(at(150, 150), o.base ~/ 2); // the value written on line 149
    expect(at(150, 151), o.base); // base again after the first empty line
    expect(f.cells.where((c) => !c.parked).length, 1);
  });

  test('warp: the grid samples the source at (x + dx, y + dy), clamped to +-4 blocks', () {
    final e = SimEngine(w: 1920, h: 1080, fps: 24, fast: false, warp: 'out.dx = 10; out.dy = 0 - 500;');
    final wf = e.frame(0, const {}).warp!;
    expect(wf.step, 16);
    expect(wf.nx, 121);
    expect(wf.ny, 68);
    final k = 10 * wf.nx + 20;
    expect(wf.sx[k], 20 * 16 + 10);
    expect(wf.sy[k], 10 * 16 - 64.0);
  });

  Future<void> page(WidgetTester tester, String shot, Map<int, String> stages, {int editorSlot = 2}) async {
    SharedPreferences.setMockInitialValues({});
    await _fonts();
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = GlobalKey();
    final ed = stages[editorSlot]!;
    await tester.pumpWidget(RepaintBoundary(
      key: root,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: Sc.theme(),
        home: SimPage(
            editorSource: _read(ed),
            editorSlot: editorSlot,
            editorName: ed.split('/').last,
            knobs: List.filled(8, 0),
            fast: true),
      ),
    ));
    final st = tester.state(find.byType(SimPage)) as dynamic;
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (final e in stages.entries) {
      if (e.key != editorSlot) st.debugSetStage(e.key, e.value.split('/').last, _read(e.value));
    }
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 42));
    }
    expect(find.text('SIMULATOR'), findsOneWidget);
    expect(find.textContaining(ed.split('/').last), findsWidgets);
    expect(find.text('PROBLEMS'), findsNothing);
    await tester.runAsync(() async {
      final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(root));
      final img = await ro.toImage();
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/screenshots').createSync(recursive: true);
      File('build/screenshots/$shot.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  testWidgets('page: warp + vertex + scan (screenshot)', (tester) async {
    await page(tester, 'sim_circle_swap_ripple', {0: 'ripple.ss', 2: 'shapes/sh01_circle.ss', 1: 'shapes/fx01_swap.ss'});
  });
  testWidgets('page: scan stage alone, pattern mode (screenshot)', (tester) async {
    await page(tester, 'sim_pattern_csc', {1: 'corpus/s02_csc_gain_rows.ss'}, editorSlot: 1);
  });
  testWidgets('page: offsets on moving bands, and an unmodelled register (screenshots)', (tester) async {
    await page(tester, 'sim_bar_offsets', {2: 'shapes/sh08_scanning_bar.ss', 1: 'shapes/fx04_offset_bands.ss'});
  });
  testWidgets('page: unmodelled register shows as a trace (screenshot)', (tester) async {
    await page(tester, 'sim_trace_hsize', {2: 'shapes/sh06_rings.ss', 1: 'shapes/fx10_hsize_wave.ss'});
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
  await load('MaterialIcons', ['${Platform.environment['FLUTTER_ROOT'] ?? '/Users/josh/src/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}
