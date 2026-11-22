import '../client/client.dart';
import '../identity/identity.dart';
import '../server/server.dart';
import '../storage/paired_store.dart';
import 'pairing.dart';
import 'pairing_qr.dart';

/// Result of trying to pair; [error] is set when it failed.
class PairOutcome {
  const PairOutcome.success(PairedDevice this.device) : error = null;
  const PairOutcome.failure(String this.error) : device = null;

  final PairedDevice? device;
  final String? error;
  bool get ok => device != null;
}

/// Why a manual pairing failed, so the UI can show the right text.
const wrongCodeError = 'wrong_code';
const unreachableError = 'unreachable';

/// Pairs from a scanned QR code: pins the fingerprint in the code and tries
/// each address until one answers.
Future<PairOutcome> pairFromQr({
  required PairingQr qr,
  required DeviceIdentity identity,
  required PairedDeviceStore store,
}) async {
  for (final ip in qr.addresses) {
    final outcome = await _pairAt(
      host: ip,
      port: qr.port,
      fingerprint: qr.fingerprint,
      code: qr.code,
      identity: identity,
      store: store,
    );
    if (outcome.ok || outcome.error == wrongCodeError) return outcome;
  }
  return const PairOutcome.failure(unreachableError);
}

/// Pairs from a typed address and code. There is no fingerprint to check, so
/// the certificate is trusted on first use, guarded by the one-time code.
Future<PairOutcome> pairManually({
  required String address,
  required String code,
  required DeviceIdentity identity,
  required PairedDeviceStore store,
}) async {
  final parts = address.trim().split(':');
  final host = parts.first;
  final port = parts.length > 1
      ? int.tryParse(parts[1]) ?? defaultPort
      : defaultPort;
  if (host.isEmpty) return const PairOutcome.failure(unreachableError);
  final String fingerprint;
  try {
    fingerprint = await CoreClient.probeFingerprint(host, port);
  } on ClientException {
    return const PairOutcome.failure(unreachableError);
  }
  return _pairAt(
    host: host,
    port: port,
    fingerprint: fingerprint,
    code: code.replaceAll(RegExp(r'\s'), ''),
    identity: identity,
    store: store,
  );
}

Future<PairOutcome> _pairAt({
  required String host,
  required int port,
  required String fingerprint,
  required String code,
  required DeviceIdentity identity,
  required PairedDeviceStore store,
}) async {
  try {
    final response =
        await CoreClient(
          host: host,
          port: port,
          pinnedFingerprint: fingerprint,
        ).pair(
          PairRequest(
            code: code,
            deviceId: identity.id,
            deviceName: identity.name,
            fingerprint: identity.fingerprint,
          ),
        );
    final device = PairedDevice(
      id: response.deviceId,
      name: response.deviceName,
      fingerprint: response.fingerprint,
      secret: response.secret,
      lastAddress: '$host:$port',
    );
    await store.save(device);
    return PairOutcome.success(device);
  } on ClientException catch (e) {
    if (e.statusCode == 403) return const PairOutcome.failure(wrongCodeError);
    return const PairOutcome.failure(unreachableError);
  }
}
