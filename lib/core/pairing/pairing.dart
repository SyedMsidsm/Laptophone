import 'dart:math';

/// The device we are paired with: who it is, which certificate to pin, the
/// shared secret every request carries, and where we last reached it.
class PairedDevice {
  const PairedDevice({
    required this.id,
    required this.name,
    required this.fingerprint,
    required this.secret,
    this.lastAddress,
  });

  final String id;
  final String name;

  /// SHA-256 of the peer's certificate (lowercase hex).
  final String fingerprint;

  /// 32 random bytes as 64 lowercase hex characters.
  final String secret;

  /// `host:port` of the last successful connection.
  final String? lastAddress;

  PairedDevice withLastAddress(String address) => PairedDevice(
    id: id,
    name: name,
    fingerprint: fingerprint,
    secret: secret,
    lastAddress: address,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'fingerprint': fingerprint,
    'secret': secret,
    'lastAddress': lastAddress,
  };

  factory PairedDevice.fromJson(Map<String, Object?> json) => PairedDevice(
    id: json['id']! as String,
    name: json['name']! as String,
    fingerprint: json['fingerprint']! as String,
    secret: json['secret']! as String,
    lastAddress: json['lastAddress'] as String?,
  );
}

/// Body of `POST /api/v1/pair`, sent by the device that scanned the code.
class PairRequest {
  const PairRequest({
    required this.code,
    required this.deviceId,
    required this.deviceName,
    required this.fingerprint,
  });

  final String code;
  final String deviceId;
  final String deviceName;
  final String fingerprint;

  Map<String, Object?> toJson() => {
    'code': code,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'fingerprint': fingerprint,
  };

  factory PairRequest.fromJson(Map<String, Object?> json) => PairRequest(
    code: json['code']! as String,
    deviceId: json['deviceId']! as String,
    deviceName: json['deviceName']! as String,
    fingerprint: json['fingerprint']! as String,
  );
}

/// Reply to a successful pairing: the host's identity and the new secret.
class PairResponse {
  const PairResponse({
    required this.deviceId,
    required this.deviceName,
    required this.fingerprint,
    required this.secret,
  });

  final String deviceId;
  final String deviceName;
  final String fingerprint;
  final String secret;

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'fingerprint': fingerprint,
    'secret': secret,
  };

  factory PairResponse.fromJson(Map<String, Object?> json) => PairResponse(
    deviceId: json['deviceId']! as String,
    deviceName: json['deviceName']! as String,
    fingerprint: json['fingerprint']! as String,
    secret: json['secret']! as String,
  );
}

/// Why a pairing attempt was refused.
class PairingException implements Exception {
  PairingException(this.message);
  final String message;
  @override
  String toString() => 'PairingException: $message';
}

/// Hands out single-use six-digit codes on the host (the laptop).
class PairingManager {
  PairingManager({
    this.ttl = const Duration(minutes: 5),
    this.maxAttempts = 5,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final Duration ttl;
  final int maxAttempts;
  final DateTime Function() _clock;
  final Random _random;

  String? _code;
  DateTime? _expires;
  int _failures = 0;

  bool get isActive =>
      _code != null && _clock().isBefore(_expires ?? DateTime(0));

  /// Starts pairing and returns a fresh six-digit code, replacing any old one.
  String startPairing() {
    _code = _random.nextInt(1000000).toString().padLeft(6, '0');
    _expires = _clock().add(ttl);
    _failures = 0;
    return _code!;
  }

  void cancel() {
    _code = null;
    _expires = null;
  }

  /// Checks [code] and, if right, uses it up. Throws [PairingException]
  /// otherwise. Five wrong guesses cancel the code.
  void consume(String code) {
    if (!isActive) throw PairingException('No pairing in progress');
    if (!_constantTimeEquals(code, _code!)) {
      _failures++;
      if (_failures >= maxAttempts) cancel();
      throw PairingException('Wrong code');
    }
    cancel();
  }

  /// A new 32-byte secret as 64 hex characters.
  String newSecret() => List.generate(
    32,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Constant-time comparison for secrets.
bool secretsEqual(String a, String b) => _constantTimeEquals(a, b);
