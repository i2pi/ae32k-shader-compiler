// Draws a simulated frame: register effects on the input side (in_*, wmc_*), the warp (the
// grid as a textured mesh, as the MFC interpolates it), register effects on the output side
// (out0_*), then the overlays. The register models are approximate (colour matrices in
// BT.709 Y'CbCr): enough to see where and how strongly a stage acts, not a colour reference.
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'sim_engine.dart';

class SimOverlays {
  bool warpGrid = false, cells = true, points = true, effects = true, trace = true, bypass = false;
}

/// The finished picture for [f] from [src] (no overlays).
ui.Image composeFrame(ui.Image src, SimFrame f, SimOverlays ov, int w, int h) {
  if (ov.bypass) return src.clone();
  var img = src.clone();
  final outs = f.outputs;
  bool input(OutInfo o) => o.target.startsWith('in_') || o.target.startsWith('wmc_');
  if (ov.effects && f.rows.isNotEmpty && outs.any((o) => o.modelled && input(o))) {
    img = _replace(img, _effects(img, f, w, h, (o) => o.modelled && input(o)));
  }
  final wf = f.warp;
  if (wf != null) img = _replace(img, _warp(img, wf, w, h));
  if (ov.effects && f.rows.isNotEmpty && outs.any((o) => o.modelled && !input(o))) {
    img = _replace(img, _effects(img, f, w, h, (o) => o.modelled && !input(o)));
  }
  return img;
}

ui.Image _replace(ui.Image old, ui.Image next) {
  old.dispose();
  return next;
}

ui.Image _warp(ui.Image src, WarpField wf, int w, int h) {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFF000000));
  final pos = <double>[], tex = <double>[];
  final nx = wf.nx, ny = wf.ny, st = wf.step.toDouble();
  void v(int i, int j) {
    final k = j * nx + i;
    pos..add(i * st)..add(j * st);
    tex..add(wf.sx[k].clamp(0, src.width - 1.0))..add(wf.sy[k].clamp(0, src.height - 1.0));
  }

  for (var j = 0; j < ny - 1; j++) {
    for (var i = 0; i < nx - 1; i++) {
      if (wf.black[j * (nx - 1) + i]) continue;
      v(i, j);
      v(i + 1, j);
      v(i, j + 1);
      v(i + 1, j);
      v(i + 1, j + 1);
      v(i, j + 1);
    }
  }
  if (pos.isNotEmpty) {
    final verts = ui.Vertices.raw(ui.VertexMode.triangles, Float32List.fromList(pos),
        textureCoordinates: Float32List.fromList(tex));
    final shader = ui.ImageShader(src, ui.TileMode.clamp, ui.TileMode.clamp, Matrix4.identity().storage,
        filterQuality: ui.FilterQuality.low);
    c.drawVertices(verts, ui.BlendMode.srcOver, ui.Paint()..shader = shader);
  }
  final pic = rec.endRecording();
  final out = pic.toImageSync(w, h);
  pic.dispose();
  return out;
}

/// Redraws the runs of [src] where the selected registers differ from their base, each run
/// through its colour matrix; rows with identical runs are drawn as one band.
ui.Image _effects(ui.Image src, SimFrame f, int w, int h, bool Function(OutInfo) pick) {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawImage(src, ui.Offset.zero, ui.Paint());
  final sel = [for (var e = 0; e < f.outputs.length; e++) if (pick(f.outputs[e])) e];
  final cache = <String, List<double>?>{};
  List<double>? matrixFor(List<int> fields) {
    final key = [for (final e in sel) fields[e]].join(',');
    return cache.putIfAbsent(key, () => _matrix(f.outputs, fields, sel));
  }

  String rowKey(List<Span> spans) => [
        for (final s in spans)
          if (matrixFor(s.fields) != null) '${s.x0}-${s.x1}:${[for (final e in sel) s.fields[e]].join(',')}'
      ].join('|');
  var y0 = 0;
  while (y0 < f.rows.length) {
    final k = rowKey(f.rows[y0]);
    var y1 = y0 + 1;
    while (y1 < f.rows.length && rowKey(f.rows[y1]) == k) {
      y1++;
    }
    if (k.isNotEmpty) {
      for (final s in f.rows[y0]) {
        final m = matrixFor(s.fields);
        if (m == null) continue;
        final r = ui.Rect.fromLTRB(s.x0.toDouble(), y0.toDouble(), s.x1.toDouble(), y1.toDouble());
        c.drawImageRect(src, r, r, ui.Paint()..colorFilter = ui.ColorFilter.matrix(m));
      }
    }
    y0 = y1;
  }
  final pic = rec.endRecording();
  final out = pic.toImageSync(w, h);
  pic.dispose();
  return out;
}

// ------------------------------------------------------------ colour model

