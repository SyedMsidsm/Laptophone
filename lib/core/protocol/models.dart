/// Protocol v1 models. Pure Dart, JSON round-trip safe.
library;

/// Identity returned by `GET /api/v1/info`.
final class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.appVersion,
  });

  final String id;
  final String name;
  final String platform;
  final String appVersion;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'appVersion': appVersion,
  };

  factory DeviceInfo.fromJson(Map<String, Object?> json) => DeviceInfo(
    id: json['id']! as String,
    name: json['name']! as String,
    platform: json['platform']! as String,
    appVersion: json['appVersion']! as String,
  );

  @override
  bool operator ==(Object other) =>
      other is DeviceInfo &&
      other.id == id &&
      other.name == name &&
      other.platform == platform &&
      other.appVersion == appVersion;

  @override
  int get hashCode => Object.hash(id, name, platform, appVersion);
}

/// One file in an offer.
final class FileMeta {
  const FileMeta({
    required this.name,
    required this.size,
    required this.mime,
    required this.modified,
  });

  final String name;
  final int size;
  final String mime;
  final DateTime modified;

  Map<String, Object?> toJson() => {
    'name': name,
    'size': size,
    'mime': mime,
    'modified': modified.toUtc().toIso8601String(),
  };

  factory FileMeta.fromJson(Map<String, Object?> json) => FileMeta(
    name: json['name']! as String,
    size: json['size']! as int,
    mime: json['mime']! as String,
    modified: DateTime.parse(json['modified']! as String),
  );

  @override
  bool operator ==(Object other) =>
      other is FileMeta &&
      other.name == name &&
      other.size == size &&
      other.mime == mime &&
      other.modified.isAtSameMomentAs(modified);

  @override
  int get hashCode =>
      Object.hash(name, size, mime, modified.millisecondsSinceEpoch);
}

/// A batch of files the sender wants to deliver. Sent before any bytes.
final class TransferOffer {
  const TransferOffer({required this.senderId, required this.files});

  final String senderId;
  final List<FileMeta> files;

  Map<String, Object?> toJson() => {
    'senderId': senderId,
    'files': [for (final f in files) f.toJson()],
  };

  factory TransferOffer.fromJson(Map<String, Object?> json) => TransferOffer(
    senderId: json['senderId']! as String,
    files: [
      for (final f in json['files']! as List<Object?>)
        FileMeta.fromJson(f! as Map<String, Object?>),
    ],
  );

  @override
  bool operator ==(Object other) {
    if (other is! TransferOffer ||
        other.senderId != senderId ||
        other.files.length != files.length) {
      return false;
    }
    for (var i = 0; i < files.length; i++) {
      if (other.files[i] != files[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(senderId, Object.hashAll(files));
}

/// Text or a link sent via `POST /api/v1/text`.
final class TextMessage {
  const TextMessage({required this.text, required this.isUrl});

  final String text;
  final bool isUrl;

  Map<String, Object?> toJson() => {'text': text, 'isUrl': isUrl};

  factory TextMessage.fromJson(Map<String, Object?> json) =>
      TextMessage(text: json['text']! as String, isUrl: json['isUrl']! as bool);

  @override
  bool operator ==(Object other) =>
      other is TextMessage && other.text == text && other.isUrl == isUrl;

  @override
  int get hashCode => Object.hash(text, isUrl);
}
