// OSC packets for uploading a stage, byte-for-byte as tools/imcu/shader.py sends them
// (test/osc_test.dart pins them to shader.py's output). Pure Dart: the socket side is in
// upload.dart, so the app can build packets on any platform.
import 'dart:convert';
import 'dart:typed_data';

import 'lang/ast.dart';

/// Where each slot's parts go (shader.py SLOT_PATH).
const slotPath = {0: '/send/1/shader/part', 1: '/send/1/shader/scanpart', 2: '/send/1/shader/vertpart'};

/// The device drops UDP packets much larger than this; parts are 1 KB of blob each.
const partBytes = 1024;

List<int> _pad(List<int> b) => [...b, ...List.filled(-b.length % 4 & 3, 0)];

List<int> _str(String s) => _pad([...utf8.encode(s), 0]);

/// The OSC types that carry no argument bytes (true, false, nil).
const oscNoArgTypes = 'TFN';

/// One OSC message; [args] are int (i), double (f), String (s) or `List<int>` (b), per [types].
/// T, F and N take no argument.
Uint8List oscMessage(String address, String types, List<Object> args) {
  final out = <int>[..._str(address), ..._str(',$types')];
  var n = 0;
  for (final t in types.split('')) {
    if (oscNoArgTypes.contains(t)) continue;
    final a = args[n++];
    final bd = ByteData(4);
    switch (t) {
      case 'i':
        bd.setInt32(0, a as int);
        out.addAll(bd.buffer.asUint8List());
      case 'f':
        bd.setFloat32(0, (a as num).toDouble());
        out.addAll(bd.buffer.asUint8List());
      case 's':
        out.addAll(_str(a as String));
      case 'b':
        final b = a as List<int>;
        bd.setInt32(0, b.length);
        out
          ..addAll(bd.buffer.asUint8List())
          ..addAll(_pad(b));
      default:
        throw ArgumentError('OSC type $t');
    }
  }
  return Uint8List.fromList(out);
}

/// The upload of [blob] to [slot]: `iib` (offset, total length, part) per 1 KB.
/// The device arms len/4 words, so a blob that is not a multiple of 4 bytes would lose
/// its tail (a 138-byte blob lost its final `jplr` and hung the CPU, 2026-10-11).
List<Uint8List> stageParts(List<int> blob, int slot) => blob.length % 4 != 0
    ? throw ArgumentError('stage blob is ${blob.length} bytes; the device needs a multiple of 4')
    : [
      for (var off = 0; off < blob.length; off += partBytes)
        oscMessage(slotPath[slot]!, 'iib', [off, blob.length, blob.sublist(off, (off + partBytes).clamp(0, blob.length))]),
    ];

Uint8List knobMessage(int k, double value) => oscMessage('/send/1/shader/k/$k', 'f', [value]);

/// The scan stage's `@out` map (shader.py outmap_blob): count, then 5 u16 per entry.
Uint8List scanMapMessage(List<OutMapEntry> entries) {
  final b = ByteData(2 + 10 * entries.length);
  b.setUint16(0, entries.length, Endian.little);
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    for (final (k, v) in [(0, e.reg), (1, e.mask), (2, e.shift), (3, e.mode), (4, e.slot)]) {
      b.setUint16(2 + 10 * i + 2 * k, v, Endian.little);
    }
  }
  return oscMessage('/send/1/shader/scanmap', 'b', [b.buffer.asUint8List()]);
}
