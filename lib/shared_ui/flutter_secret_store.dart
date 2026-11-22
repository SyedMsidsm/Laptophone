import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/identity/identity.dart';

/// [SecretStore] backed by the platform's secure storage (Android Keystore,
/// Windows Credential Locker/DPAPI).
class FlutterSecretStore implements SecretStore {
  const FlutterSecretStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}
