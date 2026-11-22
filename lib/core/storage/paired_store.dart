import 'dart:convert';

import '../identity/identity.dart';
import '../pairing/pairing.dart';

/// Keeps the paired device (fingerprint, secret, last good address) in the
/// secret store, so it survives restarts.
class PairedDeviceStore {
  PairedDeviceStore(this._store);

  final SecretStore _store;
  static const _key = 'paired.device';

  PairedDevice? _cache;
  bool _loaded = false;

  Future<PairedDevice?> load() async {
    if (_loaded) return _cache;
    final raw = await _store.read(_key);
    _cache = (raw == null || raw.isEmpty)
        ? null
        : PairedDevice.fromJson(jsonDecode(raw) as Map<String, Object?>);
    _loaded = true;
    return _cache;
  }

  Future<void> save(PairedDevice device) async {
    await _store.write(_key, jsonEncode(device.toJson()));
    _cache = device;
    _loaded = true;
  }

  /// Remembers the address that last worked. No-op when not paired.
  Future<void> updateLastAddress(String address) async {
    final d = await load();
    if (d != null) await save(d.withLastAddress(address));
  }

  Future<void> clear() async {
    await _store.write(_key, '');
    _cache = null;
    _loaded = true;
  }
}
