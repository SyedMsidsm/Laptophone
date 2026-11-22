import 'dart:convert';

/// What the laptop's QR code carries: who it is, where to reach it, the
/// certificate to pin and the one-time code.
class PairingQr {
  const PairingQr({
    required this.deviceId,
    required this.deviceName,
    required this.addresses,
    required this.port,
    required this.fingerprint,
    required this.code,
  });

  static const version = 1;

  final String deviceId;
  final String deviceName;

  /// IPv4 addresses the laptop is reachable on; the phone tries each.
  final List<String> addresses;
  final int port;
  final String fingerprint;
  final String code;

  String encode() => jsonEncode({
    'v': version,
    'id': deviceId,
    'name': deviceName,
    'ips': addresses,
    'port': port,
    'fp': fingerprint,
    'code': code,
  });

  /// Parses a scanned string. Returns null if it is not a PersonalSender code.
  static PairingQr? tryParse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?> || json['v'] != version) return null;
      final ips = [
        for (final ip in json['ips']! as List<Object?>) ip! as String,
      ];
      final code = json['code']! as String;
      final fp = json['fp']! as String;
      if (ips.isEmpty || !RegExp(r'^\d{6}$').hasMatch(code)) return null;
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fp)) return null;
      return PairingQr(
        deviceId: json['id']! as String,
        deviceName: json['name']! as String,
        addresses: ips,
        port: json['port']! as int,
        fingerprint: fp,
        code: code,
      );
    } on Object {
      return null;
    }
  }
}
