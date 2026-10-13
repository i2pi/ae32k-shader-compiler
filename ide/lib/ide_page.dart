import 'dart:async';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'asm_pane.dart';
import 'code_editor.dart';
import 'device.dart';
import 'example_files.dart';
import 'example_runner.dart';
import 'examples.dart';
import 'examples_dialog.dart';
import 'io_pane.dart';
import 'sim/sim_engine.dart' show ScanPattern;
import 'sim/sim_page.dart';
import 'templates.dart';
import 'theme.dart';

const _stageNames = ['Warp', 'Scan', 'Vertex'];
const _cyclesPerLine = 3694; // 1080p24 line at 99.75 MHz
const _cyclesPerPixel = 1.34;

/// One stage of the bundle in the editor: its text, file and unsaved state.
class _Doc {
  String text;
  String? file;
  bool dirty;
  _Doc(this.text, [this.file, this.dirty = false]);
}

class _Req {
  final String src;
  final int slot;
  final bool fast;
  final Map<String, int> knobs;
  const _Req(this.src, this.slot, this.fast, this.knobs);
}

StageAnalysis _analyze(_Req r) => analyzeStage(r.src,
    slot: r.slot, fast: r.fast, fixed: r.knobs, samples: 24);

class IdePage extends StatefulWidget {
  const IdePage({super.key});
  @override
  State<IdePage> createState() => _IdePageState();
}

