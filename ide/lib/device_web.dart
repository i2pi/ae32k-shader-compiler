// Browsers cannot open UDP sockets: on the web the IDE edits, checks and measures, but cannot upload.
import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:flutter/foundation.dart';

const bool deviceSupported = false;

class FoundDevice {
  final String host, label;
  final int port;
  const FoundDevice(this.host, this.port, this.label);
}

class DeviceLink extends ChangeNotifier {
  String host = 'scion.local';
  int port = 9000;
  String status = 'uploading needs the desktop app (browsers have no UDP)';
  bool get connected => false;
  bool get open => false;
  Future<void> connect(String h, int p) async {}
  void disconnect() {}
  void sendKnob(int k, double v) {}
  Future<String> upload(CompiledStage stage,
          {List<double>? knobs, void Function(String)? progress}) async =>
      status;
  static Future<List<FoundDevice>> discover(
          {Duration time = const Duration(seconds: 3)}) async =>
      const [];
}
