// Frame simulator: pick a format, the warp / vertex / scan stages and a simulated source, and
// watch the result play. The stages run in the reference evaluator (bit-exact with the device's
// native code); the picture model is approximate: the warp grid as the MFC applies it, cells and
// per-line register values as the resident's cell rasteriser writes them, and a visual model of
// the common registers (CSC, channel swaps, ...). Registers without a model show as a trace.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import 'sim_engine.dart';
import 'sim_render.dart';
import 'sim_source.dart';

const _formats = <(String, int, int)>[
  ('1920 × 1080', 1920, 1080),
  ('1280 × 720', 1280, 720),
  ('960 × 540 (preview)', 960, 540),
  ('720 × 480', 720, 480),
  ('720 × 576', 720, 576),
];
const _rates = <(String, double)>[
  ('23.98', 24000 / 1001),
  ('24', 24),
  ('25', 25),
  ('29.97', 30000 / 1001),
  ('30', 30),
  ('50', 50),
  ('59.94', 60000 / 1001),
  ('60', 60),
];
const _stageLabel = ['WARP', 'SCAN', 'VERTEX'];

/// A stage loaded into the simulator: from the editor or a file.
class SimStageRef {
  final String name, source;
  const SimStageRef(this.name, this.source);
}

class SimPage extends StatefulWidget {
  /// The editor's buffer and its stage slot, offered as "from the editor".
  final String editorSource;
  final int editorSlot;
  final String editorName;
  final List<double> knobs;
  final bool fast;

  /// An example's stages by slot (replacing the remembered ones), and its placement: the vertex
  /// count of `imcu scan verts`, the pattern of `imcu scan start`.
  final Map<int, SimStageRef>? stages;
  final int? points;
  final ScanPattern? pattern;
  const SimPage(
      {super.key,
      required this.editorSource,
      required this.editorSlot,
      required this.editorName,
      required this.knobs,
      required this.fast,
      this.stages,
      this.points,
      this.pattern});
  @override
  State<SimPage> createState() => _SimPageState();
}

class _SimPageState extends State<SimPage> with SingleTickerProviderStateMixin {
  SharedPreferences? _prefs;
  int _format = 0, _rate = 1;
  SourceKind _sourceKind = SourceKind.card;
  ui.Image? _fileImage;
  final _stages = List<SimStageRef?>.filled(3, null);
  late bool _fast = widget.fast;
  late final List<double> _knobs = List.of(widget.knobs);
  final _overlay = SimOverlays();
  // scan placement without a vertex stage: the pattern mode of `imcu scan start`
  int _patLstep = 8, _patXn = 1, _patLines = 1000, _patPhase = 0;
  int _points = 96;

  SimEngine? _engine;
  SimSource? _source;
  SimFrame? _frame;
  ui.Image? _image; // the composed picture
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _clock = 0; // seconds of simulated time
  int _frameNo = 0;
  bool _playing = true;
  double _speed = 1;
  String? _error;
  double _evalMs = 0;

