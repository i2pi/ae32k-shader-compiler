// Decodes the OSC the device sends back: plain messages and `#bundle`s, with i / f / s / b arguments.
import 'dart:convert';
import 'dart:typed_data';

class OscReply {
  final String address;
  final List<Object> args;
  const OscReply(this.address, this.args);
  @override
  String toString() => '$address $args';
}

List<OscReply> decodeOsc(Uint8List data) {
  final out = <OscReply>[];
  try {
    _decode(ByteData.sublistView(data), out);
  } catch (_) {
    // a malformed datagram is dropped
  }
  return out;
}

void _decode(ByteData b, List<OscReply> out) {
  var p = 0;
  String str() {
    final start = p;
    while (b.getUint8(p) != 0) {
      p++;
    }
    final s =
        utf8.decode(Uint8List.sublistView(b, start, p), allowMalformed: true);
    p = (p + 4) & ~3;
    return s;
  }

  final address = str();
  if (address == '#bundle') {
    p += 8; // time tag
    while (p + 4 <= b.lengthInBytes) {
      final n = b.getInt32(p);
      p += 4;
      _decode(ByteData.sublistView(b, p, p + n), out);
      p += n;
    }
    return;
  }
  final args = <Object>[];
  if (p < b.lengthInBytes) {
    final tags = str();
    for (final t in tags.runes.skip(1)) {
      switch (String.fromCharCode(t)) {
        case 'i':
          args.add(b.getInt32(p));
          p += 4;
        case 'f':
          args.add(b.getFloat32(p));
          p += 4;
        case 's':
          args.add(str());
        case 'b':
          final n = b.getInt32(p);
          p += 4;
          args.add(Uint8List.sublistView(b, p, p + n));
          p = (p + n + 3) & ~3;
        case 'T':
          args.add(true);
        case 'F':
          args.add(false);
        default:
          break;
      }
    }
  }
  out.add(OscReply(address, args));
}