class _IdePageState extends State<IdePage> {
  final _code = CodeController();
  final _link = DeviceLink();
  final _host = TextEditingController(text: 'scion.local');
  SharedPreferences? _prefs;
  int _slot = 0;
  bool _fast = false,
      _showAsm = true,
      _showIo = true,
      _busy = false;
  int _cursorLine = 1;
  double _asmW = 420;
  // The bundle: one document per stage slot (warp, scan, vertex); the tabs switch between them.
  final _docs = List<_Doc?>.filled(3, null);
  _Doc get _cur => _docs[_slot] ??= _Doc('');
  String? get _file => _docs[_slot]?.file;
  bool get _dirty => _docs[_slot]?.dirty ?? false;
  bool _has(int s) => _docs[s] != null && _docs[s]!.text.trim().isNotEmpty;
  StageAnalysis? _analysis;
  Timer? _debounce, _knobSend;
  int _req = 0;
  final _knobs = List<double>.filled(8, 0);
  final _log = <String>[];
  ExampleSet? _exSet;
  Example? _example; // the example last opened or run
  final _runner = ExampleRunner();
  bool _exBusy = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onEdit);
    _link.addListener(_onLink);
    _load();
  }

  void _onLink() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    final (slot, src) = templates.values.first;
    setState(() {
      _slot = p.getInt('slot') ?? slot;
      _fast = p.getBool('fast') ?? false;
      _showAsm = p.getBool('asm') ?? true;
      _showIo = p.getBool('io') ?? true;
      _asmW = p.getDouble('asmW') ?? 420;
      _host.text = p.getString('host') ?? 'scion.local';
      for (var k = 0; k < 3; k++) {
        final t = p.getString('draft.$k');
        if (t != null) _docs[k] = _Doc(t, p.getString('file.$k'), p.getBool('dirty.$k') ?? false);
      }
      // an older single-buffer draft goes to its slot
      if (p.getString('draft') case final t? when _docs[_slot] == null) _docs[_slot] = _Doc(t, p.getString('file'));
      if (_docs.every((d) => d == null)) _docs[slot] = _Doc(src);
      if (_docs[_slot] == null) _slot = _docs.indexWhere((d) => d != null);
    });
    _show();
    final id = p.getString('example');
    if (id != null) {
      try {
        final set = _exSet ??= await ExampleSet.load(await BundledExamples.load());
        final ex = set.examples.where((e) => e.id == id).firstOrNull;
        if (ex != null && mounted) setState(() => _example = ex);
      } catch (_) {}
    }
  }

  void _onEdit() {
    final sel = _code.selection;
    if (sel.isValid) {
      final at = sel.baseOffset.clamp(0, _code.text.length);
      final line = '\n'.allMatches(_code.text.substring(0, at)).length + 1;
      if (line != _cursorLine) setState(() => _cursorLine = line);
    }
    if (_code.text == _lastText) return;
    _lastText = _code.text;
    final d = _cur;
    d.text = _code.text;
    if (!d.dirty) setState(() => d.dirty = true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _analyzeNow);
    _persist(_slot);
  }

  String _lastText = '';

  Future<void> _analyzeNow() async {
    final id = ++_req;
    final knobs = {
      for (var k = 0; k < 8; k++) 'k$k': (_knobs[k] * 65536).round()
    };
    final a = await compute(_analyze, _Req(_code.text, _slot, _fast, knobs));
    if (!mounted || id != _req) return;
    _code.diagnostics = a.diagnostics;
    setState(() => _analysis = a);
  }

  /// Shows another stage of the bundle (an empty one starts blank).
  void _setSlot(int s) {
    if (s == _slot) return;
    setState(() => _slot = s);
    _prefs?.setInt('slot', s);
    _show();
  }

  /// Puts the current slot's document in the editor.
  void _show() {
    final t = _docs[_slot]?.text ?? '';
    _lastText = t; // not an edit
    _code.text = t;
    _code.selection = const TextSelection.collapsed(offset: 0);
    _analysis = null;
    _analyzeNow();
  }

  /// Replaces the document in [slot] and shows it.
  void _setDoc(int slot, String text, String? file) {
    setState(() {
      _docs[slot] = _Doc(text, file);
      _slot = slot;
    });
    _prefs?.setInt('slot', slot);
    _persist(slot);
    _show();
  }

  void _persist(int k) {
    final d = _docs[k], p = _prefs;
    if (p == null) return;
    if (d == null) {
      p.remove('draft.$k');
      p.remove('file.$k');
      p.remove('dirty.$k');
      return;
    }
    p.setString('draft.$k', d.text);
    d.file == null ? p.remove('file.$k') : p.setString('file.$k', d.file!);
    p.setBool('dirty.$k', d.dirty);
  }

  /// Removes [slot]'s stage from the bundle.
  void _clearStage(int slot) {
    setState(() => _docs[slot] = null);
    _persist(slot);
    if (slot == _slot) _show();
  }

  void _setExample(Example? ex) {
    setState(() => _example = ex);
    ex == null ? _prefs?.remove('example') : _prefs?.setString('example', ex.id);
  }

  static int _guessSlot(String name, String src) {
    final base = name.split(RegExp(r'[/\\]')).last;
    if (base.startsWith('verts') || RegExp(r'^v\d').hasMatch(base)) return 2;
    return guessSlot(src);
  }

  // ------------------------------------------------------------------ files

  static const _types = [
    XTypeGroup(label: 'Scion shader', extensions: ['ss']),
    XTypeGroup(label: 'All files')
  ];

  Future<void> _open() async {
    final f = await openFile(acceptedTypeGroups: _types);
    if (f == null) return;
    final src = await f.readAsString();
    final slot = _guessSlot(f.name, src);
    _leaveExampleFor(slot);
    _setDoc(slot, src, f.path.isEmpty ? f.name : f.path);
    _say('opened ${f.name} (${_stageNames[slot].toLowerCase()} stage)');
  }

  Future<void> _save({bool as = false}) async {
    var path = _file;
    // a bundled example has no path on disk: Save As
    final onDisk = path != null && (path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path));
    if (as || !onDisk || kIsWeb) {
      final loc = await getSaveLocation(
          acceptedTypeGroups: _types,
          suggestedName: path?.split(RegExp(r'[/\\]')).last ?? 'stage.ss');
      if (loc == null) return;
      path = loc.path;
    }
    await XFile.fromData(Uint8List.fromList(_code.text.codeUnits),
            mimeType: 'text/plain', name: path.split('/').last)
        .saveTo(path);
    setState(() {
      _cur.file = path;
      _cur.dirty = false;
    });
    _persist(_slot);
    _say('saved $path');
  }

  void _newFrom(String name) {
    final (slot, src) = templates[name]!;
    _leaveExampleFor(slot);
    _setDoc(slot, src, null);
  }

  /// Replacing one of the example's stages with something else ends the example (the bundle
  /// keeps its other stages).
  void _leaveExampleFor(int slot) {
    if (_example?.stages.containsKey(slot) ?? false) _setExample(null);
  }

  // ----------------------------------------------------------------- device

  void _say(String s) {
    setState(() {
      _log.insert(0, '${TimeOfDay.now().format(context)}  $s');
      if (_log.length > 60) _log.removeLast();
    });
  }

  Future<void> _connect() async {
    final t = _host.text.trim();
    final i = t.lastIndexOf(':');
    final host = i > 0 && !t.contains(']') ? t.substring(0, i) : t;
    final port = i > 0 ? int.tryParse(t.substring(i + 1)) ?? 9000 : 9000;
    _prefs?.setString('host', t);
    await _link.connect(host, port);
  }

  Future<void> _find() async {
    _say('looking for SCION devices (mDNS _scion._udp)...');
    final found = await DeviceLink.discover();
    if (!mounted) return;
    if (found.isEmpty) {
      _say('none found; enter the address by hand');
      return;
    }
    final pick = found.length == 1
        ? found.first
        : await showDialog<FoundDevice>(
            context: context,
            builder: (c) => SimpleDialog(
              backgroundColor: Sc.card,
              title: Text('Devices', style: Sc.uiText(16, color: Sc.text)),
              children: [
                for (final d in found)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(c, d),
                    child: Text('${d.label}  (${d.host}:${d.port})',
                        style: Sc.uiText(14)),
                  ),
              ],
            ),
          );
    if (pick == null) return;
    _host.text = pick.port == 9000 ? pick.host : '${pick.host}:${pick.port}';
    _say('found ${pick.label}');
    await _connect();
  }

  Future<void> _upload() async {
    final st = _analysis?.stage;
    if (st == null || _busy) return;
    if (!_link.open) await _connect();
    setState(() => _busy = true);
    _say(
        'uploading ${st.bytes.length} bytes to the ${_stageNames[_slot].toLowerCase()} slot${_fast ? ' (--fast)' : ''}...');
    final r = await _link.upload(st,
        knobs: _knobs, progress: (s) => setState(() => _status = s));
    setState(() {
      _busy = false;
      _status = null;
    });
    _say(r);
  }

  String? _status;

  // --------------------------------------------------------------- examples

  Future<void> _examples() async {
    ExampleSet set;
    try {
      set = _exSet ??= await ExampleSet.load(await BundledExamples.load());
    } catch (e) {
      _say('cannot load the bundled examples: $e');
      return;
    }
    if (!mounted) return;
    final pick = await showDialog<ExampleChoice>(
      context: context,
      builder: (c) => ExamplesDialog(set: set, selectedId: _example?.id, canRun: deviceSupported),
    );
    if (pick == null || !mounted) return;
    final ex = pick.example;
    switch (pick.action) {
      case ExampleAction.open:
        await _openExample(ex, pick.slot ?? ex.primarySlot!);
      case ExampleAction.run:
        if (_example?.id != ex.id) await _openExample(ex, ex.primarySlot ?? _slot);
        await _runExample();
      case ExampleAction.simulate:
        if (_example?.id != ex.id) await _openExample(ex, ex.primarySlot ?? _slot);
        await _simulateExample(ex);
    }
  }

  /// Opens [ex] as the bundle: every one of its stages in its slot (the other slots emptied),
  /// [slot] shown, and its FAST setting and knobs.
  Future<void> _openExample(Example ex, int slot) async {
    final set = _exSet!;
    final docs = <int, _Doc>{};
    for (final MapEntry(key: s, value: rel) in ex.stages.entries) {
      try {
        docs[s] = _Doc(await set.files.text(rel), set.files.path(rel));
      } catch (e) {
        _say('$rel: cannot read ($e)');
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      for (var k = 0; k < 3; k++) {
        _docs[k] = docs[k];
      }
      _slot = ex.stages.containsKey(slot) ? slot : (ex.primarySlot ?? _slot);
      _fast = ex.fast;
      for (var k = 0; k < 8; k++) {
        _knobs[k] = ex.knobs[k] ?? 0;
      }
    });
    for (var k = 0; k < 3; k++) {
      _persist(k);
    }
    _prefs?.setInt('slot', _slot);
    _prefs?.setBool('fast', _fast);
    _setExample(ex);
    _show();
    _say('opened ${ex.title}: ${[for (final s in [0, 2, 1]) if (ex.stages[s] case final r?) '${stageLabels[s]} $r'].join(', ')}');
  }

  /// The bundle's text for each of [ex]'s stages, so a run uses the edits.
  Map<String, String> _editorSources(Example ex) => {
        for (final MapEntry(key: s, value: rel) in ex.stages.entries)
          if (_docs[s] case final d?) rel: d.text,
      };

  Future<void> _runExample() async {
    final ex = _example, set = _exSet;
    if (ex == null || set == null || _exBusy || _busy) return;
    if (!_link.open) await _connect();
    setState(() => _exBusy = true);
    _say('running ${ex.title}...');
    final ok = await _runner.run(ex, set.files, LinkTarget(_link, progress: (s) => setState(() => _status = s)), _say,
        sources: _editorSources(ex), knobs: _knobs);
    if (!mounted) return;
    setState(() {
      _exBusy = false;
      _status = null;
    });
    _say(ok ? '${ex.title}: running' : '${ex.title}: stopped at the step above');
    _analyzeNow();
  }

  Future<void> _stopExample() async {
    if (_runner.running == null || _exBusy) return;
    setState(() => _exBusy = true);
    final title = _runner.running!.title;
    await _runner.stop(LinkTarget(_link), _say);
    if (!mounted) return;
    setState(() => _exBusy = false);
    _say('$title: stopped');
  }

  Future<void> _simulateExample(Example ex) async {
    final set = _exSet!, edited = _editorSources(ex);
    final stages = <int, SimStageRef>{};
    for (final MapEntry(key: slot, value: rel) in ex.stages.entries) {
      try {
        stages[slot] = SimStageRef(rel.split('/').last, edited[rel] ?? await set.files.text(rel));
      } catch (e) {
        _say('$rel: cannot read ($e)');
        return;
      }
    }
    if (ex.blobs.isNotEmpty) _say('${ex.title}: the simulator does not run C stages (${ex.blobs.map((b) => b.$2).join(', ')})');
    final a = ex.patternArgs;
    final pattern = a == null ? null : ScanPattern(a[0] ?? 8, a[3] ?? 1, a[1] ?? 1000, a[5] ?? 0);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SimPage(
        editorSource: _code.text,
        editorSlot: _slot,
        editorName: _file?.split(RegExp(r'[/\\]')).last ?? 'untitled',
        knobs: [for (var k = 0; k < 8; k++) ex.knobs[k] ?? 0],
        fast: ex.fast,
        stages: stages,
        points: ex.vertexCount,
        pattern: pattern,
      ),
    ));
  }

  /// Simulates the bundle (the example's, with its placement, when one is open).
  void _simulate() {
    if (_example case final ex?) {
      _simulateExample(ex);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SimPage(
        editorSource: _code.text,
        editorSlot: _slot,
        editorName: _file?.split(RegExp(r'[/\\]')).last ?? 'untitled',
        knobs: _knobs,
        fast: _fast,
        stages: {
          for (var k = 0; k < 3; k++)
            if (_has(k)) k: SimStageRef(_docs[k]!.file?.split(RegExp(r'[/\\]')).last ?? 'untitled', _docs[k]!.text),
        },
      ),
    ));
  }

  void _setKnob(int k, double v) {
    setState(() => _knobs[k] = v);
    _knobSend?.cancel();
    _knobSend = Timer(const Duration(milliseconds: 40), () {
      if (_link.connected) _link.sendKnob(k, v);
      _analyzeNow();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _knobSend?.cancel();
    _link.removeListener(_onLink);
    _link.dispose();
    _code.dispose();
    _host.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final mod =
        defaultTargetPlatform == TargetPlatform.macOS ? 'meta' : 'control';
    SingleActivator key(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k,
            meta: mod == 'meta', control: mod == 'control', shift: shift);
    return CallbackShortcuts(
      bindings: {
        key(LogicalKeyboardKey.keyS): () => _save(),
        key(LogicalKeyboardKey.keyS, shift: true): () => _save(as: true),
        key(LogicalKeyboardKey.keyO): _open,
        key(LogicalKeyboardKey.keyU): _upload,
        key(LogicalKeyboardKey.keyR): _simulate,
        key(LogicalKeyboardKey.keyE): _examples,
      },
      child: Scaffold(
        body: Column(
          children: [
            _toolbar(),
            if (_example != null) _exampleBar(_example!),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showIo) ...[
                    SizedBox(
                      width: 250,
                      child: IoPane(
                          source: _code.text,
                          slot: _slot,
                          onInsert: _insert,
                          onJump: _jumpToLine),
                    ),
                    Container(width: 1, color: Colors.black38),
                  ],
                  Expanded(
                    child: CodeEditor(
                        controller: _code, analysis: _analysis, slot: _slot),
                  ),
                  if (_showAsm) ...[
                    _DragDivider(
                        onDrag: (dx) {
                          setState(
                              () => _asmW = (_asmW - dx).clamp(220.0, 1400.0));
                        },
                        onEnd: () => _prefs?.setDouble('asmW', _asmW)),
                    SizedBox(
                      width: _asmW,
                      child: AsmPane(
                          analysis: _analysis,
                          cursorLine: _cursorLine,
                          onJump: _jumpToLine),
                    ),
                  ],
                  Container(width: 1, color: Colors.black26),
                  SizedBox(width: 330, child: _sidePanel()),
                ],
              ),
            ),
            _statusBar(),
          ],
        ),
      ),
    );
  }

  Widget _toolbar() {
    final name = _file?.split(RegExp(r'[/\\]')).last ?? 'untitled';
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
          color: Sc.surface,
          border: Border(bottom: BorderSide(color: Colors.black38))),
      child: Row(
        children: [
          Text('SHADER IDE',
              style: Sc.caps(13, color: Sc.text, weight: FontWeight.w700)),
          const SizedBox(width: 14),
          PopupMenuButton<String>(
            tooltip: 'New from a template',
            color: Sc.card,
            onSelected: _newFrom,
            itemBuilder: (_) => [
              for (final t in templates.keys)
                PopupMenuItem(value: t, child: Text(t, style: Sc.uiText(14)))
            ],
            child: const _Btn(icon: Icons.add, label: 'New'),
          ),
          _Btn(icon: Icons.folder_open_outlined, label: 'Open', onTap: _open),
          _Btn(icon: Icons.save_outlined, label: 'Save', onTap: () => _save()),
          _Btn(icon: Icons.auto_awesome_motion_outlined, label: 'Examples', onTap: _examples),
          const SizedBox(width: 8),
          Flexible(
            child: Text('$name${_dirty ? ' •' : ''}',
                overflow: TextOverflow.ellipsis,
                style: Sc.uiText(14, color: Sc.label)),
          ),
          const SizedBox(width: 16),
          _StageTabs(
            labels: _stageNames,
            selected: _slot,
            present: [for (var k = 0; k < 3; k++) _has(k)],
            dirty: [for (var k = 0; k < 3; k++) _docs[k]?.dirty ?? false],
            onSelect: _setSlot,
            onClear: (k) {
              _leaveExampleFor(k);
              _clearStage(k);
            },
          ),
          const SizedBox(width: 10),
          Tooltip(
            message:
                '--fast: * wraps instead of saturating, x / 0 is +-32767.99 instead of 0; otherwise identical',
            child: _Toggle(
                label: 'FAST',
                on: _fast,
                onTap: () {
                  setState(() => _fast = !_fast);
                  _prefs?.setBool('fast', _fast);
                  _analyzeNow();
                }),
          ),
          const SizedBox(width: 6),
          _Toggle(
              label: 'I/O',
              on: _showIo,
              onTap: () {
                setState(() => _showIo = !_showIo);
                _prefs?.setBool('io', _showIo);
              }),
          const SizedBox(width: 6),
          _Toggle(
              label: 'ASM',
              on: _showAsm,
              onTap: () {
                setState(() => _showAsm = !_showAsm);
                _prefs?.setBool('asm', _showAsm);
              }),
          const SizedBox(width: 10),
          _Btn(icon: Icons.play_circle_outline, label: 'Simulate', onTap: _simulate),
          const Spacer(),
          if (deviceSupported) ...[
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _link.connected
                    ? Sc.green
                    : (_link.open ? Sc.amber : const Color(0xFF55555B)),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 170,
              child: TextField(
                controller: _host,
                style: Sc.uiText(14, color: Sc.text),
                onSubmitted: (_) => _connect(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'host[:port]',
                  filled: true,
                  fillColor: Sc.inset,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            _Btn(icon: Icons.wifi_find, label: 'Find', onTap: _find),
            _Btn(
              icon: _link.open ? Icons.link_off : Icons.link,
              label: _link.open ? 'Disconnect' : 'Connect',
              onTap: _link.open ? _link.disconnect : _connect,
            ),
          ],
          const SizedBox(width: 6),
          _UploadButton(
            enabled: deviceSupported && _analysis?.stage != null && !_busy,
            busy: _busy,
            onTap: _upload,
          ),
        ],
      ),
    );
  }

  /// The current example, under the toolbar: Run, Stop, Simulate and the step it is on.
  Widget _exampleBar(Example ex) {
    final running = _runner.running?.id == ex.id;
    Widget btn(IconData icon, String label, Color color, VoidCallback? onTap, String tip) => Tooltip(
          message: tip,
          child: TextButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 17, color: onTap == null ? Sc.faint : color),
            label: Text(label, style: Sc.uiText(13, color: onTap == null ? Sc.faint : Sc.label)),
          ),
        );
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
          color: Sc.inset, border: Border(bottom: BorderSide(color: Colors.black38))),
      child: Row(children: [
        Text('EXAMPLE', style: Sc.caps(11)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(ex.title,
              overflow: TextOverflow.ellipsis,
              style: Sc.uiText(13.5, color: running ? Sc.green : Sc.text)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
              '${running ? 'running' : ex.id}${_file == null ? '' : '  ·  ${_file!.split(RegExp(r'[/\\]')).last}'}',
              overflow: TextOverflow.ellipsis,
              style: Sc.uiText(12.5, color: running ? Sc.green : Sc.faint)),
        ),
        const Spacer(),
        if (_exBusy) ...[
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(_log.isEmpty ? '' : _log.first.replaceFirst(RegExp(r'^\S+ \S*\s+'), ''),
                overflow: TextOverflow.ellipsis, style: Sc.uiText(12.5, color: Sc.caption)),
          ),
          const SizedBox(width: 8),
        ],
        btn(Icons.play_arrow, 'Run', Sc.green, deviceSupported && ex.runnable && !_exBusy && !_busy ? _runExample : null,
            'Upload the stages and blobs, then the setup and start steps'),
        btn(Icons.stop, 'Stop', Sc.red, running && !_exBusy ? _stopExample : null, "Run the example's stop steps"),
        btn(Icons.play_circle_outline, 'Simulate', Sc.label, ex.stages.isEmpty ? null : () => _simulateExample(ex),
            'Simulate the example'),
        IconButton(
          tooltip: 'Close the example',
          visualDensity: VisualDensity.compact,
          onPressed: () => _setExample(null),
          icon: const Icon(Icons.close, size: 16, color: Sc.faint),
        ),
      ]),
    );
  }

  Widget _sidePanel() {
    final a = _analysis;
    return Container(
      color: Sc.background,
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          _Card(title: 'Cost', child: _summary(a)),
          _Card(
            title: 'Problems',
            child: (a == null || a.diagnostics.isEmpty)
                ? Text(a == null ? 'compiling...' : 'none',
                    style: Sc.uiText(13, color: Sc.green))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final d in a.diagnostics)
                        InkWell(
                          onTap: () => _jumpTo(d),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                    d.isError
                                        ? Icons.error_outline
                                        : Icons.info_outline,
                                    size: 15,
                                    color: d.isError ? Sc.red : Sc.amber),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    d.line == null
                                        ? d.message
                                        : 'line ${d.line}${d.column == null ? '' : ':${d.column}'}  ${d.message}',
                                    style: Sc.uiText(13, color: Sc.body),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          _Card(
            title: 'Knobs',
            child: Column(
              children: [
                for (var k = 0; k < 8; k++)
                  Row(
                    children: [
                      SizedBox(
                          width: 26,
                          child: Text('k$k',
                              style: Sc.uiText(13, color: Sc.label))),
                      Expanded(
                        child: Slider(
                            value: _knobs[k],
                            min: -8,
                            max: 8,
                            onChanged: (v) =>
                                _setKnob(k, (v * 100).round() / 100)),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(_knobs[k].toStringAsFixed(2),
                            textAlign: TextAlign.right,
                            style: Sc.uiText(13, color: Sc.text)),
                      ),
                    ],
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    deviceSupported
                        ? 'Live on the device when connected; also used for the cost estimate.'
                        : 'Used for the cost estimate.',
                    style: Sc.uiText(11.5, color: Sc.faint),
                  ),
                ),
              ],
            ),
          ),
          _Card(
            title: 'Log',
            child: _log.isEmpty
                ? Text(
                    deviceSupported
                        ? _link.status
                        : 'Uploading needs the desktop build.',
                    style: Sc.uiText(12.5, color: Sc.faint))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in _log.take(14))
                        Text(l, style: Sc.uiText(12.5, color: Sc.body))
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summary(StageAnalysis? a) {
    if (a == null) return Text('compiling...', style: Sc.uiText(13));
    final st = a.stage;
    if (st == null) {
      return Text('does not compile', style: Sc.uiText(14, color: Sc.red));
    }
    final size = st.bytes.length;
    final entry = a.lines[0]?.cycles ?? 0;
    final per = switch (_slot) {
      0 => 'per warp grid point',
      1 =>
        'per scan point = ${(a.meanCycles / _cyclesPerPixel).toStringAsFixed(0)} px at 1080p24',
      _ =>
        'per vertex; 96 points = ${(a.meanCycles * 96 / _cyclesPerLine).toStringAsFixed(1)} lines',
    };
    Widget row(String k, String v, [Color c = Sc.text]) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(
                width: 92,
                child: Text(k, style: Sc.uiText(13, color: Sc.caption))),
            Expanded(child: Text(v, style: Sc.uiText(14, color: c))),
          ]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(a.meanCycles.toStringAsFixed(0),
                style: Sc.uiText(30,
                    color: costColor(a.meanCycles / 8),
                    weight: FontWeight.w700)),
            const SizedBox(width: 6),
            Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('cycles', style: Sc.uiText(14, color: Sc.caption))),
          ],
        ),
        Text(per, style: Sc.uiText(12.5, color: Sc.faint)),
        const SizedBox(height: 8),
        row('range', '${a.minCycles}–${a.maxCycles} over ${a.samples} inputs'),
        row('entry/exit', '${entry.toStringAsFixed(0)} cycles'),
        row('of a line',
            '${(100 * a.meanCycles / _cyclesPerLine).toStringAsFixed(1)} %'),
        row('size', '$size / $maxBlobBytes bytes',
            size > maxBlobBytes * 0.8 ? Sc.amber : Sc.text),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: size / maxBlobBytes,
            minHeight: 4,
            backgroundColor: Sc.inset,
            color: size > maxBlobBytes * 0.8 ? Sc.amber : Sc.blue,
          ),
        ),
        const SizedBox(height: 8),
        Text(
            'Emulator estimate (fitted to the device, ~5%). The gutter shows each line\'s share; * = inside an if.',
            style: Sc.uiText(11.5, color: Sc.faint)),
      ],
    );
  }

  Widget _statusBar() {
    final a = _analysis;
    final err = a?.diagnostics.where((d) => d.isError).length ?? 0;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Sc.surface,
      child: Row(
        children: [
          Text(
            a == null
                ? 'compiling'
                : (a.stage == null
                    ? '$err error${err == 1 ? '' : 's'}'
                    : '${_stageNames[_slot]} stage${_fast ? ', --fast' : ''}: compiles'),
            style: Sc.uiText(12.5, color: a?.stage == null ? Sc.red : Sc.green),
          ),
          const Spacer(),
          Text(_status ?? (deviceSupported ? _link.status : ''),
              style: Sc.uiText(12.5, color: Sc.caption)),
        ],
      ),
    );
  }

  /// Inserts [text] at the cursor (from the I/O pane).
  void _insert(String text) {
    final sel = _code.selection;
    final at = sel.isValid ? sel.start : _code.text.length,
        end = sel.isValid ? sel.end : at;
    _code.value = TextEditingValue(
        text: _code.text.replaceRange(at, end, text),
        selection: TextSelection.collapsed(offset: at + text.length));
  }

  /// Puts the cursor at the start of source line [line] (from the assembly pane).
  void _jumpToLine(int line) {
    final lines = _code.text.split('\n');
    var off = 0;
    for (var i = 0; i < line - 1 && i < lines.length; i++) {
      off += lines[i].length + 1;
    }
    final lead = line - 1 < lines.length
        ? lines[line - 1].length - lines[line - 1].trimLeft().length
        : 0;
    _code.selection = TextSelection.collapsed(offset: off + lead);
  }

  void _jumpTo(Diagnostic d) {
    final r = CodeController.errorRange(_code.text, d);
    if (r == null) return;
    _code.selection = TextSelection(baseOffset: r.$1, extentOffset: r.$2);
  }
}

