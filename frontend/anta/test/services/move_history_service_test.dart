import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/services/move_history_service.dart';
import 'package:anta/services/move_history_store.dart';

/// The history counts undo units — a batch is one, however many items it
/// moved — so a batch is kept or dropped whole and its Undo can always
/// restore every item it moved.
void main() {
  late InMemoryMoveHistoryStore store;
  late MoveHistoryService service;

  setUp(() {
    store = InMemoryMoveHistoryStore();
    service = MoveHistoryService(store: store);
  });
  tearDown(() => service.dispose());

  List<MoveHistoryItem> items(int count, String prefix) => [
    for (var i = 0; i < count; i++)
      (
        itemType: MoveItemType.note,
        itemId: '$prefix$i',
        itemName: '$prefix $i',
        sourceParentId: 'from',
        sourceParentName: 'From',
      ),
  ];

  void addBatch(int count, String batchId) => service.addMoves(
    items(count, batchId),
    targetParentId: 'to',
    targetParentName: 'To',
    batchId: batchId,
  );

  String addSingle(String id) => service.addMove(
    itemType: MoveItemType.note,
    itemId: id,
    itemName: id,
    sourceParentId: 'from',
    sourceParentName: 'From',
    targetParentId: 'to',
    targetParentName: 'To',
  );

  List<String> batch(String batchId) => [
    for (final entry in service.history)
      if (entry.batchId == batchId) entry.id,
  ];

  test('a 25-item batch is one unit and is kept whole', () async {
    addBatch(25, 'big');
    for (var i = 0; i < AppConstants.moveHistoryMaxUnits - 1; i++) {
      addSingle('single$i');
    }

    expect(batch('big'), hasLength(25));
    expect(service.history, hasLength(25 + 19));
    expect(
      (await store.loadAll()).where((e) => e.batchId == 'big'),
      hasLength(25),
    );
  });

  test('the unit past the cap is dropped whole, never cut', () async {
    addBatch(25, 'big');
    for (var i = 0; i < AppConstants.moveHistoryMaxUnits; i++) {
      addSingle('single$i');
    }

    expect(batch('big'), isEmpty);
    expect(service.history, hasLength(AppConstants.moveHistoryMaxUnits));
    expect(await store.loadAll(), hasLength(AppConstants.moveHistoryMaxUnits));
  });

  test('the badge counts items, not units', () {
    addBatch(25, 'big');
    addSingle('one');
    expect(service.undoableCount, 26);
  });

  test('marking a whole unit undone announces once', () async {
    addBatch(25, 'big');
    final counts = <int>[];
    final sub = service.changes.listen(counts.add);

    service.markAllUndone(batch('big'));
    await pumpEventQueue();
    await sub.cancel();

    expect(counts, [0]);
    expect(service.history.every((e) => e.isUndone), isTrue);
    expect((await store.loadAll()).every((e) => e.isUndone), isTrue);
  });

  group('retainUndoUnits', () {
    List<MoveHistoryEntry> entries(List<(String id, String? batch)> spec) => [
      for (final (id, batch) in spec)
        MoveHistoryEntry(
          id: id,
          itemType: MoveItemType.note,
          itemId: id,
          itemName: id,
          sourceParentId: null,
          sourceParentName: null,
          targetParentId: null,
          targetParentName: null,
          timestamp: DateTime(2026),
          batchId: batch,
        ),
    ];

    List<String> ids(List<MoveHistoryEntry> list) => [
      for (final e in list) e.id,
    ];

    test('the entry ceiling drops older units whole', () {
      final all = entries([
        ('a1', 'a'),
        ('a2', 'a'),
        ('b1', 'b'),
        ('b2', 'b'),
        ('b3', 'b'),
        ('c', null),
      ]);
      expect(ids(retainUndoUnits(all, maxUnits: 20, maxEntries: 4)), [
        'a1',
        'a2',
      ]);
      expect(ids(retainUndoUnits(all, maxUnits: 20, maxEntries: 5)), [
        'a1',
        'a2',
        'b1',
        'b2',
        'b3',
      ]);
    });

    test('the newest unit is kept whole even past the ceiling', () {
      final all = entries([('a1', 'a'), ('a2', 'a'), ('a3', 'a'), ('b', null)]);
      expect(ids(retainUndoUnits(all, maxUnits: 20, maxEntries: 2)), [
        'a1',
        'a2',
        'a3',
      ]);
    });
  });
}