  int get _w => _formats[_format].$2;
  int get _h => _formats[_format].$3;
  double get _fps => _rates[_rate].$2;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    final pat = widget.pattern;
    if (pat != null) {
      _patLstep = pat.lstep;
      _patXn = pat.xn;
      _patLines = pat.lines;
      _patPhase = pat.phase;
    }
    if (widget.stages case final st?) {
      for (final e in st.entries) {
        _stages[e.key] = e.value;
      }
    } else {
      _stages[widget.editorSlot] = SimStageRef('${widget.editorName} (editor)', widget.editorSource);
    }
    _init();
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    _format = (p.getInt('sim.format') ?? 0).clamp(0, _formats.length - 1);
    _rate = (p.getInt('sim.rate') ?? 1).clamp(0, _rates.length - 1);
    _sourceKind = SourceKind.values[(p.getInt('sim.source') ?? 0).clamp(0, SourceKind.values.length - 1)];
    _points = widget.points ?? p.getInt('sim.points') ?? 96;
    for (var s = 0; s < 3; s++) {
      if (s == widget.editorSlot || widget.stages != null) continue;
      final path = p.getString('sim.stage$s');
      if (path != null) {
        try {
          _stages[s] = SimStageRef(path.split(RegExp(r'[/\\]')).last, await XFile(path).readAsString());
        } catch (_) {}
      }
    }
    await _rebuild();
    _ticker.start();
  }

  Future<void> _rebuild() async {
    final src = SimSource(_w, _h, _sourceKind, _fileImage);
    await src.prepare();
    final e = SimEngine(
      w: _w,
      h: _h,
      fps: _fps,
      fast: _fast,
      warp: _stages[0]?.source,
      scan: _stages[1]?.source,
      vertex: _stages[2]?.source,
      points: _points,
      pattern: ScanPattern(_patLstep, _patXn, _patLines, _patPhase),
    );
    if (!mounted) return;
    setState(() {
      _source = src;
      _engine = e;
      _error = e.errors.isEmpty ? null : e.errors.join('\n');
    });
    _renderFrame();
  }

  void _tick(Duration now) {
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (!_playing || dt <= 0 || dt > 0.5) return;
    _clock += dt * _speed;
    final f = (_clock * _fps).floor();
    if (f != _frameNo) {
      _frameNo = f;
      _renderFrame();
    }
  }

  void _renderFrame() {
    final e = _engine, s = _source;
    if (e == null || s == null) return;
    final sw = Stopwatch()..start();
    final knobs = {for (var k = 0; k < 8; k++) 'k$k': (_knobs[k] * 65536).round()};
    final fr = e.frame(_frameNo, knobs);
    _evalMs = _evalMs * 0.9 + sw.elapsedMicroseconds / 1000 * 0.1;
    final src = s.frame(_frameNo / _fps);
    final img = composeFrame(src, fr, _overlay, _w, _h);
    src.dispose();
    setState(() {
      _image?.dispose();
      _image = img;
      _frame = fr;
    });
  }

  void _setPref(String k, int v) => _prefs?.setInt(k, v);

  Future<void> _pickStage(int slot) async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Scion shader', extensions: ['ss'])
    ]);
    if (f == null) return;
    final src = await f.readAsString();
    setState(() => _stages[slot] = SimStageRef(f.name, src));
    if (f.path.isNotEmpty) _prefs?.setString('sim.stage$slot', f.path);
    _rebuild();
  }

  @visibleForTesting
  void debugSetStage(int slot, String name, String source) {
    setState(() => _stages[slot] = SimStageRef(name, source));
    _rebuild();
  }

  void _clearStage(int slot) {
    setState(() => _stages[slot] = null);
    _prefs?.remove('sim.stage$slot');
    _rebuild();
  }

  void _fromEditor(int slot) {
    setState(() => _stages[slot] = SimStageRef('${widget.editorName} (editor)', widget.editorSource));
    _rebuild();
  }

  Future<void> _pickImage() async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp'])
    ]);
    if (f == null) return;
    final codec = await ui.instantiateImageCodec(await f.readAsBytes());
    final img = (await codec.getNextFrame()).image;
    setState(() {
      _fileImage = img;
      _sourceKind = SourceKind.image;
    });
    _rebuild();
  }

  void _restart() {
    _clock = 0;
    _frameNo = 0;
    _renderFrame();
  }

  void _step(int d) {
    _playing = false;
    _frameNo = (_frameNo + d).clamp(0, 1 << 30);
    _clock = _frameNo / _fps;
    _renderFrame();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _image?.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          _toolbar(),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 300, child: _controls()),
              Container(width: 1, color: Colors.black38),
              Expanded(child: _viewer()),
              Container(width: 1, color: Colors.black38),
              SizedBox(width: 300, child: _stats()),
            ]),
          ),
        ]),
      );

  Widget _toolbar() => Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
            color: Sc.surface, border: Border(bottom: BorderSide(color: Colors.black38))),
        child: Row(children: [
          IconButton(
              tooltip: 'Back to the editor',
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: () => Navigator.pop(context)),
          Text('SIMULATOR', style: Sc.caps(13, color: Sc.text, weight: FontWeight.w700)),
          const SizedBox(width: 20),
          IconButton(
              tooltip: 'Restart (t = 0)', icon: const Icon(Icons.replay, size: 20), onPressed: _restart),
          IconButton(
              tooltip: 'Previous frame', icon: const Icon(Icons.skip_previous, size: 20), onPressed: () => _step(-1)),
          IconButton(
            tooltip: _playing ? 'Pause' : 'Play',
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow, size: 22),
            onPressed: () => setState(() => _playing = !_playing),
          ),
          IconButton(
              tooltip: 'Next frame', icon: const Icon(Icons.skip_next, size: 20), onPressed: () => _step(1)),
          const SizedBox(width: 8),
          for (final s in const [0.25, 0.5, 1.0])
            _Chip(
                label: '${s == 1 ? '1' : s}×',
                on: _speed == s,
                onTap: () => setState(() => _speed = s)),
          const SizedBox(width: 16),
          Text('frame $_frameNo   t ${(_frameNo / _fps).toStringAsFixed(2)} s',
              style: Sc.uiText(13.5, color: Sc.label)),
          const Spacer(),
          Text('$_w × $_h @ ${_rates[_rate].$1}', style: Sc.uiText(13.5, color: Sc.caption)),
        ]),
      );

  Widget _controls() => Container(
        color: Sc.background,
        child: ListView(padding: const EdgeInsets.all(10), children: [
          _Card(
            title: 'Format',
            child: Column(children: [
              _Drop<int>(
                label: 'Resolution',
                value: _format,
                items: {for (var i = 0; i < _formats.length; i++) i: _formats[i].$1},
                onChanged: (v) {
                  setState(() => _format = v);
                  _setPref('sim.format', v);
                  _rebuild();
                },
              ),
              _Drop<int>(
                label: 'Frame rate',
                value: _rate,
                items: {for (var i = 0; i < _rates.length; i++) i: '${_rates[i].$1} fps'},
                onChanged: (v) {
                  setState(() => _rate = v);
                  _setPref('sim.rate', v);
                  _rebuild();
                },
              ),
            ]),
          ),
          _Card(
            title: 'Stages',
            child: Column(children: [
              for (final s in const [0, 2, 1]) _stageRow(s),
              Row(children: [
                Text('FAST', style: Sc.caps(11.5, color: Sc.caption)),
                const Spacer(),
                Switch(
                    value: _fast,
                    onChanged: (v) {
                      setState(() => _fast = v);
                      _rebuild();
                    }),
              ]),
            ]),
          ),
          _Card(
            title: 'Scan placement',
            child: _stages[2] != null
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Cell mode: the scan stage runs once per vertex.',
                        style: Sc.uiText(12.5, color: Sc.faint)),
                    _IntField(
                        label: 'Points (n)',
                        value: _points,
                        min: 1,
                        max: 128,
                        onChanged: (v) {
                          _points = v;
                          _setPref('sim.points', v);
                          _rebuild();
                        }),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Pattern mode (imcu scan start): no vertex stage loaded.',
                        style: Sc.uiText(12.5, color: Sc.faint)),
                    _IntField(
                        label: 'Every n-th line',
                        value: _patLstep,
                        min: 1,
                        max: 64,
                        onChanged: (v) {
                          _patLstep = v;
                          _rebuild();
                        }),
                    _IntField(
                        label: 'Points per line',
                        value: _patXn,
                        min: 1,
                        max: 16,
                        onChanged: (v) {
                          _patXn = v;
                          _rebuild();
                        }),
                    _IntField(
                        label: 'Walk lines',
                        value: _patLines,
                        min: 45,
                        max: 1125,
                        onChanged: (v) {
                          _patLines = v;
                          _rebuild();
                        }),
                    _IntField(
                        label: 'Line phase',
                        value: _patPhase,
                        min: 0,
                        max: 63,
                        onChanged: (v) {
                          _patPhase = v;
                          _rebuild();
                        }),
                  ]),
          ),
          _Card(
            title: 'Source',
            child: Column(children: [
              _Drop<SourceKind>(
                label: 'Input',
                value: _sourceKind,
                items: {for (final k in SourceKind.values) k: k.label},
                onChanged: (v) {
                  if (v == SourceKind.image && _fileImage == null) {
                    _pickImage();
                    return;
                  }
                  setState(() => _sourceKind = v);
                  _setPref('sim.source', v.index);
                  _rebuild();
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: Text('Load image…', style: Sc.uiText(13))),
              ),
            ]),
          ),
          _Card(
            title: 'Overlays',
            child: Column(children: [
              _Check('Warp grid', _overlay.warpGrid, (v) => setState(() => _overlay.warpGrid = v)),
              _Check('Cells and vertices', _overlay.cells, (v) => setState(() => _overlay.cells = v)),
              _Check('Scan points', _overlay.points, (v) => setState(() => _overlay.points = v)),
              _Check('Register effects', _overlay.effects, (v) {
                _overlay.effects = v;
                _renderFrame();
              }),
              _Check('Output trace (unmodelled registers)', _overlay.trace, (v) => setState(() => _overlay.trace = v)),
              _Check('Source only (bypass)', _overlay.bypass, (v) {
                _overlay.bypass = v;
                _renderFrame();
              }),
            ]),
          ),
          _Card(
            title: 'Knobs',
            child: Column(children: [
              for (var k = 0; k < 8; k++)
                Row(children: [
                  SizedBox(width: 26, child: Text('k$k', style: Sc.uiText(13, color: Sc.label))),
                  Expanded(
                    child: Slider(
                        value: _knobs[k],
                        min: -8,
                        max: 8,
                        onChanged: (v) {
                          setState(() => _knobs[k] = (v * 100).round() / 100);
                          if (!_playing) _renderFrame();
                        }),
                  ),
                  SizedBox(
                      width: 44,
                      child: Text(_knobs[k].toStringAsFixed(2),
                          textAlign: TextAlign.right, style: Sc.uiText(13, color: Sc.text))),
                ]),
            ]),
          ),
        ]),
      );

  Widget _stageRow(int slot) {
    final st = _stages[slot];
    final err = _engine?.stageError(slot);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(width: 62, child: Text(_stageLabel[slot], style: Sc.caps(11.5, color: Sc.caption))),
          Expanded(
            child: Text(st?.name ?? 'none',
                overflow: TextOverflow.ellipsis,
                style: Sc.uiText(13.5, color: st == null ? Sc.faint : (err == null ? Sc.text : Sc.red))),
          ),
          _IconBtn(icon: Icons.folder_open_outlined, tip: 'Load a .ss file', onTap: () => _pickStage(slot)),
          if (slot == widget.editorSlot)
            _IconBtn(icon: Icons.edit_note, tip: "Use the editor's stage", onTap: () => _fromEditor(slot)),
          if (st != null) _IconBtn(icon: Icons.close, tip: 'Remove', onTap: () => _clearStage(slot)),
        ]),
        if (err != null)
          Padding(
            padding: const EdgeInsets.only(left: 62, top: 2),
            child: Text(err, style: Sc.uiText(12, color: Sc.red)),
          ),
      ]),
    );
  }

  Widget _viewer() => Container(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: _w / _h,
            child: _image == null || _frame == null
                ? const SizedBox()
                : CustomPaint(
                    painter: SimPainter(_image!, _frame!, _overlay, _w, _h),
                    size: Size.infinite,
                  ),
          ),
        ),
      );

  Widget _stats() {
    final f = _frame, e = _engine;
    Widget row(String k, String v, [Color c = Sc.text]) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(width: 120, child: Text(k, style: Sc.uiText(13, color: Sc.caption))),
            Expanded(child: Text(v, style: Sc.uiText(13.5, color: c))),
          ]),
        );
    return Container(
      color: Sc.background,
      child: ListView(padding: const EdgeInsets.all(10), children: [
        if (_error != null)
          _Card(title: 'Problems', child: Text(_error!, style: Sc.uiText(12.5, color: Sc.red))),
        if (f != null && e != null) ...[
          _Card(
            title: 'This frame',
            child: Column(children: [
              row('warp points', '${f.warpPoints}'),
              row('vertices', '${f.cells.length}'),
              row('scan evaluations', '${f.scanEvals}'),
              row('register writes', '${f.writes}'),
              row('simulator', '${_evalMs.toStringAsFixed(1)} ms / frame', Sc.caption),
            ]),
          ),
          _Card(
            title: 'Device budget (estimate)',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final b in e.budget(f)) row(b.$1, b.$2, b.$3 ? Sc.text : Sc.amber),
              const SizedBox(height: 6),
              Text('Emulator cycle estimates (device-fitted, ~5%) against the 1080p24 frame.',
                  style: Sc.uiText(11.5, color: Sc.faint)),
            ]),
          ),
          if (f.outputs.isNotEmpty)
            _Card(
              title: 'Scan outputs',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final o in f.outputs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${o.name}: ${o.target}', style: Sc.uiText(13, color: Sc.label)),
                      Text(
                          '${o.mode}, ${o.granularity.isEmpty ? '?' : o.granularity}; ${o.modelled ? 'modelled' : 'trace only'}'
                          '${o.range == null ? '' : '; ${o.range}'}',
                          style: Sc.uiText(12, color: o.modelled ? Sc.faint : Sc.amber)),
                    ]),
                  ),
              ]),
            ),
        ],
      ]),
    );
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: Sc.caps(11, color: Sc.caption)),
          const SizedBox(height: 8),
          child,
        ]),
      );
}

