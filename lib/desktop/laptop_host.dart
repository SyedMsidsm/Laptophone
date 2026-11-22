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
import '../shared_ui/sending_progress.dart';
import 'known_folders.dart';
import 'main_window.dart';
import 'pair_window.dart';

/// Connects the laptop's main window to the real services: the HTTPS server,
/// discovery, UDP hellos, history and sending.
class LaptopHost extends StatefulWidget {
  const LaptopHost({
    super.key,
    required this.identity,
    required this.pairedStore,
    required this.history,
  });

  final DeviceIdentity identity;
  final PairedDeviceStore pairedStore;
  final HistoryStore history;

  @override
  State<LaptopHost> createState() => _LaptopHostState();
}

class _LaptopHostState extends State<LaptopHost> {
  final _pairing = PairingManager();
  final _pairedEvents = StreamController<PairedDevice>.broadcast();
  CoreServer? _server;
  DiscoveryService? _discovery;
  UdpAnnouncer? _udp;
  StreamSubscription<DiscoveryState>? _discSub;
  StreamSubscription<void>? _historySub;
  Directory? _inbox;

  PairedDevice? _paired;
  DiscoveryState _state = const DiscoveryState.offline();
  SendingProgress? _sending;
  List<HistoryItem> _activity = const [];

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
      final inbox = await personalSenderInbox();
      _inbox = inbox;
      final server = CoreServer(
        identity: widget.identity,
        pairedStore: widget.pairedStore,
        pairing: _pairing,
        onPaired: (d) {
          _pairedEvents.add(d);
          _refreshPaired();
        },
        info: DeviceInfo(
          id: widget.identity.id,
          name: widget.identity.name,
          platform: 'windows',
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
      ownPlatform: 'windows',
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
    _discovery?.dispose();
    _server?.stop();
    _pairedEvents.close();
    super.dispose();
  }

  Future<void> _refreshHistory() async {
    final items = widget.history.items.take(100).toList();
    if (mounted) setState(() => _activity = items);
  }

  Future<void> _refreshPaired() async {
    final paired = await widget.pairedStore.load();
    if (mounted) setState(() => _paired = paired);
    unawaited(_discovery?.checkNow());
  }

  Future<void> _onReceived(String path) async {
    final name = path.split(RegExp(r'[\\/]')).last;
    final size = await File(path).length();
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
        peerName: _paired?.name ?? 'Phone',
      ),
    );
  }

  Future<void> _choose() async {
    final picked = await FilePicker.pickFiles();
    final paths = [
      for (final f in picked)
        if (f.path != null) f.path!,
    ];
    if (paths.isNotEmpty) await _send(paths);
  }

  Future<void> _send(List<String> paths) async {
    if (_sending != null) return;
    final paired = _paired;
    if (paired == null) return;
    final files = [for (final p in paths) File(p)];

    // Until the outbox exists (Task 19) a send needs the phone to be reachable.
    final address = _state.address;
    final sender = Sender(
      deviceId: widget.identity.id,
      history: widget.history,
    );
    if (address == null) {
      final client = CoreClient(
        host: '0.0.0.0',
        port: 1,
        pinnedFingerprint: paired.fingerprint,
        secret: paired.secret,
      );
      await sender.sendFiles(
        client: client,
        peerName: paired.name,
        files: files,
      );
      unawaited(_discovery?.checkNow());
      return;
    }

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
      unawaited(_discovery?.checkNow());
    }
  }

  Future<void> _openPairing() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PairPhoneScreen(
          identity: widget.identity,
          pairing: _pairing,
          pairedEvents: _pairedEvents.stream,
        ),
      ),
    );
    await _refreshPaired();
  }

  Future<void> _openFolder() async {
    final dir = _inbox ?? await personalSenderInbox();
    await dir.create(recursive: true);
    await Process.start('explorer.exe', [dir.path]);
  }

  LinkState get _link => switch (_state.status) {
    DiscoveryStatus.connected => LinkState.connected,
    DiscoveryStatus.looking => LinkState.looking,
    DiscoveryStatus.offline => LinkState.offline,
  };

  @override
  Widget build(BuildContext context) {
    return MainWindow(
      paired: _paired != null,
      link: _link,
      network: _state.network,
      peerName: _paired?.name ?? 'your phone',
      activity: _activity,
      sending: _sending,
      onFiles: _send,
      onChoose: _choose,
      onPair: _openPairing,
      onOpenFolder: _openFolder,
      onTryAgain: () => _discovery?.checkNow(),
    );
  }
}
