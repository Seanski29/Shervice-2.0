import 'network_status_monitor.dart';

NetworkStatusProbe createNetworkStatusProbe(
  void Function(NetworkQuality) onStatus,
) => NetworkStatusProbe(onStatus);

class NetworkStatusProbe {
  NetworkStatusProbe(this.onStatus);

  final void Function(NetworkQuality) onStatus;

  void start() => onStatus(NetworkQuality.online);

  void stop() {}
}
