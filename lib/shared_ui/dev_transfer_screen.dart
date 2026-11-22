import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/client/client.dart';
import '../core/identity/identity.dart';
import '../core/pairing/pairing.dart';
import '../core/protocol/models.dart';
import '../core/server/server.dart';
import '../core/storage/paired_store.dart';
import '../core/transfer/receiver.dart';
import '../desktop/pair_window.dart';
import '../phone/pair_screen.dart';

/// Dev screen, same on phone and laptop (replaced by the real screens in
/// Task 7): it listens, can show a pairing code, can pair by typed address
/// and code, and can send a picked file to the paired device.
class DevTransferScreen extends StatefulWidget {
  const DevTransferScreen({
    super.key,
    required this.identity,
    required this.pairedStore,
    required this.platform,
    required this.resolveInbox,
    this.pickType = FileType.any,
    this.pickLabel = 'Pick file',
  });

  final DeviceIdentity identity;
  final PairedDeviceStore pairedStore;
  final String platform;
  final Future<Directory> Function() resolveInbox;
  final FileType pickType;
  final String pickLabel;

  @override
  State<DevTransferScreen> createState() => _DevTransferScreenState();
}

class _DevTransferScreenState extends State<DevTransferScreen> {
  final _address = TextEditingController();
  final _pairedEvents = StreamController<PairedDevice>.broadcast();
  final _pairing = PairingManager();
  CoreServer? _server;
  String _listening = 'Starting…';
  String _inbox = '';
  String _pairedLine = 'Not paired';
  String _sendStatus = 'Pair first, then pick a file.';
  final List<String> _received = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
    _refreshPaired();
  }

  Future<void> _refreshPaired() async {
    final d = await widget.pairedStore.load();
    if (!mounted) return;
    setState(() {
      _pairedLine = d == null
          ? 'Not paired'
          : 'Paired with ${d.name}'
                '${d.lastAddress == null ? '' : ' (last ${d.lastAddress})'}';
      if (d?.lastAddress != null && _address.text.isEmpty) {
        _address.text = d!.lastAddress!;
      }
    });
  }

  Future<void> _start() async {
    try {
      final dir = await widget.resolveInbox();
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
          platform: widget.platform,
          appVersion: '0.1.0',
        ),
        receiver: Receiver(
          dir,
          onReceived: (path) {
            if (mounted) setState(() => _received.insert(0, path));
          },
        ),
      );
      await server.start();
      final addrs = <String>[];
      for (final i in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        for (final a in i.addresses) {
          addrs.add('${a.address}:$defaultPort  (${i.name})');
        }
      }
      if (!mounted) return;
      setState(() {
        _server = server;
        _inbox = dir.path;
        _listening = 'Listening on\n${addrs.join('\n')}';
      });
    } catch (e) {
      if (mounted) setState(() => _listening = 'Could not start: $e');
    }
  }

  @override
  void dispose() {
    _server?.stop();
    _address.dispose();
    _pairedEvents.close();
    super.dispose();
  }

  (String, int)? _parseAddress() {
    final parts = _address.text.trim().split(':');
    if (parts.first.isEmpty) return null;
    final port = parts.length > 1
        ? int.tryParse(parts[1]) ?? defaultPort
        : defaultPort;
    return (parts.first, port);
  }

  Future<void> _openPairing() async {
    if (widget.platform == 'android') {
      final paired = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              PairScreen(identity: widget.identity, store: widget.pairedStore),
        ),
      );
      if (paired == true) await _refreshPaired();
    } else {
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
  }

  Future<void> _pickAndSend() async {
    final paired = await widget.pairedStore.load();
    final addr = _parseAddress();
    if (paired == null) {
      setState(() => _sendStatus = 'Not paired yet.');
      return;
    }
    if (addr == null) {
      setState(() => _sendStatus = 'Enter the other device address first.');
      return;
    }
    final picked = await FilePicker.pickFiles(type: widget.pickType);
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null) return;

    setState(() {
      _busy = true;
      _sendStatus = 'Connecting…';
    });
    try {
      final file = File(path);
      final size = await file.length();
      final name = path.split(RegExp(r'[\\/]')).last;
      final client = CoreClient(
        host: addr.$1,
        port: addr.$2,
        pinnedFingerprint: paired.fingerprint,
        secret: paired.secret,
      );
      final id = await client.sendOffer(
        TransferOffer(
          senderId: widget.identity.id,
          files: [
            FileMeta(
              name: name,
              size: size,
              mime: 'application/octet-stream',
              modified: await file.lastModified(),
            ),
          ],
        ),
      );
      await widget.pairedStore.updateLastAddress('${addr.$1}:${addr.$2}');
      await client.sendFile(
        id,
        0,
        file,
        onProgress: (sent, total) {
          if (mounted) {
            setState(() => _sendStatus = 'Sending $name: $sent / $total bytes');
          }
        },
      );
      if (mounted) setState(() => _sendStatus = 'Sent $name ($size bytes).');
    } catch (e) {
      if (mounted) setState(() => _sendStatus = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('PersonalSender')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Receive', style: text.titleLarge),
          const SizedBox(height: 8),
          SelectableText(_listening),
          if (_inbox.isNotEmpty) SelectableText('Saving to: $_inbox'),
          for (final r in _received.take(5)) SelectableText('Received: $r'),
          const SizedBox(height: 24),
          Text('Pairing', style: text.titleLarge),
          const SizedBox(height: 8),
          Text(_pairedLine),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _openPairing,
            child: Text(
              widget.platform == 'android' ? 'Pair with laptop' : 'Pair phone',
            ),
          ),
          TextButton(
            onPressed: () async {
              await widget.pairedStore.clear();
              await _refreshPaired();
            },
            child: const Text('Forget pairing (dev only)'),
          ),
          const SizedBox(height: 24),
          Text('Send', style: text.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Other device address',
              hintText: '192.168.1.20:47820',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _pickAndSend,
            child: Text(widget.pickLabel),
          ),
          const SizedBox(height: 16),
          Text(_sendStatus),
        ],
      ),
    );
  }
}
