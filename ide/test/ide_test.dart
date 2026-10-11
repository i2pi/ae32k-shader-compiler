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
}
