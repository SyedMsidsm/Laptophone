import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/core/client/client.dart';
import 'package:personal_sender/core/identity/identity.dart';
import 'package:personal_sender/core/pairing/pairing.dart';
import 'package:personal_sender/core/protocol/models.dart';
import 'package:personal_sender/core/server/server.dart';
import 'package:personal_sender/core/storage/paired_store.dart';
import 'package:personal_sender/core/transfer/receiver.dart';

void main() {
  late Directory tmp;
  late DeviceIdentity host;
  late DeviceIdentity guest;
  late PairedDeviceStore hostStore;
  late PairingManager pairing;
  late CoreServer server;
  final texts = <TextMessage>[];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ps_pair_');
    host = await DeviceIdentity.loadOrCreate(MemorySecretStore(), name: 'Host');
    guest = await DeviceIdentity.loadOrCreate(
      MemorySecretStore(),
      name: 'Guest',
    );
    hostStore = PairedDeviceStore(MemorySecretStore());
    pairing = PairingManager();
    texts.clear();
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
      onText: texts.add,
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  });

  tearDown(() async {
    await server.stop();
    await tmp.delete(recursive: true);
  });

  CoreClient client({String? secret}) => CoreClient(
    host: '127.0.0.1',
    port: server.port,
    pinnedFingerprint: host.fingerprint,
    secret: secret,
  );

  PairRequest request(String code) => PairRequest(
    code: code,
    deviceId: guest.id,
    deviceName: guest.name,
    fingerprint: guest.fingerprint,
  );

  Matcher status(int code) =>
      isA<ClientException>().having((e) => e.statusCode, 'status', code);

  test('pairing succeeds once; reusing the code fails', () async {
    final code = pairing.startPairing();
    expect(code, matches(RegExp(r'^\d{6}$')));

    final response = await client().pair(request(code));
    expect(response.deviceId, host.id);
    expect(response.fingerprint, host.fingerprint);
    expect(response.secret, matches(RegExp(r'^[0-9a-f]{64}$')));

    final saved = await hostStore.load();
    expect(saved!.id, guest.id);
    expect(saved.fingerprint, guest.fingerprint);
    expect(saved.secret, response.secret);

    await expectLater(client().pair(request(code)), throwsA(status(403)));
  });

  test('wrong code is refused and five wrong guesses cancel it', () async {
    final code = pairing.startPairing();
    final wrong = code == '000000' ? '000001' : '000000';
    for (var i = 0; i < 5; i++) {
      await expectLater(client().pair(request(wrong)), throwsA(status(403)));
    }
    // The right code no longer works either.
    await expectLater(client().pair(request(code)), throwsA(status(403)));
    expect(await hostStore.load(), isNull);
  });

  test('pairing without a started session is refused', () async {
    await expectLater(client().pair(request('123456')), throwsA(status(403)));
  });

  test('expired code is refused', () async {
    var now = DateTime(2026, 1, 1);
    final timed = PairingManager(clock: () => now);
    final code = timed.startPairing();
    now = now.add(const Duration(minutes: 6));
    expect(() => timed.consume(code), throwsA(isA<PairingException>()));
  });

  group('auth', () {
    late String secret;

    setUp(() async {
      final r = await client().pair(request(pairing.startPairing()));
      secret = r.secret;
    });

    test('no token gets 401 on transfers, uploads and text', () async {
      final c = client();
      final offer = TransferOffer(senderId: guest.id, files: const []);
      await expectLater(c.sendOffer(offer), throwsA(status(401)));
      final f = File('${tmp.path}/x')..writeAsBytesSync([1]);
      await expectLater(c.sendFile('id', 0, f), throwsA(status(401)));
      await expectLater(
        c.sendText(const TextMessage(text: 'hi', isUrl: false)),
        throwsA(status(401)),
      );
    });

    test('wrong secret gets 401', () async {
      final c = client(secret: 'ff' * 32);
      await expectLater(
        c.sendText(const TextMessage(text: 'hi', isUrl: false)),
        throwsA(status(401)),
      );
      expect(texts, isEmpty);
    });

    test('right secret is accepted', () async {
      await client(secret: secret)
          .sendText(const TextMessage(text: 'https://x.test', isUrl: true));
      expect(texts.single.text, 'https://x.test');
    });

    test('/info stays open without a token', () async {
      expect((await client().getInfo()).id, host.id);
    });

    test('unknown paths need the secret too', () async {
      final c = HttpClient(context: SecurityContext(withTrustedRoots: false));
      c.badCertificateCallback = (_, _, _) => true;
      final r = await c.getUrl(
        Uri.parse('https://127.0.0.1:${server.port}/api/v1/nothing'),
      );
      final res = await r.close();
      expect(res.statusCode, 401);
      await res.transform(utf8.decoder).drain<void>();
      c.close(force: true);
    });
  });
}
