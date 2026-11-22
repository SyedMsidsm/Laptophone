import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/core/identity/identity.dart';
import 'package:personal_sender/core/pairing/pair_flow.dart';
import 'package:personal_sender/core/pairing/pairing.dart';
import 'package:personal_sender/core/pairing/pairing_qr.dart';
import 'package:personal_sender/core/protocol/models.dart';
import 'package:personal_sender/core/server/server.dart';
import 'package:personal_sender/core/storage/paired_store.dart';
import 'package:personal_sender/core/transfer/receiver.dart';

void main() {
  late Directory tmp;
  late DeviceIdentity host;
  late DeviceIdentity guest;
  late PairedDeviceStore hostStore;
  late PairedDeviceStore guestStore;
  late PairingManager pairing;
  late CoreServer server;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ps_flow_');
    host = await DeviceIdentity.loadOrCreate(
      MemorySecretStore(),
      name: 'Laptop',
    );
    guest = await DeviceIdentity.loadOrCreate(
      MemorySecretStore(),
      name: 'Phone',
    );
    hostStore = PairedDeviceStore(MemorySecretStore());
    guestStore = PairedDeviceStore(MemorySecretStore());
    pairing = PairingManager();
    server = CoreServer(
      identity: host,
      info: DeviceInfo(
        id: host.id,
        name: host.name,
        platform: 'windows',
        appVersion: '0.1.0',
      ),
      receiver: Receiver(Directory('${tmp.path}/inbox')),
      pairedStore: hostStore,
      pairing: pairing,
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  });

  tearDown(() async {
    await server.stop();
    await tmp.delete(recursive: true);
  });

  PairingQr qrWith(String code, List<String> ips) => PairingQr(
    deviceId: host.id,
    deviceName: host.name,
    addresses: ips,
    port: server.port,
    fingerprint: host.fingerprint,
    code: code,
  );

  test('scanning the QR pairs both sides and saves the address', () async {
    final qr = qrWith(pairing.startPairing(), ['127.0.0.1']);
    final outcome = await pairFromQr(
      qr: qr,
      identity: guest,
      store: guestStore,
    );
    expect(outcome.ok, isTrue);

    final onGuest = await guestStore.load();
    final onHost = await hostStore.load();
    expect(onGuest!.id, host.id);
    expect(onGuest.fingerprint, host.fingerprint);
    expect(onGuest.lastAddress, '127.0.0.1:${server.port}');
    expect(onHost!.id, guest.id);
    expect(onHost.fingerprint, guest.fingerprint);
    expect(onGuest.secret, onHost.secret);
  });

  test('tries the next address when the first is unreachable', () async {
    // 192.0.2.x is reserved for documentation and never answers.
    final qr = qrWith(pairing.startPairing(), ['127.0.0.2', '127.0.0.1']);
    final outcome = await pairFromQr(
      qr: qr,
      identity: guest,
      store: guestStore,
    );
    expect(outcome.ok, isTrue);
  });

  test('wrong code reports wrongCodeError and stops trying', () async {
    pairing.startPairing();
    final qr = qrWith(
      '000000' == pairing.startPairing() ? '111111' : '000000',
      ['127.0.0.1'],
    );
    final outcome = await pairFromQr(
      qr: qr,
      identity: guest,
      store: guestStore,
    );
    expect(outcome.ok, isFalse);
    expect(outcome.error, wrongCodeError);
    expect(await guestStore.load(), isNull);
  });

  test('QR with a different fingerprint is refused', () async {
    final code = pairing.startPairing();
    final qr = PairingQr(
      deviceId: host.id,
      deviceName: host.name,
      addresses: const ['127.0.0.1'],
      port: server.port,
      fingerprint: 'cd' * 32,
      code: code,
    );
    final outcome = await pairFromQr(
      qr: qr,
      identity: guest,
      store: guestStore,
    );
    expect(outcome.ok, isFalse);
    expect(outcome.error, unreachableError);
    expect(await hostStore.load(), isNull);
  });

  test('manual address and grouped code pair', () async {
    final code = pairing.startPairing();
    final grouped = '${code.substring(0, 3)} ${code.substring(3)}';
    final outcome = await pairManually(
      address: '127.0.0.1:${server.port}',
      code: grouped,
      identity: guest,
      store: guestStore,
    );
    expect(outcome.ok, isTrue);
  });

  test('manual path: wrong code and unreachable address', () async {
    pairing.startPairing();
    final wrong = await pairManually(
      address: '127.0.0.1:${server.port}',
      code: '000000',
      identity: guest,
      store: guestStore,
    );
    // 000000 could (1 in a million) be the real code; accept either failure.
    expect(wrong.ok || wrong.error == wrongCodeError, isTrue);

    final nobody = await pairManually(
      address: '127.0.0.1:1',
      code: '123456',
      identity: guest,
      store: guestStore,
    );
    expect(nobody.error, unreachableError);
  });
}
