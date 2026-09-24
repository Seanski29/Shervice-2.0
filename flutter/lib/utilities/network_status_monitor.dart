import 'dart:async';

import 'package:flutter/foundation.dart';

import 'network_status_stub.dart'
    if (dart.library.io) 'network_status_io.dart'
    if (dart.library.html) 'network_status_web.dart';

enum NetworkQuality { online, weak, offline }

class NetworkStatusMonitor {
  NetworkStatusMonitor._();

  static final ValueNotifier<NetworkQuality> status = ValueNotifier(
    NetworkQuality.online,
  );
  static NetworkStatusProbe? _probe;
  static bool _started = false;
  static Timer? _startTimer;

  static void start() {
    if (_started) return;
    _started = true;
    _startTimer?.cancel();
    _startTimer = Timer(const Duration(seconds: 5), () {
      if (!_started) return;
      _probe ??= createNetworkStatusProbe((quality) {
        if (status.value != quality) status.value = quality;
      });
      _probe!.start();
    });
  }

  static void stop() {
    _startTimer?.cancel();
    _startTimer = null;
    _probe?.stop();
    _probe = null;
    _started = false;
  }
}
