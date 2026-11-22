import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/core/discovery/discovery.dart';
import 'package:personal_sender/core/discovery/prober.dart';
import 'package:personal_sender/core/identity/identity.dart';
import 'package:personal_sender/core/pairing/pairing.dart';
import 'package:personal_sender/core/protocol/models.dart';
import 'package:personal_sender/core/server/server.dart';
import 'package:personal_sender/core/storage/paired_store.dart';
import 'package:personal_sender/core/transfer/receiver.dart';

void main() {
  late Directory tmp;
  late DeviceIdentity host;
  late CoreServer server;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ps_probe_');
    host = await DeviceIdentity.loadOrCreate(MemorySecretStore(), name: 'Host');
    server = CoreServer(
      identity: host,
      info: DeviceInfo(
        id: host.id,
        name: host.name,
        platform: 'windows',
        appVersion: '0.1.0',
      ),
      receiver: Receiver(Directory('${tmp.path}/inbox')),
      pairedStore: PairedDeviceStore(MemorySecretStore()),
      pairing: PairingManager(),
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  });

  tearDown(() async {
    await server.stop();
    await tmp.delete(recursive: true);
  });

  PairedDevice paired({String? id, String? fingerprint}) => PairedDevice(
    id: id ?? host.id,
    name: 'Host',
    fingerprint: fingerprint ?? host.fingerprint,
    secret: 'aa' * 32,
  );

  test('right certificate and ID: the probe returns the device info', () async {
    final info = await pairedDeviceProber(paired())('127.0.0.1', server.port);
    expect(info?.id, host.id);
  });

  test('wrong certificate: ignored', () async {
    final probe = pairedDeviceProber(paired(fingerprint: 'cd' * 32));
    expect(await probe('127.0.0.1', server.port), isNull);
  });

  test('right certificate but another device ID: ignored', () async {
    final probe = pairedDeviceProber(paired(id: 'someone-else'));
    expect(await probe('127.0.0.1', server.port), isNull);
  });

  test('nothing listening: null, quickly', () async {
    final sw = Stopwatch()..start();
    final info = await pairedDeviceProber(paired())('127.0.0.1', 1);
    expect(info, isNull);
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });

  test(
    'a subnet scan with the real prober finds the host on loopback',
    () async {
      final hit = await scanSubnet(
        localAddress: '127.0.0.9',
        port: server.port,
        probe: pairedDeviceProber(paired()),
      );
      expect(hit?.host, '127.0.0.1');
    },
  );
}
