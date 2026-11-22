import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/identity/identity.dart';
import '../core/pairing/pair_flow.dart';
import '../core/storage/paired_store.dart';

/// Phone "Enter code instead": address and 6-digit code typed by hand.
/// Pops with `true` once paired.
class EnterCodeScreen extends StatefulWidget {
  const EnterCodeScreen({
    super.key,
    required this.identity,
    required this.store,
  });

  final DeviceIdentity identity;
  final PairedDeviceStore store;

  @override
  State<EnterCodeScreen> createState() => _EnterCodeScreenState();
}

class _EnterCodeScreenState extends State<EnterCodeScreen> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _addressError;
  String? _codeError;

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final digits = _code.text.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _addressError = _address.text.trim().isEmpty
          ? 'Type the address shown on the laptop.'
          : null;
      _codeError = digits.length != 6 ? 'The code has 6 digits.' : null;
    });
    if (_addressError != null || _codeError != null) return;

    setState(() => _busy = true);
    final outcome = await pairManually(
      address: _address.text,
      code: digits,
      identity: widget.identity,
      store: widget.store,
    );
    if (!mounted) return;
    if (outcome.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      if (outcome.error == wrongCodeError) {
        _codeError =
            "That code didn't work. Check the 6 digits on the laptop and "
            'try again.';
      } else {
        _addressError =
            "Couldn't reach the laptop. Check the address and that both are "
            'on the same Wi-Fi or hotspot.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: const Text('Enter code')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('On the laptop, choose Pair phone, then Can\'t scan?'),
          const SizedBox(height: 16),
          TextField(
            controller: _address,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Address',
              hintText: '192.168.1.6:47820',
              errorText: _addressError,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
              LengthLimitingTextInputFormatter(7),
              _GroupedCodeFormatter(),
            ],
            decoration: InputDecoration(
              labelText: 'Code',
              hintText: '482 913',
              errorText: _codeError,
              errorMaxLines: 3,
              enabledBorder: _codeError == null
                  ? null
                  : OutlineInputBorder(borderSide: BorderSide(color: danger)),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _pair,
            child: Text(_busy ? 'Pairing…' : 'Pair'),
          ),
        ],
      ),
    );
  }
}

/// Shows digits grouped as "482 913".
class _GroupedCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > 6 ? digits.substring(0, 6) : digits;
    final grouped = capped.length > 3
        ? '${capped.substring(0, 3)} ${capped.substring(3)}'
        : capped;
    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: grouped.length),
    );
  }
}
