// The frame simulator's model of the resident (imcu_broker/hybrid/hyb_main.c), in pure Dart:
// runs the stages in the reference evaluator (bit-exact with the device's native code) and
// turns their outputs into what the hardware is given: the warp grid (stage_warp), the cells
// of the vertex stage (vt_build), and per line, the register values the cell rasteriser or the
// scan pattern writes (zo_eval arithmetic, line latching). How those registers change the
// picture is the renderer's business (sim_render.dart).
import 'dart:math';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';

/// `imcu scan start <lstep> <lines> ... <xn> ... <lphase>` without a vertex stage.
class ScanPattern {
  final int lstep, xn, lines, phase;
  const ScanPattern(this.lstep, this.xn, [this.lines = 1000, this.phase = 0]);
}

/// The warp grid: [nx] x [ny] points [step] px apart; [sx]/[sy] = the source position each
/// output grid point samples (px, already clamped as the resident does); [black] marks blocks
/// the MFC blanks (corners jumping by more than a block).
class WarpField {
  final int nx, ny, step;
  final List<double> sx, sy;
  final List<bool> black; // (nx-1) * (ny-1)
  const WarpField(this.nx, this.ny, this.step, this.sx, this.sy, this.black);
}

/// One vertex-stage point as a cell: top-left (x, y) px, [width] px (0: no right edge),
/// [height] lines, slopes in px per line, the scan stage's outputs for it.
class SimCell {
  final int index;
  final double x, y, width, height, dLeft, dRight;
  final bool parked;
  final List<int> params; // p0..p3
  final List<int> out; // the scan stage's 16 outputs (Q16)
  const SimCell(this.index, this.x, this.y, this.width, this.height, this.dLeft, this.dRight, this.parked,
      this.params, this.out);
}

/// A run of pixels on one line where every mapped register field has the same value.
class Span {
  final int x0, x1;
  final List<int> fields; // per map entry, the field value in effect
  const Span(this.x0, this.x1, this.fields);
}

/// One `@out` map entry as the simulator sees it.
class OutInfo {
  final String name, target, mode, granularity;
  final int reg, mask, shift, slot, base;
  final bool hold, pixel, modelled;
  String? range;
  OutInfo(this.name, this.target, this.mode, this.granularity, this.reg, this.mask, this.shift, this.slot, this.base,
      {required this.hold, required this.pixel, required this.modelled});
  int get fieldMax => mask >> shift;
}

class SimFrame {
  final int frame;
  final WarpField? warp;
  final List<SimCell> cells;
  final List<(double, double)> scanPoints; // pattern mode: where the stage ran (px)
  final List<List<Span>> rows; // per picture row, left to right
  final List<OutInfo> outputs;
  final int warpPoints, scanEvals, writes, walkEnd;
  const SimFrame(this.frame, this.warp, this.cells, this.scanPoints, this.rows, this.outputs, this.warpPoints,
      this.scanEvals, this.writes, this.walkEnd);
}

const _q1 = 65536;
const vtVofs = 44; // walk line = picture row + 44 (VT_VOFS)
const _spOps = 24; // edges per span (SP_OPS); a cell with a width costs 2
const _spRegs = 4; // map entries written in cell mode (SP_REGS)

/// Register names whose effect on the picture sim_render.dart models.
const modelledRegisters = {
  'in_swap', 'in_cbcr_swap', 'wmc_cbcr_swap', 'out0_cbcr_swap', 'mfc0_chroma_swap',
  'out0_csc_y0', 'out0_csc_y1', 'out0_csc_y2', 'out0_csc_g0', 'out0_csc_g1', 'out0_csc_g2',
  'out0_csc_b0', 'out0_csc_b1', 'out0_csc_b2', 'out0_csc_oy', 'out0_csc_ocb', 'out0_csc_ocr',
  'out0_dark', 'out0_tp_force_g', 'in_csc_c0', 'in_csc_c1', 'in_csc_c2', 'in_csc_c3', 'in_csc_oy', 'in_csc_og',
};

class SimEngine {
  final int w, h;
  final double fps;
  final bool fast;
  final int points;
  final ScanPattern pattern;
  final Program? _warp, _scan, _vert;
  final _stageErr = List<String?>.filled(3, null);
  final _mean = List<double>.filled(3, 0);
  final errors = <String>[];
  late final List<OutInfo> outputs;
  // register state carried across lines and frames, as the hardware keeps it
  late final List<int> _state;
  final _rng = Random(1);

