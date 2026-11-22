import 'package:uuid/uuid.dart';

import 'certificate.dart';

/// Where secrets live. The Flutter apps back this with secure storage;
/// tests use [MemorySecretStore]. Keeps `lib/core` free of Flutter imports.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

/// This device's permanent identity: ID, name and TLS certificate.
class DeviceIdentity {
  const DeviceIdentity({
    required this.id,
    required this.name,
    required this.certificate,
  });

  final String id;
  final String name;
  final DeviceCertificate certificate;

  String get fingerprint => certificate.fingerprint;

  static const _idKey = 'identity.id';
  static const _certKey = 'identity.cert';
  static const _keyKey = 'identity.key';

  /// Loads the saved identity or creates and saves one. The certificate is
  /// generated once and reused after restarts.
  static Future<DeviceIdentity> loadOrCreate(
    SecretStore store, {
    required String name,
  }) async {
    var id = await store.read(_idKey);
    final certPem = await store.read(_certKey);
    final keyPem = await store.read(_keyKey);
    if (id != null && certPem != null && keyPem != null) {
      return DeviceIdentity(
        id: id,
        name: name,
        certificate: DeviceCertificate(certPem: certPem, keyPem: keyPem),
      );
    }
    id = const Uuid().v4();
    final cert = DeviceCertificate.generate(name);
    await store.write(_idKey, id);
    await store.write(_certKey, cert.certPem);
    await store.write(_keyKey, cert.keyPem);
    return DeviceIdentity(id: id, name: name, certificate: cert);
  }
}
