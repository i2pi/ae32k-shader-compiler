// Simulated input for the frame simulator: procedural test cards (every pixel a sample: smooth
// colour and luma ramps, a 64 px grid that shows the warp, fine noise), moving objects so motion
// is visible, or an image file. One ui.Image per frame.
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

enum SourceKind {
  card('Test card'),
  bars('Colour bars + ramps'),
  motion('Moving card'),
  image('Image file');

  final String label;
  const SourceKind(this.label);
}

class SimSource {
  final int w, h;
  final SourceKind kind;
  final ui.Image? file; // for SourceKind.image
  ui.Image? _base;
  SimSource(this.w, this.h, this.kind, [this.file]);

  Future<void> prepare() async {
    if (kind == SourceKind.image) return;
    final px = kind == SourceKind.bars ? _bars(w, h) : _card(w, h);
    final buf = await ui.ImmutableBuffer.fromUint8List(px);
    final desc = ui.ImageDescriptor.raw(buf, width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    _base = (await codec.getNextFrame()).image;
    desc.dispose();
    buf.dispose();
  }

  /// The source picture at [t] seconds.
  ui.Image frame(double t) {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    final full = ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    final p = ui.Paint()..filterQuality = ui.FilterQuality.medium;
    switch (kind) {
      case SourceKind.image:
        final f = file;
        if (f == null) {
          c.drawRect(full, ui.Paint()..color = const ui.Color(0xFF202020));
        } else {
          // cover the frame, keeping the aspect
          final s = max(w / f.width, h / f.height);
          final sw = w / s, sh = h / s;
          c.drawImageRect(f, ui.Rect.fromLTWH((f.width - sw) / 2, (f.height - sh) / 2, sw, sh), full, p);
        }
      case SourceKind.motion:
        // the card pans slowly (wrapping), objects move over it
        final ox = (t * 48) % w, oy = (sin(t * 0.37) * 0.5 + 0.5) * 40;
        c.save();
        c.translate(-ox, -oy);
        for (final dx in [0.0, w.toDouble()]) {
          c.drawImage(_base!, ui.Offset(dx, 0), p);
          c.drawImage(_base!, ui.Offset(dx, h.toDouble()), p);
        }
        c.restore();
        _objects(c, t, 1.0);
      default:
        c.drawImage(_base!, ui.Offset.zero, p);
        if (kind == SourceKind.card) _objects(c, t, 0.6);
    }
    final pic = rec.endRecording();
    final img = pic.toImageSync(w, h);
    pic.dispose();
    return img;
  }

  // a disc on a Lissajous path and a rotating bar: something that moves
  void _objects(ui.Canvas c, double t, double speed) {
    final s = h / 1080;
    final cx = w * (0.5 + 0.32 * sin(t * 0.9 * speed)), cy = h * (0.5 + 0.3 * sin(t * 1.3 * speed + 1));
    c.drawCircle(ui.Offset(cx, cy), 70 * s, ui.Paint()..color = const ui.Color(0xFFF2F2F2));
    c.drawCircle(ui.Offset(cx, cy), 46 * s, ui.Paint()..color = const ui.Color(0xFFD03030));
    c.save();
    c.translate(w * 0.78, h * 0.28);
    c.rotate(t * 0.8 * speed);
    c.drawRect(ui.Rect.fromCenter(center: ui.Offset.zero, width: 360 * s, height: 26 * s),
        ui.Paint()..color = const ui.Color(0xFF30C0F0));
    c.restore();
  }
}

/// Hue across, luma down, a 64 px grid (the warp's block size) and low noise.
Uint8List _card(int w, int h) {
  final px = Uint8List(w * h * 4);
  final rng = Random(5);
  final grid = max(8, (64 * h / 1080).round());
  for (var y = 0; y < h; y++) {
    final v = y / (h - 1);
    for (var x = 0; x < w; x++) {
      final u = x / (w - 1);
      final (r, g, b) = _hsv(u * 360, 0.75 - 0.35 * v, 0.95 - 0.7 * v);
      var k = 1.0;
      if (x % grid == 0 || y % grid == 0) k = 0.35;
      if ((x % (grid * 4) == 0 || y % (grid * 4) == 0) && k < 1) k = 1.6;
      final n = (rng.nextDouble() - 0.5) * 10;
      final i = (y * w + x) * 4;
      px[i] = (r * 255 * k + n).round().clamp(0, 255);
      px[i + 1] = (g * 255 * k + n).round().clamp(0, 255);
      px[i + 2] = (b * 255 * k + n).round().clamp(0, 255);
      px[i + 3] = 255;
    }
  }
  return px;
}

/// 75% colour bars on the top half; below, R, G, B and grey ramps.
Uint8List _bars(int w, int h) {
  const bars = [
    [191, 191, 191], [191, 191, 0], [0, 191, 191], [0, 191, 0], [191, 0, 191], [191, 0, 0], [0, 0, 191],
  ];
  final px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      List<int> c;
      if (y < h ~/ 2) {
        c = bars[min(6, x * 7 ~/ w)];
      } else {
        final band = min(3, (y - h ~/ 2) * 4 ~/ (h - h ~/ 2));
        final l = (x * 255 / (w - 1)).round();
        c = [band == 0 || band == 3 ? l : 0, band == 1 || band == 3 ? l : 0, band == 2 || band == 3 ? l : 0];
      }
      px[i] = c[0];
      px[i + 1] = c[1];
      px[i + 2] = c[2];
      px[i + 3] = 255;
    }
  }
  return px;
}

(double, double, double) _hsv(double hdeg, double s, double v) {
  final c = v * s, hh = (hdeg % 360) / 60, x = c * (1 - (hh % 2 - 1).abs()), m = v - c;
  final (r, g, b) = switch (hh.floor()) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  return (r + m, g + m, b + m);
}
