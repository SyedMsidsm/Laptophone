import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/core/discovery/discovery.dart';
import 'package:personal_sender/core/identity/identity.dart';
import 'package:personal_sender/core/pairing/pairing.dart';
import 'package:personal_sender/core/protocol/models.dart';
import 'package:personal_sender/core/storage/paired_store.dart';

const _laptop = DeviceInfo(
  id: 'laptop',
  name: 'Laptop',
  platform: 'windows',
  appVersion: '0.1.0',
);
const _phone = DeviceInfo(
  id: 'phone',
  name: 'Phone',
  platform: 'android',
  appVersion: '0.1.0',
);

class FakeNetwork implements NetworkInfoProvider {
  FakeNetwork(this.addresses, this.gatewayAddress);
  List<String> addresses;
  String? gatewayAddress;

  @override
  Future<List<String>> localAddresses() async => addresses;

  @override
  Future<String?> gateway() async => gatewayAddress;
}

/// Records every probe; answers only for hosts in [answers].
class FakeProber {
  FakeProber(this.answers, {this.delay = Duration.zero});
  final Map<String, DeviceInfo> answers;
  final Duration delay;
  final List<String> calls = [];

  Future<DeviceInfo?> call(String host, int port) async {
    calls.add(host);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return answers[host];
  }
}

Future<PairedDeviceStore> storeWith({String? lastAddress}) async {
  final store = PairedDeviceStore(MemorySecretStore());
  await store.save(
    PairedDevice(
      id: 'laptop',
      name: 'Laptop',
      fingerprint: 'aa' * 32,
      secret: 'bb' * 32,
      lastAddress: lastAddress,
    ),
  );
  return store;
}

DiscoveryService service(
  PairedDeviceStore store,
  FakeNetwork net,
  FakeProber prober, {
  String ownPlatform = 'android',
}) => DiscoveryService(
  store: store,
  network: net,
  prober: prober.call,
  ownPlatform: ownPlatform,
);

