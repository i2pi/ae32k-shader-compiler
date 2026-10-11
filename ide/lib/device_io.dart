// The link to a SCION device over OSC/UDP, as scion_controller_app does it (lib/network.dart there):
// one socket on an ephemeral port, `/sync` then `/ack` every second until the device answers
// `/ack`, a heartbeat every 3 s, and "disconnected" after 10 s of silence. Replies come back to the
// same socket, which is how an upload learns what the device armed.
import 'dart:async';
import 'dart:io';

import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart';
import 'package:ae32k_shader_compiler/ae32k_shader_compiler.dart' as osc
    show oscMessage, stageParts, knobMessage, scanMapMessage, slotPath;
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

import 'osc_decode.dart';

const bool deviceSupported = true;

class FoundDevice {
  final String host, label;
  final int port;
  const FoundDevice(this.host, this.port, this.label);
}

class DeviceLink extends ChangeNotifier {
  String host = 'scion.local';
  int port = 9000;
  RawDatagramSocket? _sock;
  InternetAddress? _addr;
  Timer? _timer;
  DateTime _lastRx = DateTime.fromMillisecondsSinceEpoch(0);
  bool _acked = false;
  String status = 'not connected';
  final _replies = StreamController<OscReply>.broadcast();

  bool get connected =>
      _acked &&
      DateTime.now().difference(_lastRx) < const Duration(seconds: 10);
  bool get open => _sock != null;

  Future<void> connect(String h, int p) async {
    disconnect();
    host = h;
    port = p;
    status = 'resolving $h';
    notifyListeners();
    try {
      final addrs = await InternetAddress.lookup(h);
      _addr = addrs.firstWhere((a) => a.type == InternetAddressType.IPv4,
          orElse: () => addrs.first);
      _sock = await RawDatagramSocket.bind(
          _addr!.type == InternetAddressType.IPv4
              ? InternetAddress.anyIPv4
              : InternetAddress.anyIPv6,
          0);
    } catch (e) {
      status = 'cannot reach $h: $e';
      notifyListeners();
      return;
    }
    _sock!.listen((ev) {
      if (ev != RawSocketEvent.read) return;
      final d = _sock?.receive();
      if (d == null) return;
      for (final m in decodeOsc(d.data)) {
        _lastRx = DateTime.now();
        if (m.address == '/ack') {
          if (!_acked) {
            _acked = true;
            status = 'connected to $host:$port';
            notifyListeners();
          }
        } else {
          _replies.add(m);
        }
      }
    });
    status = 'waiting for $host:$port';
    _send(osc.oscMessage('/sync', '', []));
    var tick = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      tick++;
      if (!_acked || tick % 3 == 0) _send(osc.oscMessage('/ack', '', []));
      if (_acked && !connected) {
        _acked = false;
        status = 'lost $host:$port (no reply for 10 s)';
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void disconnect() {
    _timer?.cancel();
    _timer = null;
    _sock?.close();
    _sock = null;
    _acked = false;
    status = 'not connected';
    notifyListeners();
  }

  void _send(Uint8List packet) {
    final s = _sock, a = _addr;
    if (s != null && a != null) s.send(packet, a, port);
  }

  /// Sends [packet] and waits for the device's reply on [address] (null on timeout).
  Future<OscReply?> request(
      Uint8List packet, String address, Duration timeout) async {
    final f = _replies.stream
        .firstWhere((m) => m.address == address)
        .timeout(timeout);
    _send(packet);
    try {
      return await f;
    } on TimeoutException {
      return null;
    } on StateError {
      return null;
    }
  }

  void sendKnob(int k, double v) => _send(osc.knobMessage(k, v));

  /// Uploads [stage] part by part, each acknowledged by the device (bytes received so far;
  /// the last part's reply is the number of words it armed). Then knobs, then the scan map.
  /// Returns a log line.
  Future<String> upload(CompiledStage stage,
      {List<double>? knobs, void Function(String)? progress}) async {
    if (_sock == null) return 'not connected';
    final path = osc.slotPath[stage.slot]!;
    final parts = osc.stageParts(stage.bytes, stage.slot);
    int? armed;
    for (var i = 0; i < parts.length; i++) {
      progress?.call('part ${i + 1}/${parts.length}');
      final last = i == parts.length - 1;
      final r = await request(parts[i], path, Duration(seconds: last ? 6 : 2));
      if (r == null) {
        return 'no reply to part ${i + 1}/${parts.length} (is the device connected and in hybrid mode?)';
      }
      final v =
          r.args.isNotEmpty && r.args.first is int ? r.args.first as int : null;
      if (v == null || v < 0) return 'device refused part ${i + 1}: ${r.args}';
      if (last) armed = v;
    }
    for (var k = 0; k < (knobs?.length ?? 0); k++) {
      sendKnob(k, knobs![k]);
    }
    var mapNote = '';
    if (stage.slot == 1 && stage.outMap.isNotEmpty) {
      final r = await request(osc.scanMapMessage(stage.outMap),
          '/send/1/shader/scanmap', const Duration(seconds: 3));
      mapNote = r == null
          ? ', scan map: no reply'
          : ', scan map: ${r.args.isEmpty ? '?' : r.args.first} entries';
    }
    final want = stage.bytes.length ~/ 4;
    return armed == want
        ? 'armed ${stage.bytes.length} bytes in slot ${stage.slot}$mapNote'
        : 'device armed $armed words, expected $want (checksum or load failed)$mapNote';
  }

  /// Browses mDNS for `_scion._udp` for [time].
  static Future<List<FoundDevice>> discover(
      {Duration time = const Duration(seconds: 3)}) async {
    final found = <String, FoundDevice>{};
    nsd.Discovery? d;
    try {
      d = await nsd.startDiscovery('_scion._udp',
          autoResolve: true, ipLookupType: nsd.IpLookupType.any);
      await Future<void>.delayed(time);
      for (final s in d.services) {
        final port = s.port;
        if (port == null) continue;
        final usable = (s.addresses ?? const <InternetAddress>[])
            .where((a) =>
                !a.isLoopback && a.address != '0.0.0.0' && a.address != '::')
            .toList();
        final v4 = usable.where((a) => a.type == InternetAddressType.IPv4);
        var host = usable.isEmpty
            ? (s.host ?? '')
            : (v4.isNotEmpty ? v4.first : usable.first).address;
        while (host.endsWith('.')) {
          host = host.substring(0, host.length - 1);
        }
        if (host.isEmpty) continue;
        var label = s.host ?? s.name ?? host;
        while (label.endsWith('.')) {
          label = label.substring(0, label.length - 1);
        }
        found['$host:$port'] = FoundDevice(host, port, label);
      }
    } catch (_) {
      // no mDNS on this platform: manual entry still works
    } finally {
      if (d != null) {
        try {
          await nsd.stopDiscovery(d);
        } catch (_) {}
      }
    }
    return found.values.toList();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sock?.close();
    _sock = null;
    _replies.close();
    super.dispose();
  }
}
