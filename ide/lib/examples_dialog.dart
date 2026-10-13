// The Examples browser: the entries of tools/imcu/examples/examples.json (or, without one, every
// .ss file there), grouped by folder, each with a compile check against this compiler. Picking one
// opens a stage in the editor, runs the example on the device, or simulates it.
import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'example_files.dart';
import 'examples.dart';
import 'theme.dart';

enum ExampleAction { open, run, simulate }

class ExampleChoice {
  final Example example;
  final ExampleAction action;

  /// For [ExampleAction.open]: the stage slot to open.
  final int? slot;
  const ExampleChoice(this.example, this.action, [this.slot]);
}

/// The loaded examples folder.
class ExampleSet {
  final ExampleFiles files;
  final List<Example> examples;
  final List<String> errors;
  final bool fromManifest;
  const ExampleSet(this.files, this.examples, this.errors, this.fromManifest);

  static Future<ExampleSet> load(ExampleFiles files) async {
    final errors = <String>[];
    if (files.exists('examples.json')) {
      try {
        final ex = parseManifest(await files.text('examples.json'), errors: errors);
        return ExampleSet(files, ex, errors, true);
      } on FormatException catch (e) {
        errors.add('examples.json: ${e.message}');
      }
    }
    final ex = <Example>[];
    for (final rel in await files.shaders()) {
      ex.add(fileExample(rel, await files.text(rel)));
    }
    return ExampleSet(files, ex, errors, false);
  }
}

class _CompileReq {
  final String key, src;
  final int slot;
  final bool fast;
  const _CompileReq(this.key, this.src, this.slot, this.fast);
}

/// Compiles a batch (one isolate per batch, not per stage); key -> error or null.
Map<String, String?> _compileErrors(List<_CompileReq> rs) => {
      for (final r in rs)
        r.key: () {
          try {
            compileStage(r.src, slot: r.slot, fast: r.fast);
            return null;
          } catch (e) {
            return '$e';
          }
        }(),
    };

/// Compile results by "path|slot|fast", kept for the session (Recheck clears them).
final _checked = <String, String?>{};

class ExamplesDialog extends StatefulWidget {
  final ExampleSet set;
  final String? selectedId;
  final bool canRun;
  const ExamplesDialog({super.key, required this.set, this.selectedId, required this.canRun});
  @override
  State<ExamplesDialog> createState() => _ExamplesDialogState();
}

class _ExamplesDialogState extends State<ExamplesDialog> {
  final _filter = TextEditingController();
  late Example? _sel =
      widget.set.examples.where((e) => e.id == widget.selectedId).firstOrNull ?? widget.set.examples.firstOrNull;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _filter.addListener(() => setState(() {}));
    _checkAll();
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  static String _key(String rel, int slot, bool fast) => '$rel|$slot|$fast';

  Future<void> _checkAll() async {
    setState(() => _checking = true);
    final want = <String, (String, int, bool)>{};
    for (final ex in widget.set.examples) {
      for (final MapEntry(key: slot, value: rel) in ex.stages.entries) {
        final k = _key(rel, slot, ex.fast);
        if (!_checked.containsKey(k)) want[k] = (rel, slot, ex.fast);
      }
    }
    // read every file at once, then compile in batches (one isolate per batch, not per stage)
    final todo = <_CompileReq>[];
    await Future.wait([
      for (final MapEntry(key: k, value: (rel, slot, fast)) in want.entries)
        widget.set.files.text(rel).then((src) => todo.add(_CompileReq(k, src, slot, fast)),
            onError: (Object e) => _checked[k] = 'cannot read: $e'),
    ]);
    if (!mounted) return;
    for (var i = 0; i < todo.length; i += 24) {
      final done = await compute(_compileErrors, todo.sublist(i, (i + 24).clamp(0, todo.length)));
      if (!mounted) return;
      setState(() => _checked.addAll(done));
    }
    if (mounted) setState(() => _checking = false);
  }

