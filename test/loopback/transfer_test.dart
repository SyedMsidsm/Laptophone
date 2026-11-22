import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/core/client/client.dart';
import 'package:personal_sender/core/identity/identity.dart';
import 'package:personal_sender/core/pairing/pairing.dart';
import 'package:personal_sender/core/storage/paired_store.dart';
import 'package:personal_sender/core/protocol/models.dart';
import 'package:personal_sender/core/server/server.dart';
import 'package:personal_sender/core/transfer/receiver.dart';

Future<String> _sha(File f) async =>
    (await sha256.bind(f.openRead()).first).toString();

/// Writes [bytes] of pseudo-random-ish data without holding it in memory.
Future<void> _generate(File f, int bytes) async {
  final sink = f.openWrite();
  final chunk = List<int>.generate(1 << 20, (i) => (i * 31 + 7) & 0xff);
  var left = bytes;
  while (left > 0) {
    final n = left < chunk.length ? left : chunk.length;
    sink.add(n == chunk.length ? chunk : chunk.sublist(0, n));
    left -= n;
    // Vary content between chunks so the hash isn't trivially periodic.
    chunk[left % chunk.length] = left & 0xff;
  }
  await sink.close();
}

FileMeta _meta(File f, String name, int size) => FileMeta(
  name: name,
  size: size,
  mime: 'application/octet-stream',
  modified: f.lastModifiedSync(),
);

void main() {
  late Directory tmp;
  late Directory inbox;
  late CoreServer server;
  late PairedDeviceStore pairedStore;
  const secret =
      'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12';
  late CoreClient client;
  late DeviceIdentity identity;

  setUp(() async {
    identity = await DeviceIdentity.loadOrCreate(
      MemorySecretStore(),
      name: 'Test laptop',
    );
    tmp = await Directory.systemTemp.createTemp('ps_loopback_');
    inbox = Directory('${tmp.path}/inbox');
    pairedStore = PairedDeviceStore(MemorySecretStore());
    await pairedStore.save(
      const PairedDevice(
        id: 'client',
        name: 'Phone',
        fingerprint: 'f',
        secret: secret,
      ),
    );
    server = CoreServer(
      identity: identity,
      pairedStore: pairedStore,
      pairing: PairingManager(),
      info: const DeviceInfo(
        id: 'srv',
        name: 'Test laptop',
        platform: 'windows',
        appVersion: '0.1.0',
      ),
      receiver: Receiver(inbox),
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    client = CoreClient(
      host: '127.0.0.1',
      port: server.port,
      pinnedFingerprint: identity.fingerprint,
      secret: secret,
    );
  });

  tearDown(() async {
    await server.stop();
    await tmp.delete(recursive: true);
  });

  test('GET /info returns the device info', () async {
    final info = await client.getInfo();
    expect(info.name, 'Test laptop');
    expect(info.id, 'srv');
  });

  test('small file arrives with matching SHA-256', () async {
    final src = File('${tmp.path}/photo.jpg');
    await _generate(src, 123457);
    final id = await client.sendOffer(
      TransferOffer(senderId: 'c', files: [_meta(src, 'photo.jpg', 123457)]),
    );
    final progress = <int>[];
    await client.sendFile(id, 0, src, onProgress: (s, t) => progress.add(s));

    final dst = File('${inbox.path}/photo.jpg');
    expect(await _sha(dst), await _sha(src));
    expect(progress.last, 123457);
    expect(inbox.listSync().whereType<File>().length, 1); // no .part left
  });

  test('duplicate and hostile names are made safe', () async {
    final src = File('${tmp.path}/a.bin');
    await _generate(src, 10);
    final offer = TransferOffer(
      senderId: 'c',
      files: [
        _meta(src, 'a.bin', 10),
        _meta(src, 'a.bin', 10),
        _meta(src, r'..\..\evil.exe', 10),
      ],
    );
    final id = await client.sendOffer(offer);
    for (var i = 0; i < 3; i++) {
      await client.sendFile(id, i, src);
    }
    final names = inbox.listSync().map((e) => e.uri.pathSegments.last).toSet();
    expect(names, {'a.bin', 'a (1).bin', 'evil.exe'});
  });

  test('unknown transfer gets 404', () async {
    final src = File('${tmp.path}/x.bin')..writeAsBytesSync([1, 2, 3]);
    expect(
      () => client.sendFile('nope', 0, src),
      throwsA(
        isA<ClientException>().having((e) => e.statusCode, 'status', 404),
      ),
    );
  });

  test('short upload leaves no file under the final name', () async {
    final src = File('${tmp.path}/big.bin');
    await _generate(src, 1000);
    final id = await client.sendOffer(
      TransferOffer(senderId: 'c', files: [_meta(src, 'big.bin', 1000)]),
    );

    // Promise 1000 bytes, send 400, then close the socket.
    final socket = await SecureSocket.connect(
      '127.0.0.1',
      server.port,
      onBadCertificate: (_) => true,
    );
    socket.write(
      'PUT /api/v1/transfers/$id/files/0 HTTP/1.1\r\n'
      'Host: 127.0.0.1\r\nAuthorization: Bearer $secret\r\n'
      'Content-Length: 1000\r\n\r\n',
    );
    socket.add(List.filled(400, 1));
    await socket.flush();
    await socket.close();
    socket.destroy();

    // Give the server a moment to notice and clean up.
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!inbox.existsSync() || inbox.listSync().isEmpty) break;
    }
    final left = inbox.existsSync() ? inbox.listSync() : <FileSystemEntity>[];
    expect(left, isEmpty, reason: 'no final or .part file should remain');
  });

  test(
    '500 MB file streams with matching SHA-256 and bounded memory',
    () async {
      const size = 500 * 1024 * 1024;
      final src = File('${tmp.path}/huge.bin');
      await _generate(src, size);
      final srcSha = await _sha(src);

      final id = await client.sendOffer(
        TransferOffer(senderId: 'c', files: [_meta(src, 'huge.bin', size)]),
      );

      final baseline = ProcessInfo.currentRss;
      var peak = baseline;
      final timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
      });
      await client.sendFile(id, 0, src);
      timer.cancel();

      final growthMb = (peak - baseline) / (1024 * 1024);
      // ignore: avoid_print
      print(
        'Peak RSS growth during 500 MB send: ${growthMb.toStringAsFixed(1)} MB',
      );
      expect(growthMb, lessThan(100));
      expect(await _sha(File('${inbox.path}/huge.bin')), srcSha);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
