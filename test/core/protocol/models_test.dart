import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/core/protocol/models.dart';

Map<String, Object?> _wire(Map<String, Object?> j) =>
    jsonDecode(jsonEncode(j)) as Map<String, Object?>;

void main() {
  final file = FileMeta(
    name: 'photo.jpg',
    size: 1234567890123,
    mime: 'image/jpeg',
    modified: DateTime.utc(2026, 11, 22, 8, 30, 15, 123),
  );

  test('DeviceInfo round-trips', () {
    const d = DeviceInfo(
      id: 'abc',
      name: 'S24',
      platform: 'android',
      appVersion: '0.1.0',
    );
    expect(DeviceInfo.fromJson(_wire(d.toJson())), d);
  });

  test('FileMeta round-trips', () {
    expect(FileMeta.fromJson(_wire(file.toJson())), file);
  });

  test('TransferOffer round-trips', () {
    final o = TransferOffer(senderId: 'abc', files: [file, file]);
    expect(TransferOffer.fromJson(_wire(o.toJson())), o);
  });

  test('TextMessage round-trips', () {
    const t = TextMessage(text: 'https://example.com/ü?a=1', isUrl: true);
    expect(TextMessage.fromJson(_wire(t.toJson())), t);
  });
}
