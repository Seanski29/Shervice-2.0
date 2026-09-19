// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import '../constant.dart';
import 'network_status_monitor.dart';

NetworkStatusProbe createNetworkStatusProbe(
  void Function(NetworkQuality) onStatus,
) => NetworkStatusProbe(onStatus);

class NetworkStatusProbe {
  NetworkStatusProbe(this.onStatus);

  final void Function(NetworkQuality) onStatus;
  final List<StreamSubscription<html.Event>> _subscriptions = [];
  Timer? _latencyTimer;
  bool _probeRunning = false;

  void start() {
    if (_subscriptions.isNotEmpty) return;
    _subscriptions.add(
      html.window.onOffline.listen((_) => onStatus(NetworkQuality.offline)),
    );
    _subscriptions.add(html.window.onOnline.listen((_) => _probeLatency()));
    _probeLatency();
    _latencyTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _probeLatency(),
    );
  }

  Future<void> _probeLatency() async {
    if (_probeRunning) return;
    if (!(html.window.navigator.onLine ?? true)) {
      onStatus(NetworkQuality.offline);
      return;
    }

    _probeRunning = true;
    final stopwatch = Stopwatch()..start();
    try {
      // Probe the service that login actually depends on. Probing the
      // Flutter dev server's favicon can report "offline" even while the
      // backend is healthy (and HEAD is not consistently handled by dev
      // servers).
      final probeUri = Uri.parse(
        '$localIp/?network_probe=${DateTime.now().millisecondsSinceEpoch}',
      );
      await html.HttpRequest.request(
        probeUri.toString(),
        method: 'GET',
      ).timeout(const Duration(seconds: 6));
      onStatus(
        stopwatch.elapsedMilliseconds >= 1800
            ? NetworkQuality.weak
            : NetworkQuality.online,
      );
    } catch (_) {
      onStatus(NetworkQuality.offline);
    } finally {
      _probeRunning = false;
    }
  }

  void stop() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _latencyTimer?.cancel();
    _latencyTimer = null;
  }
}