class _Drop<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  const _Drop({required this.label, required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(width: 92, child: Text(label, style: Sc.uiText(13, color: Sc.caption))),
        Expanded(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            isDense: true,
            dropdownColor: Sc.card,
            underline: const SizedBox(),
            style: Sc.uiText(13.5, color: Sc.text),
            items: [
              for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ]);
}

class _IntField extends StatefulWidget {
  final String label;
  final int value, min, max;
  final ValueChanged<int> onChanged;
  const _IntField(
      {required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final _c = TextEditingController(text: '${widget.value}');
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Expanded(child: Text(widget.label, style: Sc.uiText(13, color: Sc.caption))),
          SizedBox(
            width: 70,
            child: TextField(
              controller: _c,
              textAlign: TextAlign.right,
              style: Sc.uiText(13.5, color: Sc.text),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Sc.inset,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide.none),
              ),
              onSubmitted: (s) {
                final v = (int.tryParse(s.trim()) ?? widget.value).clamp(widget.min, widget.max);
                _c.text = '$v';
                widget.onChanged(v);
              },
            ),
          ),
        ]),
      );
}

class _Check extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Check(this.label, this.value, this.onChanged);
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChanged(!value),
        child: Row(children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v ?? false), visualDensity: VisualDensity.compact),
          Expanded(child: Text(label, style: Sc.uiText(13, color: Sc.body))),
        ]),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
              color: on ? Color.lerp(const Color(0xFF3A3A3C), Sc.blue, 0.85) : Sc.buttonFace,
              borderRadius: BorderRadius.circular(5)),
          child: Text(label, style: Sc.caps(12, color: on ? Colors.black : Sc.label, weight: FontWeight.w700)),
        ),
      );
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.tip, required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 17, color: Sc.label)),
        ),
      );
}