void main() {
  group('order of attempts', () {
    test('last good address first, and it stops at the first match', () async {
      final prober = FakeProber({'192.168.1.6': _laptop});
      final s = service(
        await storeWith(lastAddress: '192.168.1.6:47820'),
        FakeNetwork(['192.168.1.7'], '192.168.1.1'),
        prober,
      );
      final state = await s.findOnce();
      expect(state.status, DiscoveryStatus.connected);
      expect(state.address, '192.168.1.6:47820');
      expect(prober.calls, ['192.168.1.6']);
    });

    test('then the gateway, before any scan', () async {
      final prober = FakeProber({'10.0.0.1': _phone});
      final s = service(
        await storeWith(lastAddress: '10.0.0.99:47820'),
        FakeNetwork(['10.0.0.5'], '10.0.0.1'),
        prober,
      );
      final state = await s.findOnce();
      expect(state.address, '10.0.0.1:47820');
      expect(prober.calls, ['10.0.0.99', '10.0.0.1']);
    });

    test('then a /24 scan that skips what was already tried', () async {
      final prober = FakeProber({'192.168.1.57': _laptop});
      final s = service(
        await storeWith(lastAddress: '192.168.1.20:47820'),
        FakeNetwork(['192.168.1.7'], '192.168.1.1'),
        prober,
      );
      final state = await s.findOnce();
      expect(state.address, '192.168.1.57:47820');
      expect(prober.calls.take(2), ['192.168.1.20', '192.168.1.1']);
      expect(prober.calls.where((c) => c == '192.168.1.20'), hasLength(1));
      expect(prober.calls.where((c) => c == '192.168.1.1'), hasLength(1));
      expect(prober.calls, isNot(contains('192.168.1.7'))); // ourselves
    });
  });

  test('devices with the wrong certificate or ID are ignored', () async {
    // The real prober returns null for those; the service must keep looking
    // and never report them as connected.
    final prober = FakeProber({});
    final s = service(
      await storeWith(lastAddress: '192.168.1.6:47820'),
      FakeNetwork(['192.168.1.7'], '192.168.1.1'),
      prober,
    );
    final state = await s.findOnce();
    expect(state.status, DiscoveryStatus.looking);
    expect(prober.calls, contains('192.168.1.6'));
    expect(prober.calls, contains('192.168.1.254'));
  });

  test('no network means offline; unpaired means looking', () async {
    final prober = FakeProber({});
    final offline = service(await storeWith(), FakeNetwork([], null), prober);
    expect((await offline.findOnce()).status, DiscoveryStatus.offline);

    final unpaired = DiscoveryService(
      store: PairedDeviceStore(MemorySecretStore()),
      network: FakeNetwork(['192.168.1.7'], '192.168.1.1'),
      prober: prober.call,
      ownPlatform: 'android',
    );
    expect((await unpaired.findOnce()).status, DiscoveryStatus.looking);
    expect(prober.calls, isEmpty);
  });

  test('a full /24 scan with no match finishes in under 4 s', () async {
    final prober = FakeProber({}, delay: const Duration(milliseconds: 300));
    final s = service(
      await storeWith(),
      FakeNetwork(['192.168.1.7'], null),
      prober,
    );
    final sw = Stopwatch()..start();
    final state = await s.findOnce();
    sw.stop();
    expect(state.status, DiscoveryStatus.looking);
    expect(prober.calls.length, 253); // 254 minus ourselves
    expect(sw.elapsedMilliseconds, lessThan(4000));
  });

  test('keeps looking, then connects when the device appears', () async {
    final prober = FakeProber({});
    final s = DiscoveryService(
      store: await storeWith(lastAddress: '192.168.1.6:47820'),
      network: FakeNetwork(['192.168.1.7'], '192.168.1.1'),
      prober: prober.call,
      ownPlatform: 'android',
      lookingInterval: const Duration(milliseconds: 50),
      connectedInterval: const Duration(milliseconds: 50),
    );
    final seen = <DiscoveryStatus>[];
    s.states.listen((st) => seen.add(st.status));
    s.start();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(seen, [DiscoveryStatus.looking]);

    prober.answers['192.168.1.6'] = _laptop;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(seen, [DiscoveryStatus.looking, DiscoveryStatus.connected]);
    await s.dispose();
  });

  group('network kind (never the Wi-Fi name)', () {
    test('ordinary Wi-Fi', () {
      expect(
        classifyNetwork(
          gateway: '192.168.1.1',
          ownAddresses: ['192.168.1.7'],
          ownPlatform: 'android',
          peerHost: '192.168.1.6',
          peerPlatform: 'windows',
        ),
        NetworkKind.wifi,
      );
    });

    test('laptop on the phone hotspot: the phone is the gateway', () {
      expect(
        classifyNetwork(
          gateway: '10.161.89.4',
          ownAddresses: ['10.161.89.190'],
          ownPlatform: 'windows',
          peerHost: '10.161.89.4',
          peerPlatform: 'android',
        ),
        NetworkKind.phoneHotspot,
      );
    });

    test('phone hosting the hotspot has no gateway', () {
      expect(
        classifyNetwork(
          gateway: null,
          ownAddresses: ['10.161.89.4'],
          ownPlatform: 'android',
          peerHost: '10.161.89.190',
          peerPlatform: 'windows',
        ),
        NetworkKind.phoneHotspot,
      );
    });

    test('phone on the Windows hotspot: the laptop is the gateway', () {
      expect(
        classifyNetwork(
          gateway: '192.168.137.1',
          ownAddresses: ['192.168.137.50'],
          ownPlatform: 'android',
          peerHost: '192.168.137.1',
          peerPlatform: 'windows',
        ),
        NetworkKind.laptopHotspot,
      );
    });

    test('laptop hosting the Windows hotspot', () {
      expect(
        classifyNetwork(
          gateway: null,
          ownAddresses: ['192.168.137.1'],
          ownPlatform: 'windows',
          peerHost: '192.168.137.50',
          peerPlatform: 'android',
        ),
        NetworkKind.laptopHotspot,
      );
    });
  });

  group('helpers', () {
    test('isPrivateIPv4', () {
      expect(isPrivateIPv4('192.168.1.7'), isTrue);
      expect(isPrivateIPv4('10.161.89.4'), isTrue);
      expect(isPrivateIPv4('172.20.10.2'), isTrue);
      expect(isPrivateIPv4('172.32.0.1'), isFalse);
      expect(isPrivateIPv4('192.0.0.8'), isFalse);
      expect(isPrivateIPv4('169.254.162.169'), isFalse);
      expect(isPrivateIPv4('8.8.8.8'), isFalse);
    });

    test('virtual adapters are skipped', () {
      expect(isVirtualInterface('vEthernet (WSL (Hyper-V firewall))'), isTrue);
      expect(isVirtualInterface('rmnet_data7'), isTrue);
      expect(isVirtualInterface('lo'), isTrue);
      expect(isVirtualInterface('Local Area Connection* 12'), isFalse);
      expect(isVirtualInterface('wlan0'), isFalse);
      expect(isVirtualInterface('WiFi'), isFalse);
    });

    test('parses the Windows default gateway, lowest metric wins', () {
      const out = '''
IPv4 Route Table
===========================================================================
Active Routes:
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0      10.0.0.1     10.0.0.9     55
          0.0.0.0          0.0.0.0     192.168.1.1    192.168.1.6     35
        127.0.0.0        255.0.0.0         On-link         127.0.0.1    331
''';
      expect(parseWindowsRoutePrint(out), '192.168.1.1');
      expect(parseWindowsRoutePrint('nothing here'), isNull);
    });
  });
}
