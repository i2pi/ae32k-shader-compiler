// The IDE's upload against a real SCION, only when asked:
//   flutter test test/live_device_test.dart --dart-define=SCION=192.168.100.221
// Uploads the ripple warp stage to slot 0 (the warp slot) and checks the device armed it.
import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shader_ide/device_io.dart';
import 'package:shader_ide/templates.dart';

const host = String.fromEnvironment('SCION');

void main() {
  test('upload to $host', () async {
    final link = DeviceLink();
    await link.connect(host, 9000);
    for (var i = 0; i < 50 && !link.connected; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print('link: ${link.status}');
    expect(link.connected, isTrue, reason: 'no /ack from $host');
    final st = compileStage(templates['Warp: ripple']!.$2, slot: 0);
    final r = await link.upload(st);
    // ignore: avoid_print
    print('upload: $r');
    expect(r, startsWith('armed ${st.bytes.length} bytes in slot 0'));
    link.dispose();
  }, skip: host.isEmpty ? 'pass --dart-define=SCION=<device ip>' : false, timeout: const Timeout(Duration(seconds: 30)));
}