  SimEngine({
    required this.w,
    required this.h,
    required this.fps,
    required this.fast,
    String? warp,
    String? scan,
    String? vertex,
    this.points = 96,
    this.pattern = const ScanPattern(8, 1),
  })  : _warp = _compile(warp, 0),
        _scan = _compile(scan, 1),
        _vert = _compile(vertex, 2) {
    for (final (s, src) in [(0, warp), (1, scan), (2, vertex)]) {
      if (src == null) continue;
      final a = analyzeStage(src, slot: s, fast: fast, samples: 12);
      final errs = a.diagnostics.where((d) => d.isError).toList();
      if (errs.isNotEmpty) {
        _stageErr[s] = errs.first.toString();
        errors.add('${['warp', 'scan', 'vertex'][s]}: ${errs.first}');
      }
      _mean[s] = a.meanCycles;
    }
    outputs = _outputs(scan);
    _state = [for (final o in outputs) o.base];
  }

  static Program? _compile(String? src, int slot) {
    if (src == null) return null;
    try {
      return parse(src);
    } catch (_) {
      return null;
    }
  }

  String? stageError(int slot) => _stageErr[slot];
  bool get cellMode => _vert != null;
  int get walkEnd => min(h, (pattern.lines - vtVofs) * h ~/ 1080);

  Map<String, int> _inputs(int frame, Map<String, int> knobs) => {
        't': (frame / fps * _q1).round(),
        'frame': frame * _q1,
        'w': 1920 * _q1,
        'h': 1080 * _q1,
        'heat': 0,
        'mvx': 960 * _q1,
        'mvy': 540 * _q1,
        'luma': 0,
        ...knobs,
      };

  SimFrame frame(int frame, Map<String, int> knobs) {
    final base = _inputs(frame, knobs);
    final warp = _warp == null ? null : _warpField(base);
    final cells = <SimCell>[];
    final pts = <(double, double)>[];
    var evals = 0;
    final List<List<Span>> rows;
    var writes = 0;
    if (_vert != null) {
      cells.addAll(_cells(base));
      evals = cells.length;
      (rows, writes) = _cellRows(cells);
    } else if (_scan != null) {
      (rows, writes, evals) = _patternRows(base, pts);
    } else {
      rows = const [];
    }
    if (outputs.isNotEmpty) _ranges(rows);
    return SimFrame(frame, warp, cells, pts, rows, outputs, warp == null ? 0 : warp.nx * warp.ny, evals, writes, walkEnd);
  }

  // ------------------------------------------------------------------ warp

  WarpField _warpField(Map<String, int> base) {
    final step = w <= 1920 ? 16 : 32; // block_h_size (mdinmfc.c)
    final nx = w ~/ step + 1, ny = h ~/ step + 1;
    final lim = step * 4.0; // +-4 blocks
    final sx = List<double>.filled(nx * ny, 0), sy = List<double>.filled(nx * ny, 0);
    final dx = List<double>.filled(nx * ny, 0), dy = List<double>.filled(nx * ny, 0);
    final inp = Map.of(base);
    for (var j = 0; j < ny; j++) {
      for (var i = 0; i < nx; i++) {
        final gx = i * step, gy = j * step;
        inp['x'] = gx * _q1;
        inp['y'] = gy * _q1;
        inp['u'] = gx * _q1 ~/ 1920;
        inp['v'] = gy * _q1 ~/ 1080;
        inp['rnd'] = _rng.nextInt(_q1);
        final o = evaluate(_warp!, inp, null, fast);
        final k = j * nx + i;
        dx[k] = (o[0] / _q1).clamp(-lim, lim);
        dy[k] = (o[1] / _q1).clamp(-lim, lim);
        sx[k] = max(0, gx + dx[k]);
        sy[k] = max(0, gy + dy[k]);
      }
    }
    // a block whose corners disagree by more than a 64 px block is blanked (approximate rule)
    final black = List<bool>.filled((nx - 1) * (ny - 1), false);
    for (var j = 0; j < ny - 1; j++) {
      for (var i = 0; i < nx - 1; i++) {
        final ks = [j * nx + i, j * nx + i + 1, (j + 1) * nx + i, (j + 1) * nx + i + 1];
        var lo = double.infinity, hi = -double.infinity, lo2 = double.infinity, hi2 = -double.infinity;
        for (final k in ks) {
          lo = min(lo, dx[k]);
          hi = max(hi, dx[k]);
          lo2 = min(lo2, dy[k]);
          hi2 = max(hi2, dy[k]);
        }
        black[j * (nx - 1) + i] = hi - lo > 64 || hi2 - lo2 > 64;
      }
    }
    return WarpField(nx, ny, step, sx, sy, black);
  }

