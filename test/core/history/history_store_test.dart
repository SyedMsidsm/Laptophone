import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/core/history/history_store.dart';
import 'package:personal_sender/core/storage/key_value_store.dart';

HistoryItem item(
  String id, {
  DateTime? time,
  HistoryDirection direction = HistoryDirection.sent,
  HistoryStatus status = HistoryStatus.done,
}) => HistoryItem(
  id: id,
  direction: direction,
  status: status,
  kind: HistoryKind.photo,
  title: 'IMG_$id.jpg',
  count: 1,
  totalBytes: 2400000,
  time: time ?? DateTime(2026, 11, 22, 15, 30),
  peerName: 'Laptop',
);

void main() {
  test('starts empty', () async {
    final s = HistoryStore(MemoryKeyValueStore());
    await s.load();
    expect(s.items, isEmpty);
  });

  test('newest first, and survives a restart', () async {
    final backing = MemoryKeyValueStore();
    final s = HistoryStore(backing);
    await s.add(item('1'));
    await s.add(item('2', direction: HistoryDirection.received));

    final again = HistoryStore(backing);
    await again.load();
    expect(again.items.map((i) => i.id), ['2', '1']);
    expect(again.items.first.direction, HistoryDirection.received);
    expect(again.items.first.title, 'IMG_2.jpg');
    expect(again.items.first.time, DateTime(2026, 11, 22, 15, 30));
  });

  test('adding the same id replaces it instead of duplicating', () async {
    final s = HistoryStore(MemoryKeyValueStore());
    await s.add(item('1'));
    await s.add(item('1', status: HistoryStatus.failed));
    expect(s.items, hasLength(1));
    expect(s.items.single.status, HistoryStatus.failed);
  });

  test('update changes status and reason, and is saved', () async {
    final backing = MemoryKeyValueStore();
    final s = HistoryStore(backing);
    await s.add(item('1', status: HistoryStatus.waiting));
    await s.update(
      '1',
      status: HistoryStatus.failed,
      failureReason: 'No Wi-Fi',
    );
    await s.update('missing', status: HistoryStatus.done); // no-op

    final again = HistoryStore(backing);
    await again.load();
    expect(again.items.single.status, HistoryStatus.failed);
    expect(again.items.single.failureReason, 'No Wi-Fi');
  });

  test('today() keeps only the same calendar day', () async {
    final s = HistoryStore(MemoryKeyValueStore());
    final now = DateTime(2026, 11, 22, 18);
    await s.add(item('old', time: DateTime(2026, 11, 21, 23, 59)));
    await s.add(item('a', time: DateTime(2026, 11, 22, 0, 1)));
    await s.add(item('b', time: DateTime(2026, 11, 22, 17)));
    expect(s.today(now).map((i) => i.id), ['b', 'a']);
  });

  test('keeps at most maxItems, dropping the oldest', () async {
    final s = HistoryStore(MemoryKeyValueStore(), maxItems: 3);
    for (var i = 1; i <= 5; i++) {
      await s.add(item('$i'));
    }
    expect(s.items.map((i) => i.id), ['5', '4', '3']);
  });

  test('damaged saved data gives an empty history, not a crash', () async {
    final backing = MemoryKeyValueStore()..data['history.items'] = '{not json';
    final s = HistoryStore(backing);
    await s.load();
    expect(s.items, isEmpty);
    await s.add(item('1')); // and it keeps working
    expect(s.items, hasLength(1));
  });

  test('changes stream fires after each change', () async {
    final s = HistoryStore(MemoryKeyValueStore());
    var events = 0;
    s.changes.listen((_) => events++);
    await s.add(item('1'));
    await s.update('1', status: HistoryStatus.failed);
    await Future<void>.delayed(Duration.zero);
    expect(events, 2);
  });

  group('describeBatch', () {
    test('one file keeps its name', () {
      expect(describeBatch(['IMG_1.jpg']), ('IMG_1.jpg', HistoryKind.photo));
      expect(describeBatch(['clip.MOV']), ('clip.MOV', HistoryKind.video));
      expect(describeBatch(['a.apk']), ('a.apk', HistoryKind.file));
    });

    test('batches are summarised', () {
      expect(describeBatch(['a.jpg', 'b.PNG', 'c.heic', 'd.jpeg']), (
        '4 photos',
        HistoryKind.photo,
      ));
      expect(describeBatch(['a.mp4', 'b.mov']), (
        '2 videos',
        HistoryKind.video,
      ));
      expect(describeBatch(['a.jpg', 'b.mp4']), ('2 files', HistoryKind.file));
      expect(describeBatch(['a.pdf', 'b']), ('2 files', HistoryKind.file));
    });
  });
}
