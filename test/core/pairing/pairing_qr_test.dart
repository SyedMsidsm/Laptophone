import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/core/pairing/pairing_qr.dart';

void main() {
  final qr = PairingQr(
    deviceId: 'id-1',
    deviceName: 'Laptop',
    addresses: const ['192.168.1.6', '10.0.0.2'],
    port: 47820,
    fingerprint: 'ab' * 32,
    code: '482913',
  );

  test('round-trips through the QR string', () {
    final parsed = PairingQr.tryParse(qr.encode())!;
    expect(parsed.deviceId, 'id-1');
    expect(parsed.deviceName, 'Laptop');
    expect(parsed.addresses, ['192.168.1.6', '10.0.0.2']);
    expect(parsed.port, 47820);
    expect(parsed.fingerprint, 'ab' * 32);
    expect(parsed.code, '482913');
  });

  test('rejects things that are not PersonalSender codes', () {
    expect(PairingQr.tryParse('https://example.com'), isNull);
    expect(PairingQr.tryParse('{"v":2}'), isNull);
    expect(PairingQr.tryParse('{}'), isNull);
    expect(PairingQr.tryParse(''), isNull);
  });

  test('rejects a bad code or fingerprint', () {
    final badCode = qr.encode().replaceAll('482913', '48291');
    expect(PairingQr.tryParse(badCode), isNull);
    final badFp = qr.encode().replaceAll('ab' * 32, 'zz' * 32);
    expect(PairingQr.tryParse(badFp), isNull);
  });
}
