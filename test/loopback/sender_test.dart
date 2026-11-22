import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/core/client/client.dart';
import 'package:personal_sender/core/history/history_store.dart';
import 'package:personal_sender/core/identity/identity.dart';
import 'package:personal_sender/core/pairing/pairing.dart';
import 'package:personal_sender/core/protocol/models.dart';
import 'package:personal_sender/core/server/server.dart';
import 'package:personal_sender/core/storage/key_value_store.dart';
import 'package:personal_sender/core/storage/paired_store.dart';
import 'package:personal_sender/core/transfer/receiver.dart';
import 'package:personal_sender/core/transfer/sender.dart';

void main() {
  const secret =
      'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12';
  late Directory tmp;
  late DeviceIdentity identity;
  late CoreServer server;
  late HistoryStore history;
  late Sender sender;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ps_sender_');
    identity = await DeviceIdentity.loadOrCreate(
      MemorySecretStore(),
      name: 'L',
    );
    final paired = PairedDeviceStore(MemorySecretStore());
    await paired.save(
      const PairedDevice(
        id: 'p',
        name: 'Phone',
        fingerprint: 'f',
        secret: secret,
      ),
    );
    server = CoreServer(
      identity: identity,
      info: DeviceInfo(
        id: identity.id,
        name: 'L',
        platform: 'windows',
        appVersion: '0.1.0',
      ),
      receiver: Receiver(Directory('${tmp.path}/inbox')),
      pairedStore: paired,
      pairing: PairingManager(),
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    history = HistoryStore(MemoryKeyValueStore());
    sender = Sender(deviceId: 'phone-id', history: history);
  });

  tearDown(() async {
    await server.stop();
    await tmp.delete(recursive: true);
  });

  CoreClient client({String? withSecret = secret, int? port}) => CoreClient(
    host: '127.0.0.1',
    port: port ?? server.port,
    pinnedFingerprint: identity.fingerprint,
    secret: withSecret,
  );

  Future<File> file(String name, int size) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(List.filled(size, 7));
    return f;
  }

  test('a batch of photos arrives and is recorded as one row', () async {
    final files = [await file('a.jpg', 100), await file('b.jpg', 250)];
    final progress = <int>[];
    final outcome = await sender.sendFiles(
      client: client(),
      peerName: 'Laptop',
      files: files,
      onProgress: (i, s, t) => progress.add(i),
    );

    expect(outcome.ok, isTrue);
    expect(outcome.item.title, '2 photos');
    expect(outcome.item.kind, HistoryKind.photo);
    expect(outcome.item.count, 2);
    expect(outcome.item.totalBytes, 350);
    expect(outcome.item.direction, HistoryDirection.sent);
    expect(progress.toSet(), {0, 1});
    expect(File('${tmp.path}/inbox/a.jpg').lengthSync(), 100);
    expect(File('${tmp.path}/inbox/b.jpg').lengthSync(), 250);
    expect(history.items.single.id, outcome.item.id);
  });

  test('unreachable laptop becomes a Not sent row, without throwing', () async {
    final files = [await file('c.pdf', 10)];
    final outcome = await sender.sendFiles(
      client: client(port: 1),
      peerName: 'Laptop',
      files: files,
    );
    expect(outcome.ok, isFalse);
    expect(outcome.item.status, HistoryStatus.failed);
    expect(outcome.item.failureReason, 'Not reachable');
    expect(outcome.item.title, 'c.pdf');
    expect(history.items, hasLength(1));
  });

  test('wrong secret becomes Not paired', () async {
    final files = [await file('d.jpg', 10)];
    final outcome = await sender.sendFiles(
      client: client(withSecret: 'ff' * 32),
      peerName: 'Laptop',
      files: files,
    );
    expect(outcome.item.status, HistoryStatus.failed);
    expect(outcome.item.failureReason, 'Not paired');
  });
}
