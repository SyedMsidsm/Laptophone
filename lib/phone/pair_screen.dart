import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/identity/identity.dart';
import '../core/pairing/pair_flow.dart';
import '../core/pairing/pairing_qr.dart';
import '../core/storage/paired_store.dart';
import 'enter_code_screen.dart';

/// Phone "Pair" screen. The camera permission is asked only when the user
/// taps Scan code. Pops with `true` once paired.
class PairScreen extends StatelessWidget {
  const PairScreen({super.key, required this.identity, required this.store});

  final DeviceIdentity identity;
  final PairedDeviceStore store;

  Future<void> _done(BuildContext context, Future<Object?> route) async {
    final paired = await route;
    if (paired == true && context.mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pair with laptop')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'On the laptop, open PersonalSender and choose Pair phone. '
              'Then scan the code it shows.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => _done(
                context,
                Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) =>
                        ScanScreen(identity: identity, store: store),
                  ),
                ),
              ),
              child: const Text('Scan code'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _done(
                context,
                Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) =>
                        EnterCodeScreen(identity: identity, store: store),
                  ),
                ),
              ),
              child: const Text('Enter code instead'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Camera view that reads the laptop's QR code and pairs.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.identity, required this.store});

  final DeviceIdentity identity;
  final PairedDeviceStore store;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handling = false;
  String _status = 'The camera is used only to read this code.';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    for (final barcode in capture.barcodes) {
      final qr = PairingQr.tryParse(barcode.rawValue ?? '');
      if (qr == null) continue;
      _handling = true;
      setState(() => _status = 'Pairing with ${qr.deviceName}…');
      final outcome = await pairFromQr(
        qr: qr,
        identity: widget.identity,
        store: widget.store,
      );
      if (!mounted) return;
      if (outcome.ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _handling = false;
          _status = outcome.error == wrongCodeError
              ? 'That code has expired. Show a new one on the laptop.'
              : "Couldn't reach the laptop. Check both are on the same "
                    'Wi-Fi or hotspot.';
        });
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan code')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'Camera access is off. Allow it in Settings, or '
                              'go back and choose Enter code instead.'
                        : 'The camera could not start. Go back and choose '
                              'Enter code instead.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: Text(_status)),
        ],
      ),
    );
  }
}