  // ----------------------------------------------------------- cell mode

  List<SimCell> _cells(Map<String, int> base) {
    final out = <SimCell>[];
    final vin = Map.of(base);
    final sin = Map.of(base);
    final init = List<int>.filled(16, 0);
    for (final o in outputs) {
      if (o.mode == 'gain') init[o.slot] = _q1;
    }
    for (var i = 0; i < points; i++) {
      vin['x'] = i * _q1;
      vin['u'] = i * _q1 ~/ points;
      vin['y'] = 0;
      vin['v'] = 0;
      vin['rnd'] = _rng.nextInt(_q1);
      final v = evaluate(_vert!, vin, null, fast);
      final x = (v[0] >> 16).clamp(-2048, 4095), y = (v[1] >> 16).clamp(-1024, 1124);
      final params = [v[2], v[3], v[4], v[5]];
      final slope = 128.0 * _q1;
      final dl = v[6].clamp(-slope, slope) / _q1, dr = (v[6] + v[7]).clamp(-slope, slope) / _q1;
      var so = List<int>.filled(16, 0);
      if (_scan != null) {
        sin['x'] = x * _q1;
        sin['y'] = y * _q1;
        // unsigned divides on the device: a negative position gives a large u / v
        sin['u'] = ((x * _q1) & 0xffffffff) ~/ 1920;
        sin['v'] = ((y * _q1) & 0xffffffff) ~/ 1080;
        for (var k = 0; k < 4; k++) {
          sin['p$k'] = params[k];
        }
        sin['rnd'] = _rng.nextInt(_q1);
        so = evaluate(_scan, sin, init, fast);
      }
      final parked = y + vtVofs >= pattern.lines;
      out.add(SimCell(i, x.toDouble(), y.toDouble(), (v[4] >> 16).toDouble(), max(1, v[5] >> 16).toDouble(), dl, dr,
          parked, params, so));
    }
    return out;
  }

  /// zo_eval: the field value an output gives for map entry [o].
  int _field(OutInfo o, int out) {
    final fm = o.fieldMax;
    var bf = o.base;
    if (o.mask == 0xFFFF) bf = bf.toSigned(16);
    int v;
    switch (o.mode) {
      case 'gain':
        final g = out.clamp(0, 8 * _q1);
        v = (bf * (g >> 4)) >> 12;
      case 'add':
        v = bf + (out >> 16);
      case 'unit':
        v = (out.clamp(0, 65535) * (fm + 1)) >> 16;
      case 'strobe':
        return o.base;
      default:
        v = out >> 16;
    }
    return o.mask == 0xFFFF ? v & 0xFFFF : v.clamp(0, fm);
  }