// ------------------------------------------------------------------ widgets

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: Sc.cardBox(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: Sc.caps(11, color: Sc.caption)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _Btn({required this.icon, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) {
    final body = Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
          color: Sc.buttonFace, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: const Color(0xFFE6E6EA)),
        const SizedBox(width: 6),
        Text(label, style: Sc.uiText(13.5, color: const Color(0xFFE6E6EA))),
      ]),
    );
    return onTap == null
        ? body
        : InkWell(
            borderRadius: BorderRadius.circular(6), onTap: onTap, child: body);
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Toggle({required this.label, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: on
                ? Color.lerp(const Color(0xFF3A3A3C), Sc.red, 0.85)
                : Sc.buttonFace,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
              style: Sc.caps(12,
                  color: on ? Colors.black : const Color(0xFFE6E6EA),
                  weight: FontWeight.w700)),
        ),
      );
}

/// The bundle's stages: WARP / SCAN / VERTEX, each its own document. A stage with code is
/// bright (a dot when it has unsaved edits); an empty one is dim. The shown stage has an x that
/// removes it from the bundle.
class _StageTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final List<bool> present, dirty;
  final ValueChanged<int> onSelect, onClear;
  const _StageTabs(
      {required this.labels,
      required this.selected,
      required this.present,
      required this.dirty,
      required this.onSelect,
      required this.onClear});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
            color: Sc.inset, borderRadius: BorderRadius.circular(7)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < labels.length; i++)
            Tooltip(
              message: present[i]
                  ? '${labels[i]} stage${dirty[i] ? ' (unsaved edits)' : ''}'
                  : '${labels[i]} stage: empty (New or Open puts one here)',
              child: InkWell(
                onTap: () => onSelect(i),
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  padding: EdgeInsets.fromLTRB(12, 6, i == selected && present[i] ? 4 : 12, 6),
                  decoration: BoxDecoration(
                    color: i == selected
                        ? Color.lerp(const Color(0xFF3A3A3C), Sc.blue, 0.85)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(labels[i].toUpperCase(),
                        style: Sc.caps(12,
                            color: i == selected
                                ? Colors.black
                                : (present[i] ? Sc.label : Sc.faint),
                            weight: FontWeight.w700)),
                    if (dirty[i] && present[i])
                      Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == selected ? Colors.black : Sc.amber)),
                      ),
                    if (i == selected && present[i])
                      InkWell(
                        onTap: () => onClear(i),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 6, right: 2),
                          child: Icon(Icons.close, size: 13, color: Colors.black54),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
        ]),
      );
}

class _UploadButton extends StatelessWidget {
  final bool enabled, busy;
  final VoidCallback onTap;
  const _UploadButton(
      {required this.enabled, required this.busy, required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: deviceSupported
            ? 'Upload to the device (Cmd/Ctrl+U)'
            : 'Uploading needs the desktop build',
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: enabled ? Sc.primary : const Color(0xFF2C2C31),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              busy
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Icon(Icons.upload,
                      size: 17,
                      color: enabled ? Colors.black : const Color(0xFF74747C)),
              const SizedBox(width: 6),
              Text('UPLOAD',
                  style: Sc.caps(12.5,
                      color: enabled ? Colors.black : const Color(0xFF74747C),
                      weight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

/// A vertical splitter: drag to resize the pane on its right.
class _DragDivider extends StatelessWidget {
  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;
  const _DragDivider({required this.onDrag, required this.onEnd});
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
          onHorizontalDragEnd: (_) => onEnd(),
          child: SizedBox(
            width: 7,
            child: Center(child: Container(width: 1, color: Colors.black38)),
          ),
        ),
      );
}
