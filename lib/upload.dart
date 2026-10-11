/// Sends a compiled stage to a Scion over OSC/UDP (dart:io; not for the web).
library;

import 'dart:io';

import 'ae32k_shader_compiler.dart';

/// Uploads [stage] the way `shader.py --osc` does: 1 KB parts to the slot's path (the
/// device arms the stage only when the checksum matches), then knobs, then the scan map.
/// The device replies to its configured OSC client, so this does not wait for an ack.
Future<int> uploadStage(CompiledStage stage, String host,
    {int port = 9000, List<double>? knobs}) async {
  final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final addr = InternetAddress(host);
  try {
    for (final p in stageParts(stage.bytes, stage.slot)) {
      sock.send(p, addr, port);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    for (var k = 0; k < (knobs?.length ?? 0); k++) {
      sock.send(knobMessage(k, knobs![k]), addr, port);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (stage.slot == 1 && stage.outMap.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      sock.send(scanMapMessage(stage.outMap), addr, port);
    }
  } finally {
    sock.close();
  }
  return stage.bytes.length;
}
