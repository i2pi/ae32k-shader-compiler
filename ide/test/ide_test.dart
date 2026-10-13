// Pumps the IDE with real fonts, checks it compiles, measures and marks errors, and writes
// screenshots to build/screenshots/ (to look at the layout without a display).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_ide/asm_pane.dart';
import 'package:shader_ide/code_editor.dart';
import 'package:shader_ide/main.dart';
import 'package:shader_ide/templates.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final f = File(p);
    if (f.existsSync()) loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await loader.load();
}

final _root = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(_root));
    final img = await ro.toImage();
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/screenshots').createSync(recursive: true);
    File('build/screenshots/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _settle(WidgetTester tester) async {
  // analysis runs in an isolate (compute): give it real time, then pump
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUpAll(() async {
    await _font('DINPro', ['assets/fonts/D-DIN-Regular.otf', 'assets/fonts/D-DIN-Bold.otf']);
    await _font('Menlo', ['/System/Library/Fonts/Monaco.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf']);
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/src/flutter';
    await _font('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  });

  testWidgets('a warp stage: compiles, costs per line, screenshot', (tester) async {
    SharedPreferences.setMockInitialValues({'draft': templates['Warp: ripple']!.$2, 'slot': 0});
    tester.view.physicalSize = const Size(1440, 880);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(key: _root, child: const ShaderIde()));
    await _settle(tester);
    expect(find.textContaining('compiles'), findsOneWidget);
    expect(find.text('none'), findsOneWidget); // no problems
    expect(find.text('ASSEMBLY'), findsOneWidget);
    // put the cursor on line 5 (the sin): its instructions light up in the assembly pane
    final editor = find.descendant(of: find.byType(CodeEditor), matching: find.byType(TextField));
    final tf = tester.widget<TextField>(editor);
    final text = tf.controller!.text;
    var off = 0;
    for (var i = 0; i < 4; i++) {
      off = text.indexOf('\n', off) + 1;
    }
    await tester.showKeyboard(editor);
    tester.testTextInput.updateEditingValue(TextEditingValue(text: text, selection: TextSelection.collapsed(offset: off + 4)));
    await tester.pump();
    expect(tester.widget<AsmPane>(find.byType(AsmPane)).cursorLine, 5);
    await _settle(tester);
    await _shot(tester, 'warp_ripple');
  });

  testWidgets('an error is listed with its position', (tester) async {
    SharedPreferences.setMockInitialValues({'draft': 'let a = in.u;\nout.dx = sin(a, 2) * 3;\nout.dy = a;\n', 'slot': 0});
    tester.view.physicalSize = const Size(1440, 880);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(key: _root, child: const ShaderIde()));
    await _settle(tester);
    expect(find.textContaining('line 2:10'), findsOneWidget);
    expect(find.textContaining('1 error'), findsOneWidget);
    await _shot(tester, 'error');
  });

  testWidgets('a scan stage shows its @out map', (tester) async {
    SharedPreferences.setMockInitialValues({'draft': templates['Scan: CSC gain rows']!.$2, 'slot': 1});
    tester.view.physicalSize = const Size(1440, 880);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(key: _root, child: const ShaderIde()));
    await _settle(tester);
    expect(find.text('out0_csc_y0'), findsOneWidget);
    await _shot(tester, 'scan_map');
  });

  testWidgets('autocomplete: typing opens the list, Enter accepts', (tester) async {
    SharedPreferences.setMockInitialValues({'draft': 'let a = in.u;\n', 'slot': 0});
    tester.view.physicalSize = const Size(1440, 880);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(key: _root, child: const ShaderIde()));
    await _settle(tester);
    final editor = find.descendant(of: find.byType(CodeEditor), matching: find.byType(TextField));
    await tester.showKeyboard(editor);
    Future<void> type(String text) async {
      tester.testTextInput.updateEditingValue(TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)));
      await tester.pump();
    }

    await type('let a = in.u;\nout.dx = a * s');
    expect(find.text('sin(x)'), findsOneWidget);
    expect(find.text('smoothstep(e0, e1, x)'), findsOneWidget);
    await _shot(tester, 'autocomplete');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // the first: sin
    await tester.pump();
    final tf = tester.widget<TextField>(editor);
    expect(tf.controller!.text, 'let a = in.u;\nout.dx = a * sin()');
    expect(tf.controller!.selection.baseOffset, 'let a = in.u;\nout.dx = a * sin('.length);
    expect(find.text('smoothstep(e0, e1, x)'), findsNothing);
    // in. lists the inputs; arrows move, Escape closes
    await type('let a = in.u;\nout.dx = a * sin(in.');
    expect(find.text('frame'), findsOneWidget); // in the list (rows past the 8th are built when scrolled to)
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('motion at the point (flow on), else 0'), findsOneWidget); // only the I/O pane now
  });

  testWidgets('the I/O pane follows the stage; the asm divider drags', (tester) async {
    SharedPreferences.setMockInitialValues({'draft': '@out gy out0_csc_y0 gain\n@out sw in_swap\nout.gy = in.v;\n', 'slot': 1});
    tester.view.physicalSize = const Size(1440, 880);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(key: _root, child: const ShaderIde()));
    await _settle(tester);
    expect(find.text('out.gy'), findsOneWidget);
    expect(find.text('declared, never written'), findsOneWidget); // sw
    expect(find.text('in.p0'), findsOneWidget); // scan stage inputs
    expect(find.text('in.heat'), findsNothing);
    final asm = find.byType(AsmPane);
    final w0 = tester.getSize(asm).width;
    await tester.drag(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_DragDivider'), const Offset(-150, 0));
    await tester.pump();
    expect(tester.getSize(asm).width, closeTo(w0 + 150, 1));
    await _shot(tester, 'io_scan');
  });

  testWidgets('the Examples button opens the bundled examples; Open loads a stage (screenshot)', (tester) async {
    SharedPreferences.setMockInitialValues({'draft': templates['Warp: ripple']!.$2, 'slot': 0});
    tester.view.physicalSize = const Size(1440, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(key: _root, child: const ShaderIde()));
    await _settle(tester);
    await tester.tap(find.text('Examples'));
    await _settle(tester);
    expect(find.text('EXAMPLES'), findsOneWidget);
    expect(find.textContaining('from examples.json'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)), 'lit sphere');
    await tester.pump();
    await tester.tap(find.descendant(of: find.byType(ListView), matching: find.text('Lit sphere')).first);
    await tester.pump(const Duration(milliseconds: 400)); // a row also takes double taps
    expect(find.text('pip/sphere'), findsOneWidget); // the detail pane shows it
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Open')));
    await _settle(tester);
    expect(find.text('EXAMPLES'), findsNothing);
    expect(find.textContaining('Scan stage'), findsOneWidget); // status bar: compiles as a scan stage
    await _shot(tester, 'ide_example_open');

    // the example is a bundle: its vertex stage is one tab away, and edits stay with their stage
    final code = tester.widget<CodeEditor>(find.byType(CodeEditor)).controller;
    final scan = code.text;
    expect(scan, contains('@out o0'));
    await tester.tap(find.text('VERTEX'));
    await _settle(tester);
    final vert = code.text;
    expect(vert, isNot(scan));
    expect(vert, contains('out.vx'));
    expect(find.textContaining('Vertex stage'), findsOneWidget);
    code.text = '// edited\n$vert';
    await _settle(tester);
    await tester.tap(find.text('SCAN'));
    await _settle(tester);
    expect(code.text, scan);
    await tester.tap(find.text('VERTEX'));
    await _settle(tester);
    expect(code.text, startsWith('// edited\n'));
    expect(find.textContaining('Vertex stage'), findsOneWidget);
    await _shot(tester, 'ide_bundle_vertex');
    // the warp tab is empty: this example has no warp stage
    await tester.tap(find.text('WARP'));
    await _settle(tester);
    expect(code.text, isEmpty);
  });
}
