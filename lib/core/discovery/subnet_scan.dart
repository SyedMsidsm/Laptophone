import '../protocol/models.dart';

/// Asks the device at [host]:[port] who it is. Returns its info only if it is
/// the paired device (right certificate and ID); null for anything else,
/// including no answer.
typedef Prober = Future<DeviceInfo?> Function(String host, int port);

/// A device that answered a probe.
class ProbeHit {
  const ProbeHit(this.host, this.port, this.info);
  final String host;
  final int port;
  final DeviceInfo info;
}

/// Probes the other hosts of the /24 network that contains [localAddress],
/// in parallel, and returns the first match (or null).
///
/// [skip] holds addresses already tried or belonging to this device.
Future<ProbeHit?> scanSubnet({
  required String localAddress,
  required int port,
  required Prober probe,
  Set<String> skip = const {},
  int concurrency = 64,
}) async {
  final parts = localAddress.split('.');
  if (parts.length != 4) return null;
  final prefix = parts.take(3).join('.');
  final hosts = [
    for (var i = 1; i <= 254; i++)
      if (!skip.contains('$prefix.$i') && '$prefix.$i' != localAddress)
        '$prefix.$i',
  ];

  var next = 0;
  ProbeHit? found;

  Future<void> worker() async {
    while (found == null && next < hosts.length) {
      final host = hosts[next++];
      final info = await probe(host, port);
      if (info != null) found ??= ProbeHit(host, port, info);
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  return found;
}