  /// null = all stages compile, '' = not checked yet, else the first error.
  String? _status(Example ex) {
    for (final MapEntry(key: slot, value: rel) in ex.stages.entries) {
      final k = _key(rel, slot, ex.fast);
      if (!_checked.containsKey(k)) return '';
      if (_checked[k] != null) return '$rel: ${_checked[k]}';
    }
    for (final (_, rel) in ex.blobs) {
      if (!widget.set.files.exists(rel)) return '$rel: missing (rebuild the C stages)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final q = _filter.text.trim().toLowerCase();
    final shown = widget.set.examples
        .where((e) => q.isEmpty || '${e.id} ${e.title} ${e.desc}'.toLowerCase().contains(q))
        .toList();
    // a selection the filter hides gives way to the first match
    if (shown.isNotEmpty && !shown.contains(_sel)) _sel = shown.first;
    final failing = widget.set.examples.where((e) => (_status(e) ?? '').isNotEmpty).length;
    return Dialog(
      backgroundColor: Sc.background,
      insetPadding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 780),
        child: Column(
          children: [
            Container(
              color: Sc.surface,
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
              child: Row(children: [
                Text('EXAMPLES', style: Sc.caps(13, color: Sc.text, weight: FontWeight.w700)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${widget.set.files.label}  ·  ${widget.set.examples.length} '
                    '${widget.set.fromManifest ? 'from examples.json' : 'stage files (no examples.json: upload only)'}'
                    '${_checking ? '  ·  checking...' : failing == 0 ? '  ·  all compile' : '  ·  $failing do not compile'}',
                    overflow: TextOverflow.ellipsis,
                    style: Sc.uiText(12.5, color: failing > 0 && !_checking ? Sc.amber : Sc.caption),
                  ),
                ),
                TextButton(
                  onPressed: _checking
                      ? null
                      : () {
                          _checked.clear();
                          _checkAll();
                        },
                  child: Text('Recheck', style: Sc.uiText(13, color: _checking ? Sc.faint : Sc.blue)),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18, color: Sc.label)),
              ]),
            ),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 400,
                  child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: TextField(
                        controller: _filter,
                        autofocus: true,
                        style: Sc.uiText(14, color: Sc.text),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'filter',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          filled: true,
                          fillColor: Sc.inset,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    for (final e in widget.set.errors)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                        child: Text(e, style: Sc.uiText(12, color: Sc.red)),
                      ),
                    Expanded(child: _list(shown)),
                  ]),
                ),
                Container(width: 1, color: Colors.black38),
                Expanded(child: _sel == null ? const SizedBox() : _detail(_sel!)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<Example> shown) {
    final rows = <Widget>[];
    String? group;
    for (final e in shown) {
      if (e.group != group) {
        group = e.group;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 4),
          child: Text(group.isEmpty ? 'TOP LEVEL' : group.toUpperCase(), style: Sc.caps(11)),
        ));
      }
      final st = _status(e);
      final sel = identical(e, _sel);
      rows.add(InkWell(
        onTap: () => setState(() => _sel = e),
        onDoubleTap: () => Navigator.pop(context, ExampleChoice(e, ExampleAction.open, e.primarySlot)),
        child: Container(
          color: sel ? Sc.card : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          child: Row(children: [
            Icon(
              st == '' ? Icons.more_horiz : (st == null ? Icons.check : Icons.error_outline),
              size: 14,
              color: st == '' ? Sc.faint : (st == null ? Sc.green : Sc.red),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(e.title,
                  overflow: TextOverflow.ellipsis,
                  style: Sc.uiText(13.5, color: e.runnable ? Sc.text : Sc.caption)),
            ),
            if (!e.runnable) Text('probe', style: Sc.uiText(11.5, color: Sc.faint)),
          ]),
        ),
      ));
    }
    return ListView(children: rows);
  }

  Widget _detail(Example e) {
    final st = _status(e);
    final runnable = e.runnable && (st == null || st.isEmpty) && widget.canRun;
    Widget section(String t) =>
        Padding(padding: const EdgeInsets.only(top: 14, bottom: 4), child: Text(t, style: Sc.caps(11)));
    Widget mono(String s, [Color c = Sc.body]) => Text(s,
        style: TextStyle(fontFamily: Sc.mono, fontFamilyFallback: Sc.monoFallback, fontSize: 12.5, color: c));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        Text(e.title, style: Sc.uiText(20, color: Sc.text, weight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(e.id, style: Sc.uiText(12.5, color: Sc.faint)),
        if (e.desc.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(e.desc, style: Sc.uiText(14)),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: runnable ? () => Navigator.pop(context, ExampleChoice(e, ExampleAction.run)) : null,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Run on device'),
          ),
          OutlinedButton.icon(
            onPressed: e.stages.isEmpty ? null : () => Navigator.pop(context, ExampleChoice(e, ExampleAction.simulate)),
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: const Text('Simulate'),
          ),
          OutlinedButton.icon(
            onPressed: e.primarySlot == null
                ? null
                : () => Navigator.pop(context, ExampleChoice(e, ExampleAction.open, e.primarySlot)),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Open'),
          ),
        ]),
        if (!widget.canRun)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Running needs the desktop app.', style: Sc.uiText(12, color: Sc.faint)),
          ),
        if (st != null && st.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 10), child: mono(st, Sc.red)),
        section('STAGES'),
        for (final slot in [0, 2, 1])
          if (e.stages[slot] case final rel?)
            Row(children: [
              SizedBox(width: 64, child: Text(stageLabels[slot], style: Sc.uiText(13, color: Sc.caption))),
              Expanded(child: mono(rel)),
              TextButton(
                onPressed: () => Navigator.pop(context, ExampleChoice(e, ExampleAction.open, slot)),
                child: Text('open', style: Sc.uiText(13, color: Sc.blue)),
              ),
            ]),
        for (final (slot, rel) in e.blobs)
          Row(children: [
            SizedBox(width: 64, child: Text('slot $slot', style: Sc.uiText(13, color: Sc.caption))),
            Expanded(child: mono('$rel  (C runner, prebuilt)')),
          ]),
        if (e.fast) Padding(padding: const EdgeInsets.only(top: 4), child: mono('--fast')),
        if (e.knobs.isNotEmpty) ...[
          section('KNOBS'),
          mono([for (final k in e.knobs.entries) 'k${k.key} = ${k.value}'].join('   ')),
        ],
        for (final (name, steps) in [('SETUP', e.setup), ('START', e.start), ('STOP', e.stop)])
          if (steps.isNotEmpty) ...[
            section(name),
            for (final s in steps) mono('$s'),
          ],
        if (e.kind == 'file') ...[
          section('RUN'),
          Text('No examples.json entry: Run uploads the stage only (no setup or start steps).',
              style: Sc.uiText(12.5, color: Sc.faint)),
        ],
      ],
    );
  }
}