// BT.709: rgb -> (Y, Cb, Cr) with Cb, Cr centred on 0, all in 0..1 units
const _toYcc = [
  [0.2126, 0.7152, 0.0722],
  [-0.1146, -0.3854, 0.5],
  [0.5, -0.4542, -0.0458],
];
const _toRgb = [
  [1.0, 0.0, 1.5748],
  [1.0, -0.1873, -0.4681],
  [1.0, 1.8556, 0.0],
];

/// An affine map on (r, g, b) in 0..1: 3 x 4 (last column = offset).
typedef _Aff = List<List<double>>;

_Aff _id() => [
      [1.0, 0.0, 0.0, 0.0],
      [0.0, 1.0, 0.0, 0.0],
      [0.0, 0.0, 1.0, 0.0],
    ];

_Aff _of(List<List<double>> m, [List<double> off = const [0, 0, 0]]) => [
      for (var r = 0; r < 3; r++) [...m[r], off[r]]
    ];

/// a after b
_Aff _then(_Aff a, _Aff b) => [
      for (var r = 0; r < 3; r++)
        [
          for (var c = 0; c < 3; c++) a[r][0] * b[0][c] + a[r][1] * b[1][c] + a[r][2] * b[2][c],
          a[r][0] * b[0][3] + a[r][1] * b[1][3] + a[r][2] * b[2][3] + a[r][3],
        ]
    ];

/// The effect of the selected entries' field values, in rgb, or null when nothing changes.
List<double>? _matrix(List<OutInfo> outs, List<int> fields, List<int> sel) {
  // values per register name (the last entry naming a register wins, as the last write would)
  final v = <String, (OutInfo, int)>{};
  for (final e in sel) {
    v[outs[e].target] = (outs[e], fields[e]);
  }
  double gain(String n) {
    final x = v[n];
    if (x == null || x.$1.base == 0) return 1;
    return x.$2 / x.$1.base;
  }

  double delta(String n, double full) {
    final x = v[n];
    if (x == null) return 0;
    var d = x.$2 - x.$1.base;
    if (x.$1.mask == 0xFFFF) d = d.toSigned(16);
    return d / full;
  }

  int raw(String n) => v[n]?.$2 ?? 0;

  var changed = false;
  // input side, in code space (Y, Cb + 0.5, Cr + 0.5)
  var ycc = _of(_toYcc);
  final inG = [gain('in_csc_c0'), gain('in_csc_c1'), gain('in_csc_c2'), gain('in_csc_c3')];
  final inOy = delta('in_csc_oy', 1024), inOg = delta('in_csc_og', 1024);
  if (inG.any((g) => g != 1) || inOy != 0 || inOg != 0) {
    changed = true;
    final cg = (inG[1] + inG[2] + inG[3]) / 3;
    ycc = _then(_of([
      [inG[0], 0, 0],
      [0, cg, 0],
      [0, 0, cg],
    ], [inOy + inOg * 0.7, 0, 0]), ycc);
  }
  final sw = raw('in_swap') & 7;
  final chroma = (raw('in_cbcr_swap') | raw('wmc_cbcr_swap') | raw('out0_cbcr_swap') | raw('mfc0_chroma_swap')) & 1;
  if (sw != 0 || chroma != 0) {
    changed = true;
    // code space: shift chroma to 0..1, permute, shift back
    final toCode = _of(_id().map((r) => r.sublist(0, 3)).toList(), [0, 0.5, 0.5]);
    final fromCode = _of(_id().map((r) => r.sublist(0, 3)).toList(), [0, -0.5, -0.5]);
    final perm = switch (sw & 3) {
      1 => [1, 0, 2],
      2 => [2, 1, 0],
      3 => [0, 2, 1],
      _ => [0, 1, 2],
    };
    var p = [
      for (var r = 0; r < 3; r++) [for (var c = 0; c < 3; c++) perm[r] == c ? 1.0 : 0.0]
    ];
    if (chroma != 0) p = [p[0], p[2], p[1]];
    var m = _then(_of(p), toCode);
    if (sw & 4 != 0) m = _then(_of([[-1, 0, 0], [0, -1, 0], [0, 0, -1]], [1, 1, 1]), m); // msb<>lsb, approximated
    ycc = _then(fromCode, _then(m, ycc));
  }
  // output CSC: rows Y/G/B taken as the R/G/B outputs (the examples' reading), columns Y, Cb, Cr
  final rows = ['y', 'g', 'b'];
  final cm = [for (final r in _toRgb) List.of(r)];
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 3; c++) {
      final g = gain('out0_csc_${rows[r]}$c');
      if (g != 1) {
        changed = true;
        cm[r][c] *= g;
      }
    }
  }
  final oy = delta('out0_csc_oy', 4096), ocb = delta('out0_csc_ocb', 4096), ocr = delta('out0_csc_ocr', 4096);
  if (oy != 0 || ocb != 0 || ocr != 0) {
    changed = true;
    ycc = _then(_of(_id().map((r) => r.sublist(0, 3)).toList(), [oy, ocb, ocr]), ycc);
  }
  var rgb = _then(_of(cm), ycc);
  if (raw('out0_dark') != 0) {
    changed = true;
    rgb = _of([[0, 0, 0], [0, 0, 0], [0, 0, 0]]);
  }
  final tp = raw('out0_tp_force_g');
  if (tp & 0x1000 != 0) {
    changed = true;
    rgb[1] = [0, 0, 0, (tp & 0xFFF) / 4095];
  }
  if (!changed) return null;
  return [
    for (var r = 0; r < 3; r++) ...[rgb[r][0], rgb[r][1], rgb[r][2], 0, rgb[r][3] * 255],
    0, 0, 0, 1, 0,
  ];
}

