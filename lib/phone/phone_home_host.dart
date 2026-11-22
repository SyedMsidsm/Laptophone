import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../core/client/client.dart';
import '../core/discovery/discovery.dart';
import '../core/discovery/prober.dart';
import '../core/discovery/udp_announce.dart';
import '../core/history/history_store.dart';
import '../core/identity/identity.dart';
import '../core/pairing/pairing.dart';
import '../core/protocol/models.dart';
import '../core/server/server.dart';
import '../core/storage/paired_store.dart';
import '../core/transfer/receiver.dart';
import '../core/transfer/sender.dart';
import '../shared_ui/format.dart';
import '../shared_ui/link_indicator.dart';
import '../shared_ui/platform_network_info.dart';
import 'home_screen.dart';
import 'multicast_lock.dart';
import 'pair_screen.dart';

/// Connects the phone's Home screen to the real services: the HTTPS server,
/// discovery, UDP hellos, history and sending.
class PhoneHomeHost extends StatefulWidget {
  const PhoneHomeHost({
    super.key,
    required this.identity,
    required this.pairedStore,
    required this.history,
  });

  final DeviceIdentity identity;
  final PairedDeviceStore pairedStore;
  final HistoryStore history;

  @override
  State<PhoneHomeHost> createState() => _PhoneHomeHostState();
}

class _PhoneHomeHostState extends State<PhoneHomeHost> {
  final _pairing = PairingManager();
  final _multicast = const MulticastLock();
  CoreServer? _server;
  DiscoveryService? _discovery;
  UdpAnnouncer? _udp;
  StreamSubscription<DiscoveryState>? _discSub;
  StreamSubscription<void>? _historySub;

  PairedDevice? _paired;
  DiscoveryState _state = const DiscoveryState.offline();
  SendingProgress? _sending;
  List<HistoryItem> _today = const [];

  @override
  void initState() {
    super.initState();
    _historySub = widget.history.changes.listen((_) => _refreshHistory());
    unawaited(_start());
  }

  Future<void> _start() async {
    await widget.history.load();
    await _refreshHistory();
    await _refreshPaired();

    try {
      final inbox = Directory('${Directory.systemTemp.path}/inbox');
      final server = CoreServer(
        identity: widget.identity,
        pairedStore: widget.pairedStore,
        pairing: _pairing,
        onPaired: (_) => _refreshPaired(),
        info: DeviceInfo(
          id: widget.identity.id,
          name: widget.identity.name,
          platform: 'android',
          appVersion: '0.1.0',
        ),
        receiver: Receiver(inbox, onReceived: _onReceived),
      );
      await server.start();
      _server = server;
    } on Object catch (e) {
      debugPrint('Server could not start: $e');
    }

    final discovery = DiscoveryService(
      store: widget.pairedStore,
      network: PlatformNetworkInfo(),
      prober: storeProber(widget.pairedStore),
      ownPlatform: 'android',
    );
    _discovery = discovery;
    _discSub = discovery.states.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    discovery.start();

    final udp = UdpAnnouncer(
      selfId: widget.identity.id,
      servicePort: defaultPort,
      store: widget.pairedStore,
      network: PlatformNetworkInfo(),
      onHello: (host, port) => discovery.hint(host, port),
    );
    _udp = udp;
    await _multicast.acquire();
    try {
      await udp.start();
    } on Object catch (e) {
      debugPrint('UDP could not start: $e');
    }
  }

  @override
  void dispose() {
    _historySub?.cancel();
    _discSub?.cancel();
    _udp?.stop();
    _multicast.release();
    _discovery?.dispose();
    _server?.stop();
    super.dispose();
  }

  Future<void> _refreshHistory() async {
    final today = widget.history.today(DateTime.now());
    if (mounted) setState(() => _today = today);
  }

  Future<void> _refreshPaired() async {
    final paired = await widget.pairedStore.load();
    if (mounted) setState(() => _paired = paired);
    unawaited(_discovery?.checkNow());
  }

  Future<void> _onReceived(String path) async {
    final file = File(path);
    final name = path.split(RegExp(r'[\\/]')).last;
    final size = await file.length();
    await widget.history.add(
      HistoryItem(
        id: const Uuid().v4(),
        direction: HistoryDirection.received,
        status: HistoryStatus.done,
        kind: kindOfFileName(name),
        title: name,
        count: 1,
        totalBytes: size,
        time: DateTime.now(),
        peerName: _paired?.name ?? 'Laptop',
      ),
    );
  }

  Future<void> _pick(FileType type) async {
    final picked = await FilePicker.pickFiles(type: type);
    final files = [
      for (final f in picked)
        if (f.path != null) File(f.path!),
    ];
    if (files.isEmpty) return;
    await _send(files);
  }

  Future<void> _send(List<File> files) async {
    final paired = _paired;
    final address = _state.address;
    if (paired == null || address == null) return;
    final parts = address.split(':');
    final client = CoreClient(
      host: parts.first,
      port: int.parse(parts.last),
      pinnedFingerprint: paired.fingerprint,
      secret: paired.secret,
    );

    var total = 0;
    final sizes = <int>[];
    for (final f in files) {
      final len = await f.length();
      sizes.add(len);
      total += len;
    }
    final sender = Sender(
      deviceId: widget.identity.id,
      history: widget.history,
    );

    if (mounted) {
      setState(
        () => _sending = SendingProgress(
          label: 'Sending 1 of ${files.length}',
          fraction: 0,
        ),
      );
    }
    final outcome = await sender.sendFiles(
      client: client,
      peerName: paired.name,
      files: files,
      onProgress: (index, sent, fileTotal) {
        var done = 0;
        for (var i = 0; i < index; i++) {
          done += sizes[i];
        }
        done += sent;
        if (!mounted) return;
        setState(
          () => _sending = SendingProgress(
            label:
                'Sending ${index + 1} of ${files.length} · '
                '${formatBytes(done)} of ${formatBytes(total)}',
            fraction: total == 0 ? 0 : done / total,
          ),
        );
      },
    );
    if (mounted) setState(() => _sending = null);
    if (outcome.ok) {
      await widget.pairedStore.updateLastAddress(address);
    } else {
      // A failed send usually means the laptop went away: look again now.
      unawaited(_discovery?.checkNow());
    }
  }

  Future<void> _openPairing() async {
    final paired = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            PairScreen(identity: widget.identity, store: widget.pairedStore),
      ),
    );
    if (paired == true) await _refreshPaired();
  }

  LinkState get _link => switch (_state.status) {
    DiscoveryStatus.connected => LinkState.connected,
    DiscoveryStatus.looking => LinkState.looking,
    DiscoveryStatus.offline => LinkState.offline,
  };

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
      paired: _paired != null,
      link: _link,
      network: _state.network,
      peerName: _paired?.name ?? 'Laptop',
      today: _today,
      sending: _sending,
      onSendMedia: () => _pick(FileType.media),
      onSendFiles: () => _pick(FileType.any),
      onTryAgain: () => _discovery?.checkNow(),
      onPair: _openPairing,
    );
  }
}
