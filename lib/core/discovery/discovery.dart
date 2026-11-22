import 'dart:async';

import '../pairing/pairing.dart';
import '../protocol/models.dart';
import '../storage/paired_store.dart';
import 'gateway.dart';
import 'subnet_scan.dart';

export 'gateway.dart';
export 'subnet_scan.dart';

enum DiscoveryStatus { connected, looking, offline }

/// The kind of network, never its name.
enum NetworkKind { wifi, phoneHotspot, laptopHotspot, unknown }

class DiscoveryState {
  const DiscoveryState.offline()
    : status = DiscoveryStatus.offline,
      address = null,
      peer = null,
      network = NetworkKind.unknown;

  const DiscoveryState.looking(this.network)
    : status = DiscoveryStatus.looking,
      address = null,
      peer = null;

  const DiscoveryState.connected({
    required String this.address,
    required DeviceInfo this.peer,
    required this.network,
  }) : status = DiscoveryStatus.connected;

  final DiscoveryStatus status;

  /// `host:port` of the paired device while connected.
  final String? address;
  final DeviceInfo? peer;
  final NetworkKind network;

  @override
  bool operator ==(Object other) =>
      other is DiscoveryState &&
      other.status == status &&
      other.address == address &&
      other.network == network;

  @override
  int get hashCode => Object.hash(status, address, network);

  @override
  String toString() => 'DiscoveryState($status, $address, $network)';
}

/// Windows' built-in hotspot always gives the laptop this address.
const windowsHotspotAddress = '192.168.137.1';

/// Works out what kind of network we are on without using its name.
///
/// - The paired device is the gateway: it is hosting the hotspot (a phone
///   hosts a phone hotspot, a laptop a laptop hotspot).
/// - We are the Windows hotspot host: we hold 192.168.137.1.
/// - We are a phone with no gateway while connected: we host the hotspot.
/// - Otherwise it is an ordinary Wi-Fi network.
NetworkKind classifyNetwork({
  required String? gateway,
  required List<String> ownAddresses,
  required String ownPlatform,
  String? peerHost,
  String? peerPlatform,
}) {
  if (gateway != null && peerHost == gateway) {
    return peerPlatform == 'android'
        ? NetworkKind.phoneHotspot
        : NetworkKind.laptopHotspot;
  }
  if (ownAddresses.contains(windowsHotspotAddress)) {
    return NetworkKind.laptopHotspot;
  }
  if (gateway == null && ownPlatform == 'android' && peerHost != null) {
    return NetworkKind.phoneHotspot;
  }
  return NetworkKind.wifi;
}

/// Finds the paired device on the current network and keeps checking.
///
/// Tries, fastest first: the last good address, the gateway, then a scan of
/// the local /24 networks. Only a device with the paired certificate and ID
/// counts as a match.
class DiscoveryService {
  DiscoveryService({
    required this.store,
    required this.network,
    required this.prober,
    required this.ownPlatform,
    this.port = 47820,
    this.lookingInterval = const Duration(seconds: 5),
    this.connectedInterval = const Duration(seconds: 30),
  });

  final PairedDeviceStore store;
  final NetworkInfoProvider network;
  final Prober prober;
  final String ownPlatform;
  final int port;
  final Duration lookingInterval;
  final Duration connectedInterval;

  final _controller = StreamController<DiscoveryState>.broadcast();
  DiscoveryState _state = const DiscoveryState.offline();
  Timer? _timer;
  bool _running = false;

  /// How long the last discovery round took (for diagnostics).
  Duration lastRoundDuration = Duration.zero;
  bool _checking = false;
  final List<(String, int)> _hints = [];

  /// Emits only when the state changes.
  Stream<DiscoveryState> get states => _controller.stream;
  DiscoveryState get state => _state;

  void start() {
    if (_running) return;
    _running = true;
    unawaited(checkNow());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    stop();
    await _controller.close();
  }

  /// A verified hello said the paired device is at [host]:[hintPort]. Tried
  /// first in the next round, which starts now unless already connected.
  void hint(String host, int hintPort) {
    if (!_running || _state.status == DiscoveryStatus.connected) return;
    if (!_hints.contains((host, hintPort))) _hints.add((host, hintPort));
    if (!_checking) unawaited(checkNow());
  }

  /// Runs one discovery round now (also used when the network changes).
  Future<DiscoveryState> checkNow() async {
    if (_checking) return _state;
    _checking = true;
    final stopwatch = Stopwatch()..start();
    try {
      _set(await findOnce());
      lastRoundDuration = stopwatch.elapsed;
    } finally {
      _checking = false;
    }
    if (_running &&
        _hints.isNotEmpty &&
        _state.status != DiscoveryStatus.connected) {
      return checkNow(); // A hello arrived during the round.
    }
    if (_running) {
      _timer?.cancel();
      _timer = Timer(
        _state.status == DiscoveryStatus.connected
            ? connectedInterval
            : lookingInterval,
        () => unawaited(checkNow()),
      );
    }
    return _state;
  }

  void _set(DiscoveryState next) {
    if (next == _state) return;
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  /// One discovery round. Public so tests can call it without timers.
  Future<DiscoveryState> findOnce() async {
    final paired = await store.load();
    final local = await network.localAddresses();
    if (local.isEmpty) return const DiscoveryState.offline();
    final gateway = await network.gateway();
    if (paired == null) return DiscoveryState.looking(NetworkKind.unknown);

    final tried = <String>{...local};

    DiscoveryState connected(String host, int p, DeviceInfo info) {
      return DiscoveryState.connected(
        address: '$host:$p',
        peer: info,
        network: classifyNetwork(
          gateway: gateway,
          ownAddresses: local,
          ownPlatform: ownPlatform,
          peerHost: host,
          peerPlatform: info.platform,
        ),
      );
    }

    // 0. Addresses that just announced themselves by UDP.
    final hints = List.of(_hints);
    _hints.clear();
    for (final (host, hintPort) in hints) {
      if (!tried.add(host)) continue;
      final info = await prober(host, hintPort);
      if (info != null) return connected(host, hintPort, info);
    }

    // 1. Last good address.
    final last = _parseAddress(paired);
    if (last != null) {
      tried.add(last.$1);
      final info = await prober(last.$1, last.$2);
      if (info != null) return connected(last.$1, last.$2, info);
    }

    // 2. The gateway (covers both hotspot layouts).
    if (gateway != null && !tried.contains(gateway)) {
      tried.add(gateway);
      final info = await prober(gateway, port);
      if (info != null) return connected(gateway, port, info);
    }

    // 3. Scan each local /24.
    for (final address in local) {
      final hit = await scanSubnet(
        localAddress: address,
        port: port,
        probe: prober,
        skip: tried,
      );
      if (hit != null) return connected(hit.host, hit.port, hit.info);
    }

    return DiscoveryState.looking(
      classifyNetwork(
        gateway: gateway,
        ownAddresses: local,
        ownPlatform: ownPlatform,
      ),
    );
  }

  (String, int)? _parseAddress(PairedDevice d) {
    final a = d.lastAddress;
    if (a == null) return null;
    final parts = a.split(':');
    final p = parts.length > 1 ? int.tryParse(parts[1]) : port;
    return p == null ? null : (parts.first, p);
  }
}
