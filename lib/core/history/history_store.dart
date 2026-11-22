import 'dart:async';
import 'dart:convert';

import '../storage/key_value_store.dart';

enum HistoryDirection { sent, received }

/// done = finished, waiting = queued for when the other device is reachable,
/// failed = not sent (see [HistoryItem.failureReason]).
enum HistoryStatus { done, waiting, failed }

/// What a batch mostly is, for the icon and the title ("4 photos").
enum HistoryKind { photo, video, file, text }

/// One row in the activity list: a single file or a whole batch.
class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.direction,
    required this.status,
    required this.kind,
    required this.title,
    required this.count,
    required this.totalBytes,
    required this.time,
    required this.peerName,
    this.failureReason,
  });

  final String id;
  final HistoryDirection direction;
  final HistoryStatus status;
  final HistoryKind kind;

  /// The file name, or "4 photos" for a batch.
  final String title;
  final int count;
  final int totalBytes;
  final DateTime time;

  /// The other device's name at the time.
  final String peerName;
  final String? failureReason;

  HistoryItem copyWith({
    HistoryStatus? status,
    String? failureReason,
    DateTime? time,
  }) => HistoryItem(
    id: id,
    direction: direction,
    status: status ?? this.status,
    kind: kind,
    title: title,
    count: count,
    totalBytes: totalBytes,
    time: time ?? this.time,
    peerName: peerName,
    failureReason: failureReason ?? this.failureReason,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'direction': direction.name,
    'status': status.name,
    'kind': kind.name,
    'title': title,
    'count': count,
    'totalBytes': totalBytes,
    'time': time.toUtc().toIso8601String(),
    'peerName': peerName,
    'failureReason': failureReason,
  };

  factory HistoryItem.fromJson(Map<String, Object?> json) => HistoryItem(
    id: json['id']! as String,
    direction: HistoryDirection.values.byName(json['direction']! as String),
    status: HistoryStatus.values.byName(json['status']! as String),
    kind: HistoryKind.values.byName(json['kind']! as String),
    title: json['title']! as String,
    count: json['count']! as int,
    totalBytes: json['totalBytes']! as int,
    time: DateTime.parse(json['time']! as String).toLocal(),
    peerName: json['peerName']! as String,
    failureReason: json['failureReason'] as String?,
  );
}

/// Recent transfers, newest first, saved across restarts.
class HistoryStore {
  HistoryStore(this._storage, {this.maxItems = 500});

  final KeyValueStore _storage;
  final int maxItems;
  static const _key = 'history.items';

  List<HistoryItem> _items = [];
  bool _loaded = false;
  final _changes = StreamController<void>.broadcast();

  /// Fires after every change.
  Stream<void> get changes => _changes.stream;

  /// Newest first.
  List<HistoryItem> get items => List.unmodifiable(_items);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await _storage.read(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<Object?>;
      _items = [
        for (final e in list) HistoryItem.fromJson(e! as Map<String, Object?>),
      ];
    } on Object {
      _items = []; // A damaged history must never stop the app.
    }
  }

  Future<void> add(HistoryItem item) async {
    await load();
    _items = [item, ..._items.where((i) => i.id != item.id)];
    if (_items.length > maxItems) _items = _items.sublist(0, maxItems);
    await _save();
  }

  /// Changes an existing item (for example waiting to done). No-op if absent.
  Future<void> update(
    String id, {
    HistoryStatus? status,
    String? failureReason,
    DateTime? time,
  }) async {
    await load();
    final i = _items.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _items = [..._items]
      ..[i] = _items[i].copyWith(
        status: status,
        failureReason: failureReason,
        time: time,
      );
    await _save();
  }

  Future<void> clear() async {
    _items = [];
    await _save();
  }

  /// Items from the same calendar day as [now].
  List<HistoryItem> today(DateTime now) => [
    for (final i in _items)
      if (i.time.year == now.year &&
          i.time.month == now.month &&
          i.time.day == now.day)
        i,
  ];

  Future<void> _save() async {
    await _storage.write(
      _key,
      jsonEncode([for (final i in _items) i.toJson()]),
    );
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}

const _photoExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'heic',
  'heif',
  'bmp',
};
const _videoExtensions = {'mp4', 'mov', 'mkv', 'webm', 'avi', '3gp', 'm4v'};

HistoryKind kindOfFileName(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  if (_photoExtensions.contains(ext)) return HistoryKind.photo;
  if (_videoExtensions.contains(ext)) return HistoryKind.video;
  return HistoryKind.file;
}

/// Title and kind for a batch: the name for one file, otherwise "4 photos",
/// "2 videos" or "3 files" (mixed batches count as files).
(String, HistoryKind) describeBatch(List<String> fileNames) {
  if (fileNames.length == 1) {
    return (fileNames.first, kindOfFileName(fileNames.first));
  }
  final kinds = {for (final n in fileNames) kindOfFileName(n)};
  final n = fileNames.length;
  if (kinds.length == 1 && kinds.first == HistoryKind.photo) {
    return ('$n photos', HistoryKind.photo);
  }
  if (kinds.length == 1 && kinds.first == HistoryKind.video) {
    return ('$n videos', HistoryKind.video);
  }
  return ('$n files', HistoryKind.file);
}
