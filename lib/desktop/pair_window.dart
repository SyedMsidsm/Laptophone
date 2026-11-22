import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/identity/identity.dart';
import '../core/pairing/pairing.dart';
import '../core/pairing/pairing_qr.dart';
import '../core/server/server.dart';

/// Laptop "Pair phone" screen: a QR code plus "Can't scan?" address and code.
/// The code is made when the screen opens and dies when it closes.
class PairPhoneScreen extends StatefulWidget {
  const PairPhoneScreen({
    super.key,
    required this.identity,
    required this.pairing,
    required this.pairedEvents,
    this.port = defaultPort,
  });

  final DeviceIdentity identity;
  final PairingManager pairing;

  /// Fires when a device finishes pairing with this laptop.
  final Stream<PairedDevice> pairedEvents;
  final int port;

  @override
  State<PairPhoneScreen> createState() => _PairPhoneScreenState();
}

class _PairPhoneScreenState extends State<PairPhoneScreen> {
  String? _code;
  List<String> _addresses = const [];
  PairedDevice? _paired;
  StreamSubscription<PairedDevice>? _sub;

  @override
  void initState() {
    super.initState();
    _code = widget.pairing.startPairing();
    _sub = widget.pairedEvents.listen((d) {
      if (mounted) setState(() => _paired = d);
    });
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    final found = <String>[];
    for (final i in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      // Skip virtual adapters (WSL, Hyper-V, Docker): the phone can't see them.
      if (i.name.contains('vEthernet') || i.name.contains('WSL')) continue;
      for (final a in i.addresses) {
        if (!a.isLoopback && !a.address.startsWith('169.254.')) {
          found.add(a.address);
        }
      }
    }
    if (mounted) setState(() => _addresses = found);
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.pairing.cancel(); // The code dies when the window closes.
    super.dispose();
  }

  String get _groupedCode {
    final c = _code ?? '';
    return c.length == 6 ? '${c.substring(0, 3)} ${c.substring(3)}' : c;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final code = _code;
    return Scaffold(
      appBar: AppBar(title: const Text('Pair phone')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_paired != null) ...[
            Text('Paired with ${_paired!.name}', style: text.titleLarge),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ] else if (code != null && _addresses.isNotEmpty) ...[
            Text('1. Open PersonalSender on your phone', style: text.bodyLarge),
            Text('2. Tap Pair, then Scan code', style: text.bodyLarge),
            const SizedBox(height: 16),
            Center(
              child: Container(
                color: const Color(0xFFFFFFFF),
                padding: const EdgeInsets.all(16),
                child: QrImageView(
                  data: PairingQr(
                    deviceId: widget.identity.id,
                    deviceName: widget.identity.name,
                    addresses: _addresses,
                    port: widget.port,
                    fingerprint: widget.identity.fingerprint,
                    code: code,
                  ).encode(),
                  size: 224,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text("Can't scan?", style: text.titleMedium),
            const SizedBox(height: 4),
            const Text('On the phone choose Enter code instead, then type:'),
            const SizedBox(height: 8),
            for (final a in _addresses)
              SelectableText('Address  $a:${widget.port}'),
            SelectableText('Code  $_groupedCode', style: text.headlineSmall),
          ] else if (_addresses.isEmpty && code != null)
            const Text('Looking for a network connection…'),
        ],
      ),
    );
  }
}
