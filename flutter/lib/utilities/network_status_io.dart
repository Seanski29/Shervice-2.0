import 'dart:async';
import 'dart:io';

import '../constant.dart';
import 'network_status_monitor.dart';

NetworkStatusProbe createNetworkStatusProbe(
  void Function(NetworkQuality) onStatus,
) => NetworkStatusProbe(onStatus);

class NetworkStatusProbe {
  NetworkStatusProbe(this.onStatus);

  final void Function(NetworkQuality) onStatus;
  Timer? _timer;
  bool _probeRunning = false;

  void start() {
    if (_timer != null) return;
    _probeLatency();
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _probeLatency(),
    );
  }

  Future<void> _probeLatency() async {
    if (_probeRunning) return;
    _probeRunning = true;
    final stopwatch = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.headUrl(Uri.parse(backendUrl));
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      await response.drain<void>();
      onStatus(
        stopwatch.elapsedMilliseconds >= 1800
            ? NetworkQuality.weak
            : NetworkQuality.online,
      );
    } catch (_) {
      onStatus(NetworkQuality.offline);
    } finally {
      client.close(force: true);
      _probeRunning = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
