import '../client/client.dart';
import '../pairing/pairing.dart';
import '../storage/paired_store.dart';
import 'subnet_scan.dart';

/// A [Prober] for the paired device: connects with its pinned certificate and
/// accepts the answer only if the device ID matches too. Anything else (no
/// answer, wrong certificate, another device) gives null.
Prober pairedDeviceProber(
  PairedDevice paired, {
  Duration timeout = const Duration(milliseconds: 300),
}) {
  return (host, port) async {
    try {
      final info = await CoreClient(
        host: host,
        port: port,
        pinnedFingerprint: paired.fingerprint,
        connectTimeout: timeout,
      ).getInfo().timeout(timeout * 4);
      return info.id == paired.id ? info : null;
    } on Object {
      return null;
    }
  };
}

/// A [Prober] that always uses the currently paired device from [store].
Prober storeProber(
  PairedDeviceStore store, {
  Duration timeout = const Duration(milliseconds: 300),
}) {
  return (host, port) async {
    final paired = await store.load();
    if (paired == null) return null;
    return pairedDeviceProber(paired, timeout: timeout)(host, port);
  };
}
