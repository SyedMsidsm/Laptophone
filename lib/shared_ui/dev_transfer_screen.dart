import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/client/client.dart';
import '../core/protocol/models.dart';
import '../core/server/server.dart';
import '../core/transfer/receiver.dart';

/// Task 4 dev screen, same on phone and laptop: it listens for incoming
/// files AND can send a picked file to a typed address.
class DevTransferScreen extends StatefulWidget {
  const DevTransferScreen({
    super.key,
    required this.deviceName,
    required this.platform,
    required this.resolveInbox,
    this.pickType = FileType.any,
    this.pickLabel = 'Pick file',
  });

  final String deviceName;
  final String platform;
  final Future<Directory> Function() resolveInbox;
  final FileType pickType;
  final String pickLabel;

  @override
  State<DevTransferScreen> createState() => _DevTransferScreenState();
}

class _DevTransferScreenState extends State<DevTransferScreen> {
  final _address = TextEditingController();
  CoreServer? _server;
  String _listening = 'Starting…';
  String _inbox = '';
  String _sendStatus = 'Enter the other device address, then pick a file.';
  final List<String> _received = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final dir = await widget.resolveInbox();
      final server = CoreServer(
        info: DeviceInfo(
          id: 'dev-${widget.platform}',
          name: widget.deviceName,
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
    super.dispose();
  }

  Future<void> _pickAndSend() async {
    final parts = _address.text.trim().split(':');
    final host = parts.first;
    final port = parts.length > 1
        ? int.tryParse(parts[1]) ?? defaultPort
        : defaultPort;
    if (host.isEmpty) {
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
      final client = CoreClient(host: host, port: port);
      final id = await client.sendOffer(
        TransferOffer(
          senderId: 'dev-${widget.platform}',
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
          const SizedBox(height: 32),
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
