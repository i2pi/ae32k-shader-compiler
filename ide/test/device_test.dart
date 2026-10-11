// The upload protocol against a fake SCION on localhost that answers like the firmware
// (scion_firmware imcu_link.c sh_part / handle_shader_scanmap): /ack for /sync and /ack, each
// part acknowledged with the bytes received so far, the last one with the words armed.
import 'dart:io';
import 'dart:typed_data';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_ide/device_io.dart';
import 'package:shader_ide/osc_decode.dart';
import 'package:shader_ide/templates.dart';

class FakeScion {
  late RawDatagramSocket sock;
  final blob = BytesBuilder();
  int total = 0;
  List<int>? map;
  final knobs = <int, double>{};
  bool refuse = false;

  Future<int> start() async {
    sock = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    sock.listen((ev) {
      if (ev != RawSocketEvent.read) return;
      final d = sock.receive();
      if (d == null) return;
      for (final m in decodeOsc(d.data)) {
        void reply(String a, [int? v]) =>
            sock.send(oscMessage(a, v == null ? '' : 'i', [if (v != null) v]), d.address, d.port);
        if (m.address == '/sync' || m.address == '/ack') {
          reply('/ack');
        } else if (m.address.startsWith('/send/1/shader/') && m.address.endsWith('part')) {
          if (refuse) {
            reply(m.address, -1);
            continue;
          }
          final off = m.args[0] as int;
          total = m.args[1] as int;
          if (off == 0) blob.clear();
          blob.add(m.args[2] as Uint8List);
          reply(m.address, blob.length >= total ? total ~/ 4 : blob.length);
        } else if (m.address == '/send/1/shader/scanmap') {
          map = m.args[0] as Uint8List;
          reply(m.address, ByteData.sublistView(map! as Uint8List).getUint16(0, Endian.little));
        } else if (m.address.startsWith('/send/1/shader/k/')) {
          knobs[int.parse(m.address.split('/').last)] = (m.args[0] as double);
        }
      }
    });
    return sock.port;
  }
}

Future<void> _until(bool Function() ok) async {
  for (var i = 0; i < 100 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('connect, upload a scan stage with its map and knobs, and read back what was armed', () async {
    final dev = FakeScion();
    final port = await dev.start();
    final link = DeviceLink();
    await link.connect('127.0.0.1', port);
    await _until(() => link.connected);
    expect(link.connected, isTrue);

    final st = compileStage(templates['Scan: CSC gain rows']!.$2, slot: 1);
    final r = await link.upload(st, knobs: [1.5, 0, 0, 0, 0, 0, 0, 0.25]);
    expect(r, 'armed ${st.bytes.length} bytes in slot 1, scan map: ${st.outMap.length} entries');
    expect(dev.blob.toBytes(), st.bytes);
    // the map blob as shader.py sends it: count, then reg mask shift mode slot per entry
    final m = ByteData.sublistView(Uint8List.fromList(dev.map!));
    expect(m.getUint16(0, Endian.little), st.outMap.length);
    expect(m.getUint16(2, Endian.little), st.outMap.first.reg);
    await _until(() => dev.knobs.length == 8);
    expect(dev.knobs[0], 1.5);
    expect(dev.knobs[7], 0.25);
    link.dispose();
    dev.sock.close();
  });

  test('a large stage goes in 1 KB parts; a refusal is reported', () async {
    final dev = FakeScion();
    final port = await dev.start();
    final link = DeviceLink();
    await link.connect('127.0.0.1', port);
    await _until(() => link.connected);
    final big = compileStage(List.generate(16, (i) => 'out.o${i % 8} = noise(in.u * $i, in.v) * sin(in.t + $i) / (in.x + 1);').join('\n'));
    expect(big.bytes.length, greaterThan(1024));
    expect(await link.upload(big), startsWith('armed ${big.bytes.length} bytes in slot 0'));
    expect(dev.blob.toBytes(), big.bytes);
    dev.refuse = true;
    expect(await link.upload(big), startsWith('device refused part 1'));
    link.dispose();
    dev.sock.close();
  });

  test('no device: the upload says so instead of hanging', () async {
    final link = DeviceLink();
    final dead = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0); // nothing answers
    await link.connect('127.0.0.1', dead.port);
    final st = compileStage('out.dx = 1;');
    expect(await link.upload(st), startsWith('no reply to part 1/1'));
    link.dispose();
    dead.close();
  });
}
