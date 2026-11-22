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
  final _code = TextEditingController();
  final _pairing = PairingManager();
  CoreServer? _server;
  String _listening = 'Starting…';
  String _inbox = '';
  String _pairedLine = 'Not paired';
  String _hostCode = '';
  String _pairStatus = '';
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
        onPaired: (_) {
          _refreshPaired();
          if (mounted) setState(() => _hostCode = '');
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
    _code.dispose();
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

  void _showCode() {
    setState(() => _hostCode = _pairing.startPairing());
  }

  Future<void> _pair() async {
    final addr = _parseAddress();
    if (addr == null || _code.text.trim().length != 6) {
      setState(() => _pairStatus = 'Enter the address and the 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _pairStatus = 'Pairing…';
    });
    try {
      // Dev only: read the fingerprint from the connection. Task 7 takes it
      // from the QR code instead.
      final pin = await CoreClient.probeFingerprint(addr.$1, addr.$2);
      final response =
          await CoreClient(
            host: addr.$1,
            port: addr.$2,
            pinnedFingerprint: pin,
          ).pair(
            PairRequest(
              code: _code.text.trim(),
              deviceId: widget.identity.id,
              deviceName: widget.identity.name,
              fingerprint: widget.identity.fingerprint,
            ),
          );
      await widget.pairedStore.save(
        PairedDevice(
          id: response.deviceId,
          name: response.deviceName,
          fingerprint: response.fingerprint,
          secret: response.secret,
          lastAddress: '${addr.$1}:${addr.$2}',
        ),
      );
      _code.clear();
      await _refreshPaired();
      if (mounted) setState(() => _pairStatus = 'Paired.');
    } catch (e) {
      if (mounted) setState(() => _pairStatus = 'Pairing failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
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
            onPressed: _showCode,
            child: const Text('Show pairing code (on the host)'),
          ),
          if (_hostCode.isNotEmpty)
            SelectableText('Code: $_hostCode', style: text.headlineMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Code from the other device',
            ),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _pair,
            child: const Text('Pair with address below'),
          ),
          if (_pairStatus.isNotEmpty) Text(_pairStatus),
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
