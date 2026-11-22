import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart';

import '../protocol/models.dart';
import 'file_names.dart';

final _log = Logger('Receiver');

/// Thrown for bad requests (unknown transfer, bad index, size mismatch).
class ReceiveException implements Exception {
  ReceiveException(this.message, {this.statusCode = 400});
  final String message;
  final int statusCode;
  @override
  String toString() => 'ReceiveException($statusCode): $message';
}

/// Accepts offers and streams file bytes to disk.
///
/// Bytes go to `<name>.part`; the file is renamed to its final name only when
/// the received byte count equals the announced size. Anything else deletes
/// the `.part` file, so a partial file never has its final name.
class Receiver {
  Receiver(this.saveDir);

  final Directory saveDir;
  final Map<String, TransferOffer> _offers = {};
  final Map<String, Set<int>> _started = {};
  final _rand = Random.secure();

  /// Registers an offer and returns its transfer ID.
  String handleOffer(TransferOffer offer) {
    if (offer.files.isEmpty) throw ReceiveException('Offer has no files');
    for (final f in offer.files) {
      if (f.size < 0) throw ReceiveException('Negative file size');
    }
    final id = List.generate(
      16,
      (_) => _rand.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _offers[id] = offer;
    _started[id] = {};
    return id;
  }

  /// Streams one file to disk. Returns the final path.
  Future<String> receiveFile(
    String transferId,
    int index,
    Stream<List<int>> bytes, {
    void Function(int received, int total)? onProgress,
  }) async {
    final offer = _offers[transferId];
    if (offer == null) {
      throw ReceiveException('Unknown transfer', statusCode: 404);
    }
    if (index < 0 || index >= offer.files.length) {
      throw ReceiveException('Bad file index', statusCode: 404);
    }
    if (!_started[transferId]!.add(index)) {
      throw ReceiveException('File already received', statusCode: 409);
    }
    final meta = offer.files[index];

    await saveDir.create(recursive: true);
    final sep = Platform.pathSeparator;
    final safe = safeFileName(meta.name);
    final finalName = uniqueName(
      safe,
      (n) =>
          File('${saveDir.path}$sep$n').existsSync() ||
          File('${saveDir.path}$sep$n.part').existsSync(),
    );
    final finalFile = File('${saveDir.path}$sep$finalName');
    final partFile = File('${finalFile.path}.part');

    final sink = partFile.openWrite();
    var count = 0;
    try {
      await for (final chunk in bytes) {
        count += chunk.length;
        if (count > meta.size) {
          throw ReceiveException('More bytes than announced');
        }
        sink.add(chunk);
        onProgress?.call(count, meta.size);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      await _deleteQuietly(partFile);
      _log.warning('Upload of "$safe" failed after $count bytes: $e');
      if (e is ReceiveException) rethrow;
      throw ReceiveException('Upload interrupted');
    }

    if (count != meta.size) {
      await _deleteQuietly(partFile);
      throw ReceiveException('Expected ${meta.size} bytes, got $count');
    }
    await partFile.rename(finalFile.path);
    return finalFile.path;
  }

  Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
