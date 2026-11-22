import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/core/discovery/discovery.dart';
import 'package:personal_sender/core/discovery/udp_announce.dart';
import 'package:personal_sender/core/identity/identity.dart';
import 'package:personal_sender/core/pairing/pairing.dart';
import 'package:personal_sender/core/protocol/models.dart';
import 'package:personal_sender/core/storage/paired_store.dart';

class _Net implements NetworkInfoProvider {
  @override
  Future<List<String>> localAddresses() async => ['127.0.0.1'];

  @override
  Future<String?> gateway() async => null;
}

Future<PairedDeviceStore> _store(String peerId, String secret) async {
  final s = PairedDeviceStore(MemorySecretStore());
  await s.save(
    PairedDevice(
      id: peerId,
      name: 'peer',
      fingerprint: 'aa' * 32,
      secret: secret,
    ),
  );
  return s;
}

void main() {
  final secret = 'ab' * 32;

  group('Hello', () {
    test('round-trips with the right secret', () {
      final bytes = Hello.encode(const Hello(id: 'dev-1', port: 47820), secret);
      final hello = Hello.decode(bytes, secret)!;
      expect(hello.id, 'dev-1');
      expect(hello.port, 47820);
    });

    test('wrong secret, tampered fields and garbage are rejected', () {
      final bytes = Hello.encode(const Hello(id: 'dev-1', port: 47820), secret);
      expect(Hello.decode(bytes, 'cd' * 32), isNull);

      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      expect(
        Hello.decode(utf8.encode(jsonEncode({...json, 'port': 9})), secret),
        isNull,
      );
      expect(
        Hello.decode(utf8.encode(jsonEncode({...json, 'id': 'evil'})), secret),
        isNull,
      );
      expect(Hello.decode(utf8.encode('hello'), secret), isNull);
      expect(Hello.decode(const [], secret), isNull);
    });
  });

  group('announcer over loopback UDP', () {
    // Ports well away from 47820 so a running app is not disturbed.
    const portA = 48611;
    const portB = 48612;
    late UdpAnnouncer a;
    late UdpAnnouncer b;
    final heardByA = <String>[];
    final heardByB = <String>[];

    Future<UdpAnnouncer> make({
      required String selfId,
      required String peerId,
      required int listen,
      required int sendTo,
      required String storeSecret,
      required List<String> heard,
    }) async => UdpAnnouncer(
      selfId: selfId,
      servicePort: 47820,
      store: await _store(peerId, storeSecret),
      network: _Net(),
      onHello: (host, port) => heard.add('$host:$port'),
      listenPort: listen,
      interval: const Duration(milliseconds: 100),
      destinations: [(InternetAddress.loopbackIPv4, sendTo)],
    );

    setUp(() {
      heardByA.clear();
      heardByB.clear();
    });

    tearDown(() async {
      await a.stop();
      await b.stop();
    });

    test('each side hears the other, with the sender address', () async {
      a = await make(
        selfId: 'A',
        peerId: 'B',
        listen: portA,
        sendTo: portB,
        storeSecret: secret,
        heard: heardByA,
      );
      b = await make(
        selfId: 'B',
        peerId: 'A',
        listen: portB,
        sendTo: portA,
        storeSecret: secret,
        heard: heardByB,
      );
      await a.start();
      await b.start();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(heardByA, isNotEmpty);
      expect(heardByB, isNotEmpty);
      expect(heardByA.first, '127.0.0.1:47820');
    });

    test('hellos signed with another secret are ignored', () async {
      a = await make(
        selfId: 'A',
        peerId: 'B',
        listen: portA,
        sendTo: portB,
        storeSecret: secret,
        heard: heardByA,
      );
      b = await make(
        selfId: 'B',
        peerId: 'A',
        listen: portB,
        sendTo: portA,
        storeSecret: 'ef' * 32, // B signs with a different secret
        heard: heardByB,
      );
      await a.start();
      await b.start();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(heardByA, isEmpty);
    });

    test('our own hellos are ignored', () async {
      // A sends to its own port; the ID matches, so nothing is reported.
      a = await make(
        selfId: 'A',
        peerId: 'A',
        listen: portA,
        sendTo: portA,
        storeSecret: secret,
        heard: heardByA,
      );
      b = await make(
        selfId: 'B',
        peerId: 'A',
        listen: portB,
        sendTo: portB,
        storeSecret: secret,
        heard: heardByB,
      );
      await a.start();
      await b.start();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(heardByA, isEmpty);
    });
  });

  test(
    'a hint is tried first and connects without waiting for a scan',
    () async {
      final store = await _store('laptop', secret);
      final calls = <String>[];
      const info = DeviceInfo(
        id: 'laptop',
        name: 'Laptop',
        platform: 'windows',
        appVersion: '0.1.0',
      );
      final service = DiscoveryService(
        store: store,
        network: _Net(),
        prober: (host, port) async {
          calls.add('$host:$port');
          return host == '192.168.1.6' ? info : null;
        },
        ownPlatform: 'android',
        lookingInterval: const Duration(hours: 1),
      );
      final states = <DiscoveryStatus>[];
      service.states.listen((s) => states.add(s.status));
      service.start();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(states, [DiscoveryStatus.looking]);
      calls.clear();

      service.hint('192.168.1.6', 47820);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(calls.first, '192.168.1.6:47820');
      expect(states.last, DiscoveryStatus.connected);
      expect(service.state.address, '192.168.1.6:47820');
      await service.dispose();
    },
  );
}
