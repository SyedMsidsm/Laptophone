import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

import '../storage/paired_store.dart';
import 'gateway.dart';

final _log = Logger('UdpAnnounce');

/// UDP port for hellos (same number as the HTTPS port, different protocol).
const udpPort = 47820;

/// Multicast group both apps join.
const multicastGroup = '239.255.77.77';

/// A small "I'm here" message: device ID and HTTPS port, signed with the
/// shared secret so only the paired device's hellos are believed.
class Hello {
  const Hello({required this.id, required this.port});

  final String id;
  final int port;

  static List<int> encode(Hello hello, String secret) => utf8.encode(
    jsonEncode({
      'v': 1,
      'id': hello.id,
      'port': hello.port,
      'mac': _mac(hello.id, hello.port, secret),
    }),
  );

  /// Returns the hello if the bytes are well formed and the signature
  /// matches [secret]; null otherwise.
  static Hello? decode(List<int> bytes, String secret) {
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, Object?> || json['v'] != 1) return null;
      final id = json['id']! as String;
      final port = json['port']! as int;
      final mac = json['mac']! as String;
      if (!_equal(mac, _mac(id, port, secret))) return null;
      return Hello(id: id, port: port);
    } on Object {
      return null;
    }
  }

  static String _mac(String id, int port, String secret) => Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode('personalsender-hello|$id|$port')).toString();

  static bool _equal(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Called when a verified hello from the paired device arrives.
typedef HelloCallback = void Function(String host, int port);

/// Sends hellos by multicast and broadcast and listens for the paired
/// device's hellos. Speeds discovery up; everything still works without it.
class UdpAnnouncer {
  UdpAnnouncer({
    required this.selfId,
    required this.servicePort,
    required this.store,
    required this.network,
    required this.onHello,
    this.listenPort = udpPort,
    this.interval = const Duration(seconds: 3),
    this.destinations,
  });

  /// This device's ID (our own hellos are ignored).
  final String selfId;

  /// The HTTPS port we announce.
  final int servicePort;
  final PairedDeviceStore store;
  final NetworkInfoProvider network;
  final HelloCallback onHello;
  final int listenPort;
  final Duration interval;

  /// Where to send hellos. Null means multicast plus every broadcast address.
  /// Tests pass loopback targets.
  final List<(InternetAddress, int)>? destinations;

  RawDatagramSocket? _socket;
  Timer? _timer;

  bool get isRunning => _socket != null;

  Future<void> start() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      listenPort,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;
    socket.multicastLoopback = false;
    _joinMulticast(socket);
    socket.listen(_onEvent, onError: (Object e) => _log.warning('UDP: $e'));
    _socket = socket;
    _timer = Timer.periodic(interval, (_) => unawaited(_sendHello()));
    unawaited(_sendHello());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }

  void _joinMulticast(RawDatagramSocket socket) {
    final group = InternetAddress(multicastGroup);
    try {
      socket.joinMulticast(group);
    } on Object catch (e) {
      _log.info('Default multicast join failed: $e');
    }
    // Also join on every real adapter: the default one may be a virtual one.
    unawaited(() async {
      try {
        for (final i in await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        )) {
          if (isVirtualInterface(i.name)) continue;
          try {
            socket.joinMulticast(group, i);
          } on Object {
            // That adapter cannot do multicast; others may.
          }
        }
      } on Object catch (e) {
        _log.info('Multicast join per adapter failed: $e');
      }
    }());
  }

  Future<void> _onEvent(RawSocketEvent event) async {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;
    final paired = await store.load();
    if (paired == null) return;
    final hello = Hello.decode(datagram.data, paired.secret);
    if (hello == null || hello.id == selfId || hello.id != paired.id) return;
    onHello(datagram.address.address, hello.port);
  }

  Future<void> _sendHello() async {
    final socket = _socket;
    if (socket == null) return;
    final paired = await store.load();
    if (paired == null) return; // Nobody to talk to before pairing.
    final bytes = Hello.encode(
      Hello(id: selfId, port: servicePort),
      paired.secret,
    );
    for (final (address, port) in await _targets()) {
      try {
        socket.send(bytes, address, port);
      } on Object catch (e) {
        _log.fine('Send to $address failed: $e');
      }
    }
  }

  Future<List<(InternetAddress, int)>> _targets() async {
    final fixed = destinations;
    if (fixed != null) return fixed;
    final targets = <(InternetAddress, int)>[
      (InternetAddress(multicastGroup), udpPort),
      (InternetAddress('255.255.255.255'), udpPort),
    ];
    for (final local in await network.localAddresses()) {
      final p = local.split('.');
      if (p.length == 4) {
        targets.add((InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'), udpPort));
      }
    }
    return targets;
  }
}