  (List<List<Span>>, int) _cellRows(List<SimCell> cells) {
    final n = min(outputs.length, _spRegs);
    final rows = List<List<Span>>.generate(h, (_) => const []);
    final end = walkEnd;
    var writes = 0;
    final rowOps = List.generate(end, (_) => <(double, bool, int)>[]); // x, isSet, cell
    for (final c in cells) {
      if (c.parked) continue;
      for (var k = 0; k < c.height; k++) {
        final row = c.y.toInt() + k;
        if (row < 0) continue;
        if (row >= end) break;
        final xl = (c.x + c.dLeft * k).clamp(0.0, w.toDouble());
        rowOps[row].add((xl, true, c.index));
        if (c.width > 0) {
          final xr = max(xl + 1, (c.x + c.width + c.dRight * k).clamp(0.0, w.toDouble())); // at least 1 tick
          rowOps[row].add((xr, false, c.index));
        }
      }
    }
    final valueOf = <int, List<int>>{}; // cell -> field values
    List<int> fieldsOf(SimCell c, int line) => valueOf.putIfAbsent(c.index, () {
          return [
            for (var e = 0; e < outputs.length; e++)
              e < n ? _field(outputs[e], c.out[outputs[e].slot]) : outputs[e].base
          ];
        });
    // per-line slope: out[src+8] adds (line - top) * slope inside the field
    List<int> withSlope(SimCell c, int row) {
      final f = List.of(fieldsOf(c, row));
      for (var e = 0; e < n; e++) {
        final o = outputs[e];
        if (o.slot < 8) {
          final s = c.out[o.slot + 8];
          if (s != 0) f[e] = (f[e] + (((row - c.y.toInt()) * s) >> 16)) & o.fieldMax;
        }
      }
      return f;
    }

    final byIndex = {for (final c in cells) c.index: c};
    var wasEmpty = true;
    for (var row = 0; row < h; row++) {
      final ops = row < end ? rowOps[row] : const <(double, bool, int)>[];
      final latched = [for (var e = 0; e < outputs.length; e++) _state[e]];
      final spans = <Span>[];
      var x = 0;
      if (ops.isEmpty) {
        if (!wasEmpty) {
          // hold registers return to their base on the first line of an empty span
          for (var e = 0; e < n; e++) {
            if (outputs[e].hold) _state[e] = outputs[e].base;
          }
        }
        wasEmpty = true;
      } else {
        wasEmpty = false;
        ops.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : (a.$2 ? 1 : 0) - (b.$2 ? 1 : 0));
        // SP_OPS: extra cells are dropped
        final kept = <(double, bool, int)>[];
        var cost = 0;
        final dropped = <int>{};
        for (final op in ops) {
          if (dropped.contains(op.$3)) continue;
          final c = byIndex[op.$3]!;
          final need = op.$2 ? (c.width > 0 ? 2 : 1) : 0;
          if (op.$2 && cost + need > _spOps) {
            dropped.add(op.$3);
            continue;
          }
          cost += need;
          kept.add(op);
        }
        List<int>? lead; // line-latched entries take the leftmost op's value
        for (final op in kept) {
          final c = byIndex[op.$3]!;
          final vals = withSlope(c, row);
          lead ??= vals;
          final xi = op.$1.round();
          if (xi > x) {
            spans.add(Span(x, xi, List.of(_state)));
            x = xi;
          }
          for (var e = 0; e < n; e++) {
            final o = outputs[e];
            final nv = o.hold ? lead[e] : (op.$2 ? vals[e] : o.base);
            if (_state[e] != nv) writes++;
            _state[e] = nv;
          }
        }
      }
      if (x < w) spans.add(Span(x, w, List.of(_state)));
      rows[row] = _latch(spans, latched);
    }
    return (rows, writes);
  }

  /// Line-granularity registers are sampled once per line: on this row they show the value at
  /// the end of the previous row ([latched]); pixel and partial ones change where written.
  List<Span> _latch(List<Span> spans, List<int> latched) {
    final out = <Span>[];
    for (final s in spans) {
      final f = [for (var e = 0; e < outputs.length; e++) outputs[e].pixel ? s.fields[e] : latched[e]];
      if (out.isNotEmpty && _same(out.last.fields, f)) {
        out[out.length - 1] = Span(out.last.x0, s.x1, f);
      } else {
        out.add(Span(s.x0, s.x1, f));
      }
    }
    return out;
  }

  static bool _same(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // -------------------------------------------------------- pattern mode

  (List<List<Span>>, int, int) _patternRows(Map<String, int> base, List<(double, double)> pts) {
    final rows = List<List<Span>>.generate(h, (_) => const []);
    final init = List<int>.filled(16, 0);
    for (final o in outputs) {
      if (o.mode == 'gain') init[o.slot] = _q1;
    }
    final inp = Map.of(base);
    // the points that run on each picture row (walk line = row + 44)
    final at = <int, List<int>>{};
    for (var line = pattern.phase; line < pattern.lines; line += max(1, pattern.lstep)) {
      final row = (line - vtVofs) * h ~/ 1080;
      if (row < 0 || row >= h) continue;
      at[row] = [for (var i = 0; i < pattern.xn; i++) i * 1920 ~/ pattern.xn];
      for (final x in at[row]!) {
        pts.add((x * w / 1920, row.toDouble()));
      }
      // the device's in.y is the raster line, not the picture row
      at[row] = [...at[row]!, line];
    }
    var writes = 0, evals = 0;
    for (var row = 0; row < h; row++) {
      final latched = List.of(_state);
      final spans = <Span>[];
      var x = 0;
      final xs = at[row];
      if (xs != null) {
        final line = xs.last;
        for (var i = 0; i < xs.length - 1; i++) {
          inp['x'] = xs[i] * _q1;
          inp['y'] = line * _q1;
          inp['u'] = i * _q1 ~/ pattern.xn;
          inp['v'] = line * _q1 ~/ 1080;
          inp['rnd'] = _rng.nextInt(_q1);
          final o = evaluate(_scan!, inp, init, fast);
          evals++;
          final xi = xs[i] * w ~/ 1920;
          if (xi > x) {
            spans.add(Span(x, xi, List.of(_state)));
            x = xi;
          }
          for (var e = 0; e < outputs.length; e++) {
            final nv = _field(outputs[e], o[outputs[e].slot]);
            if (nv != _state[e]) writes++;
            _state[e] = nv;
          }
        }
      }
      if (x < w) spans.add(Span(x, w, List.of(_state)));
      rows[row] = _latch(spans, latched);
    }
    return (rows, writes, evals);
  }

  // -------------------------------------------------------------- outputs

  static final _outLine = RegExp(r'^\s*@out\s+(\w+)\s+(.*?)\s*;?\s*(//.*)?$');

  List<OutInfo> _outputs(String? src) {
    final p = _scan;
    if (src == null || p == null) return const [];
    final out = <OutInfo>[];
    var e = 0;
    for (final line in src.split('\n')) {
      final m = _outLine.firstMatch(line);
      if (m == null) continue;
      final f = m.group(2)!.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      if (f.isEmpty || e >= p.outMap.length) continue;
      final entry = p.outMap[e++];
      Register? r;
      try {
        r = f.length >= 4 ? null : lookupRegister(f[0]); // a registers.inc row or a send<N>.pip<M> port
      } on FormatException {
        r = null;
      }
      final mode = switch (entry.mode & 15) { 0 => 'raw', 1 => 'gain', 2 => 'add', 3 => 'unit', _ => 'strobe' };
      final gran = r?.granularity ?? (entry.mode & 0x10 != 0 ? 'line' : 'pixel');
      final fm = entry.mask == 0 ? 0 : entry.mask >> entry.shift;
      // the field as found when the map was set is unknown here: a nominal base that leaves
      // room both ways (gain: 1.0 = 0x1000; add: mid-range; raw: 0)
      final base = switch (mode) {
        'gain' => entry.mask == 0xFFFF ? 0x1000 : fm ~/ 2,
        'add' => entry.mask == 0xFFFF ? 0 : fm ~/ 2,
        _ => 0,
      };
      out.add(OutInfo(m.group(1)!, r?.name ?? f.take(3).join(' '), mode, gran, entry.reg, entry.mask, entry.shift,
          entry.slot, base,
          hold: entry.mode & 0x10 != 0,
          pixel: gran == 'pixel' || gran == 'partial',
          modelled: r != null && modelledRegisters.contains(r.name)));
    }
    return out;
  }

  void _ranges(List<List<Span>> rows) {
    for (var e = 0; e < outputs.length; e++) {
      var lo = 1 << 30, hi = -(1 << 30);
      for (final r in rows) {
        for (final s in r) {
          lo = min(lo, s.fields[e]);
          hi = max(hi, s.fields[e]);
        }
      }
      if (lo <= hi) outputs[e].range = lo == hi ? 'field = $lo' : 'field $lo..$hi';
    }
  }

  // --------------------------------------------------------------- budget

  static const _hz = 99.75e6, _line = 3694.0;

  /// (label, value, fits) rows for the stats panel.
  List<(String, String, bool)> budget(SimFrame f) {
    final out = <(String, String, bool)>[];
    if (_warp != null) {
      final c = _mean[0] * f.warpPoints;
      out.add(('warp', '${_mean[0].toStringAsFixed(0)} cyc × ${f.warpPoints} = ${(c / _hz * 1000).toStringAsFixed(1)} ms',
          c / _hz < 1 / fps));
    }
    if (_vert != null) {
      final c = (_mean[2] + _mean[1]) * points;
      final lines = c / _line, room = (1125 - pattern.lines).toDouble();
      out.add(('build', '${c.toStringAsFixed(0)} cyc = ${lines.toStringAsFixed(0)} of ${room.toStringAsFixed(0)} lines',
          lines < room));
      out.add(('vertex', '${_mean[2].toStringAsFixed(0)} cyc × $points', true));
      if (_scan != null) out.add(('scan', '${_mean[1].toStringAsFixed(0)} cyc × $points', true));
    } else if (_scan != null) {
      final per = _mean[1] * pattern.xn, room = _line * pattern.lstep;
      out.add(('scan', '${_mean[1].toStringAsFixed(0)} cyc × ${pattern.xn} per line (of ${room.toStringAsFixed(0)})',
          per < room));
    }
    return out;
  }
}
