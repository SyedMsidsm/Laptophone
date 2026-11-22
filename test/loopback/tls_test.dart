import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/core/client/client.dart';
import 'package:personal_sender/core/identity/identity.dart';
import 'package:personal_sender/core/pairing/pairing.dart';
import 'package:personal_sender/core/storage/paired_store.dart';
import 'package:personal_sender/core/protocol/models.dart';
import 'package:personal_sender/core/server/server.dart';
import 'package:personal_sender/core/transfer/receiver.dart';

void main() {
  late Directory tmp;
  late DeviceIdentity identity;
  late CoreServer server;
  late PairedDeviceStore pairedStore;
  const secret =
      'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ps_tls_');
    identity = await DeviceIdentity.loadOrCreate(
      MemorySecretStore(),
      name: 'Test laptop',
    );
    pairedStore = PairedDeviceStore(MemorySecretStore());
    await pairedStore.save(
      const PairedDevice(
        id: 'client',
        name: 'Phone',
        fingerprint: 'f',
        secret: secret,
      ),
    );
    server = CoreServer(
      identity: identity,
      pairedStore: pairedStore,
      pairing: PairingManager(),
      info: DeviceInfo(
        id: identity.id,
        name: identity.name,
        platform: 'windows',
        appVersion: '0.1.0',
      ),
      receiver: Receiver(Directory('${tmp.path}/inbox')),
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  });

  tearDown(() async {
    await server.stop();
    await tmp.delete(recursive: true);
  });

  CoreClient clientWith(String fingerprint) => CoreClient(
    host: '127.0.0.1',
    port: server.port,
    pinnedFingerprint: fingerprint,
    secret: secret,
  );

  test('correct fingerprint connects', () async {
    final info = await clientWith(identity.fingerprint).getInfo();
    expect(info.id, identity.id);
  });

  test('wrong fingerprint is rejected', () async {
    final wrong = 'ab' * 32;
    expect(
      () => clientWith(wrong).getInfo(),
      throwsA(
        isA<ClientException>().having(
          (e) => e.message,
          'message',
          contains('does not match'),
        ),
      ),
    );
  });

  test('plain HTTP is not served', () async {
    final c = HttpClient();
    await expectLater(() async {
      final r = await c.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/api/v1/info'),
      );
      final res = await r.close();
      await res.drain<void>();
    }(), throwsA(anything));
    c.close(force: true);
  });

  test('probeFingerprint reads the server certificate fingerprint', () async {
    expect(
      await CoreClient.probeFingerprint('127.0.0.1', server.port),
      identity.fingerprint,
    );
  });

  test('identity is created once and reused from the store', () async {
    final store = MemorySecretStore();
    final sw = Stopwatch()..start();
    final first = await DeviceIdentity.loadOrCreate(store, name: 'A');
    final createMs = sw.elapsedMilliseconds;
    sw.reset();
    final second = await DeviceIdentity.loadOrCreate(store, name: 'A');
    expect(second.id, first.id);
    expect(second.fingerprint, first.fingerprint);
    expect(sw.elapsedMilliseconds, lessThan(createMs + 1));
    expect(createMs, lessThan(3000));
  });
}