// ---------------------------------------------------------------- painter

class SimPainter extends CustomPainter {
  final ui.Image image;
  final SimFrame frame;
  final SimOverlays ov;
  final int w, h;
  SimPainter(this.image, this.frame, this.ov, this.w, this.h);

  static const _traceHues = [0.0, 120.0, 220.0, 45.0, 290.0, 170.0, 330.0, 90.0];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / w;
    canvas.save();
    canvas.scale(s);
    canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    final f = frame;
    if (ov.trace && !ov.bypass) _trace(canvas);
    final wf = f.warp;
    if (ov.warpGrid && wf != null) {
      final p = Paint()
        ..color = const Color(0x8000E0FF)
        ..strokeWidth = 1 / s;
      final every = max(1, (4 * 16) ~/ wf.step); // one line per 64 px
      for (var j = 0; j < wf.ny; j += every) {
        for (var i = 0; i < wf.nx - 1; i++) {
          final k = j * wf.nx + i;
          canvas.drawLine(Offset(wf.sx[k], wf.sy[k]), Offset(wf.sx[k + 1], wf.sy[k + 1]), p);
        }
      }
      for (var i = 0; i < wf.nx; i += every) {
        for (var j = 0; j < wf.ny - 1; j++) {
          final k = j * wf.nx + i;
          canvas.drawLine(Offset(wf.sx[k], wf.sy[k]), Offset(wf.sx[k + wf.nx], wf.sy[k + wf.nx]), p);
        }
      }
    }
    if (ov.cells) {
      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / s
        ..color = const Color(0xCCFFF176);
      final dot = Paint()..color = const Color(0xFFFFF176);
      for (final c in f.cells) {
        if (c.parked) continue;
        final hgt = c.height;
        if (c.width > 0) {
          final path = Path()
            ..moveTo(c.x, c.y)
            ..lineTo(c.x + c.width, c.y)
            ..lineTo(c.x + c.width + c.dRight * hgt, c.y + hgt)
            ..lineTo(c.x + c.dLeft * hgt, c.y + hgt)
            ..close();
          canvas.drawPath(path, edge);
        } else {
          canvas.drawLine(Offset(c.x, c.y), Offset(c.x + c.dLeft * hgt, c.y + hgt), edge);
        }
        canvas.drawCircle(Offset(c.x, c.y), 3 / s, dot);
      }
      if (f.cells.isNotEmpty) {
        // the walk ends here: shapes below are not drawn on the device
        final y = f.walkEnd.toDouble();
        canvas.drawLine(Offset(0, y), Offset(w.toDouble(), y),
            Paint()
              ..color = const Color(0x80FF6B6B)
              ..strokeWidth = 1 / s);
      }
    }
    if (ov.points) {
      final p = Paint()..color = const Color(0xFF6A9ACA);
      for (final (x, y) in f.scanPoints) {
        canvas.drawCircle(Offset(x, y), 2 / s, p);
      }
    }
    canvas.restore();
  }

  /// Outputs without a picture model: a tint whose hue names the output and whose strength is
  /// the field value within its range on this frame.
  void _trace(Canvas canvas) {
    final f = frame;
    final idx = [for (var e = 0; e < f.outputs.length; e++) if (!f.outputs[e].modelled && f.outputs[e].mode != 'strobe') e];
    if (idx.isEmpty || f.rows.isEmpty) return;
    for (final (n, e) in idx.indexed) {
      var lo = 1 << 30, hi = -(1 << 30);
      for (final r in f.rows) {
        for (final sp in r) {
          lo = min(lo, sp.fields[e]);
          hi = max(hi, sp.fields[e]);
        }
      }
      if (hi <= lo) continue;
      final hue = _traceHues[n % _traceHues.length];
      for (var y = 0; y < f.rows.length; y++) {
        for (final sp in f.rows[y]) {
          final a = (sp.fields[e] - lo) / (hi - lo);
          if (a <= 0.02) continue;
          canvas.drawRect(Rect.fromLTRB(sp.x0.toDouble(), y.toDouble(), sp.x1.toDouble(), y + 1.0),
              Paint()..color = HSVColor.fromAHSV(0.45 * a, hue, 0.9, 1).toColor());
        }
      }
    }
  }

  @override
  bool shouldRepaint(SimPainter old) => true;
}
