import 'dart:io';

import 'package:uuid/uuid.dart';

import '../client/client.dart';
import '../history/history_store.dart';
import '../protocol/models.dart';

/// The result of sending one batch.
class SendOutcome {
  const SendOutcome({required this.item, required this.files});

  /// The history row that was saved for this batch.
  final HistoryItem item;
  final List<File> files;

  bool get ok => item.status == HistoryStatus.done;
}

/// Sends a batch of files to the paired device and records it in history.
class Sender {
  Sender({required this.deviceId, required this.history});

  final String deviceId;
  final HistoryStore history;

  /// Sends [files] through [client]. Never throws: a failure becomes a
  /// "Not sent" history row with a short reason.
  ///
  /// [onProgress] gets the index of the current file and its byte counts.
  Future<SendOutcome> sendFiles({
    required CoreClient client,
    required String peerName,
    required List<File> files,
    void Function(int index, int sent, int total)? onProgress,
  }) async {
    final names = [for (final f in files) _baseName(f.path)];
    final (title, kind) = describeBatch(names);
    var totalBytes = 0;
    final metas = <FileMeta>[];
    for (var i = 0; i < files.length; i++) {
      final size = await files[i].length();
      totalBytes += size;
      metas.add(
        FileMeta(
          name: names[i],
          size: size,
          mime: 'application/octet-stream',
          modified: await files[i].lastModified(),
        ),
      );
    }

    HistoryItem make(HistoryStatus status, [String? reason]) => HistoryItem(
      id: const Uuid().v4(),
      direction: HistoryDirection.sent,
      status: status,
      kind: kind,
      title: title,
      count: files.length,
      totalBytes: totalBytes,
      time: DateTime.now(),
      peerName: peerName,
      failureReason: reason,
    );

    try {
      final id = await client.sendOffer(
        TransferOffer(senderId: deviceId, files: metas),
      );
      for (var i = 0; i < files.length; i++) {
        await client.sendFile(
          id,
          i,
          files[i],
          onProgress: (sent, total) => onProgress?.call(i, sent, total),
        );
      }
      final done = make(HistoryStatus.done);
      await history.add(done);
      return SendOutcome(item: done, files: files);
    } on ClientException catch (e) {
      final failed = make(HistoryStatus.failed, reasonFor(e));
      await history.add(failed);
      return SendOutcome(item: failed, files: files);
    } on Object {
      final failed = make(HistoryStatus.failed, 'Connection lost');
      await history.add(failed);
      return SendOutcome(item: failed, files: files);
    }
  }

  /// A short reason for the "Not sent" row.
  static String reasonFor(ClientException e) {
    final code = e.statusCode;
    if (code == 401) return 'Not paired';
    if (code != null) return 'Laptop refused it';
    if (e.message.contains('Certificate')) return 'Wrong device';
    return 'Not reachable';
  }

  static String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;
}
