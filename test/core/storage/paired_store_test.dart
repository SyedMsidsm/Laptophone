import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/core/identity/identity.dart';
import 'package:personal_sender/core/pairing/pairing.dart';
import 'package:personal_sender/core/storage/paired_store.dart';

void main() {
  const device = PairedDevice(
    id: 'abc',
    name: 'Galaxy S24 Ultra',
    fingerprint: 'aa11',
    secret: 'cc22',
  );

  test('starts empty', () async {
    expect(await PairedDeviceStore(MemorySecretStore()).load(), isNull);
  });

  test(
    'paired device survives a restart (reload from the same store)',
    () async {
      final backing = MemorySecretStore();
      await PairedDeviceStore(backing).save(device);

      final reloaded = await PairedDeviceStore(backing).load();
      expect(reloaded!.id, 'abc');
      expect(reloaded.name, 'Galaxy S24 Ultra');
      expect(reloaded.fingerprint, 'aa11');
      expect(reloaded.secret, 'cc22');
      expect(reloaded.lastAddress, isNull);
    },
  );

  test('last good address is remembered across restarts', () async {
    final backing = MemorySecretStore();
    final store = PairedDeviceStore(backing);
    await store.save(device);
    await store.updateLastAddress('192.168.1.7:47820');

    final reloaded = await PairedDeviceStore(backing).load();
    expect(reloaded!.lastAddress, '192.168.1.7:47820');
    expect(reloaded.secret, 'cc22');
  });

  test('updateLastAddress does nothing when unpaired', () async {
    final store = PairedDeviceStore(MemorySecretStore());
    await store.updateLastAddress('1.2.3.4:5');
    expect(await store.load(), isNull);
  });

  test('clear removes the pairing, also after reload', () async {
    final backing = MemorySecretStore();
    final store = PairedDeviceStore(backing);
    await store.save(device);
    await store.clear();
    expect(await PairedDeviceStore(backing).load(), isNull);
  });
}
