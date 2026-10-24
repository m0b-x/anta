// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/counter.dart';
import 'package:anta/services/counter_service.dart';

import '../database/support/db_test_support.dart';

/// Guards what the debounced flush writes, now that every write stamps an HLC
/// (**v43**): a write that changes nothing would read as a change once devices
/// merge, and a write landing after a delete would bring the counter's values
/// back.
void main() {
  late AppDatabase db;
  late CounterService service;

  setUp(() async {
    db = await openTestDatabase();
    service = await CounterService.forTesting(db);
  });
  tearDown(() async {
    await service.flush();
    await db.close();
  });

  Future<Map<String, int>> versions(String noteId) async {
    final rows = await (db.select(
      db.counterValues,
    )..where((v) => v.noteId.equals(noteId))).get();
    return {for (final r in rows) r.counterId: r.version};
  }

  test('a flush writes only the per-note value that changed', () async {
    final ids = [
      for (var i = 0; i < 5; i++)
        await service.addCounter(name: 'C$i', scope: CounterScope.perNote),
    ];
    for (final id in ids) {
      await service.increment(id, noteId: 'n1');
    }
    await service.flush();
    final before = await versions('n1');
    expect(before, hasLength(5));

    await service.increment(ids[2], noteId: 'n1');
    await service.flush();

    final after = await versions('n1');
    final moved = [
      for (final id in ids)
        if (after[id] != before[id]) id,
    ];
    expect(moved, [ids[2]]);
  });

  test(
    'resetting a global counter already at its start writes nothing',
    () async {
      final id = await service.addCounter(name: 'Sets', startValue: 3);
      final before = (await versions(''))[id];

      await service.resetGlobal(id);
      await service.flush();

      expect((await versions(''))[id], before);
    },
  );

  group('the backup export', () {
    const orphanHlc = 'ffffffffffff:0000:remote';

    CounterValueRow orphanValue(String noteId) => CounterValueRow(
      counterId: 'gone',
      noteId: noteId,
      value: 99,
      position: 4,
      isPinned: true,
      hlcTimestamp: orphanHlc,
      deviceId: 'remote',
      version: 2,
      isDeleted: false,
      ownerId: 'uid-1',
    );

    test('writes no value whose counter is tombstoned', () async {
      final sets = await service.addCounter(name: 'Sets', startValue: 3);
      final laps = await service.addCounter(
        name: 'Laps',
        scope: CounterScope.perNote,
      );
      await service.increment(laps, noteId: 'n1');
      await service.toggleNoteValuePin(laps, 'n1', true);
      await service.flush();
      final before = await service.exportData();
      expect(jsonDecode(before['globalValues'] as String), {
        sets: 3,
        laps: 1,
      });
      expect(jsonDecode(before['noteValues'] as String), {
        'n1': {laps: 2},
      });

      // A counter deleted on another device whose values arrived live: the
      // merge stores both as received, the backup must not carry the values.
      await db
          .into(db.counters)
          .insert(
            CounterRow(
              id: 'gone',
              name: 'Gone',
              startValue: 1,
              step: 1,
              scope: 'perNote',
              position: 9,
              isPinned: false,
              createdAt: DateTime.utc(2026, 1, 1),
              hlcTimestamp: orphanHlc,
              deviceId: 'remote',
              version: 2,
              isDeleted: true,
              ownerId: 'uid-1',
            ),
          );
      await db.into(db.counterValues).insert(orphanValue(''));
      await db.into(db.counterValues).insert(orphanValue('n1'));
      final reloaded = await CounterService.forTesting(db);

      final after = await reloaded.exportData();

      // `counters` is left out: the reloaded service reads `createdAt` back
      // at the column's precision, which this change does not touch. Compared
      // decoded: the reloaded maps follow the table's order over random ids,
      // so equal maps need not serialize to the same bytes.
      for (final key in ['globalValues', 'noteValues', 'noteValueExtras']) {
        expect(
          jsonDecode(after[key] as String),
          jsonDecode(before[key] as String),
          reason: key,
        );
      }
      expect(after['noteValueExtras'] as String, isNot(contains('gone')));
    });

    test('carries a counter merged live but not yet reloaded, with its '
        'values', () async {
      final sets = await service.addCounter(name: 'Sets', startValue: 3);
      await service.flush();
      // A pull stored these beneath the service; its cache has not reloaded.
      await db
          .into(db.counters)
          .insert(
            CounterRow(
              id: 'merged',
              name: 'Merged',
              startValue: 1,
              step: 1,
              scope: 'perNote',
              position: 9,
              isPinned: false,
              createdAt: DateTime.utc(2026, 1, 1),
              hlcTimestamp: orphanHlc,
              deviceId: 'remote',
              version: 2,
              isDeleted: false,
              ownerId: 'uid-1',
            ),
          );
      await db
          .into(db.counterValues)
          .insert(orphanValue('').copyWith(counterId: 'merged', value: 7));
      await db
          .into(db.counterValues)
          .insert(orphanValue('n1').copyWith(counterId: 'merged', value: 5));
      expect(service.counters.map((c) => c.id), [sets]);

      final exported = await service.exportData();

      final counters = (jsonDecode(exported['counters'] as String) as List)
          .cast<Map<String, dynamic>>();
      expect(counters.map((c) => c['id']), containsAll([sets, 'merged']));
      expect(
        counters.firstWhere((c) => c['id'] == 'merged')['ownerId'],
        'uid-1',
      );
      expect(jsonDecode(exported['globalValues'] as String), {
        sets: 3,
        'merged': 7,
      });
      expect(jsonDecode(exported['noteValues'] as String), {
        'n1': {'merged': 5},
      });
    });
  });

  group('taps pending across a sync page (S3c review H1)', () {
    test('a tap in the reload window lands on top of the merged value', () async {
      final id = await service.addCounter(name: 'Sets', startValue: 3);
      // The page merged another device's 8 beneath the service.
      await db.counterDao.upsertValue(id, '', 8);

      expect(await service.incrementGlobal(id), 4, reason: 'not reloaded yet');
      await service.reload();

      expect(service.getGlobalValue(id), 9);
      expect(await db.counterDao.getValue(id, ''), 8, reason: 'still pending');
      await service.flush();
      expect(await db.counterDao.getValue(id, ''), 9);
    });

    test('flushed before the page, tapped, reloaded after: merged plus the '
        'taps', () async {
      final id = await service.addCounter(name: 'Sets', startValue: 3);
      await service.incrementGlobal(id);
      await service.flush();
      expect(await db.counterDao.getValue(id, ''), 4);

      await service.incrementGlobal(id);
      await service.incrementGlobal(id);
      await db.counterDao.upsertValue(id, '', 8);
      await service.reload();
      await service.flush();

      expect(service.getGlobalValue(id), 10);
      expect(await db.counterDao.getValue(id, ''), 10);
    });

    test('a flush that lands after the merge and before the reload writes '
        'the merged value plus the tap, never the stale number', () async {
      final id = await service.addCounter(name: 'Sets', startValue: 3);
      await service.incrementGlobal(id);
      await db.counterDao.upsertValue(id, '', 8);

      await service.flush();

      expect(await db.counterDao.getValue(id, ''), 9);
      expect(service.getGlobalValue(id), 9);
    });

    test('a per-note tap survives the reload that dropped its note cache', () async {
      final id = await service.addCounter(
        name: 'Laps',
        scope: CounterScope.perNote,
      );
      await service.setValueForNote(id, 2, noteId: 'n1');
      await service.flush();
      await service.increment(id, noteId: 'n1');
      await db.counterDao.upsertValue(id, 'n1', 6);

      await service.reload();

      expect(await service.getValueForNote(id, 'n1'), 7);
      await service.flush();
      expect(await db.counterDao.getValue(id, 'n1'), 7);
    });

    test('a pending reset stays a reset over the merged value', () async {
      final id = await service.addCounter(name: 'Sets', startValue: 3);
      await service.incrementGlobal(id);
      await service.flush();
      await service.resetGlobal(id);
      await service.incrementGlobal(id);
      await db.counterDao.upsertValue(id, '', 8);

      await service.reload();
      await service.flush();

      expect(service.getGlobalValue(id), 4);
      expect(await db.counterDao.getValue(id, ''), 4);
    });

    test('a tap on a counter the page deleted is dropped', () async {
      final id = await service.addCounter(name: 'Sets', startValue: 3);
      await service.incrementGlobal(id);
      await db.counterDao.deleteCounter(id);

      await service.reload();
      await service.flush();

      expect(service.getCounterById(id), isNull);
      expect(await db.counterDao.getValue(id, ''), isNull);
    });
  });

  group('the changes signal', () {
    test('fires after a reload, with the merged rows read', () async {
      final id = await service.addCounter(name: 'Sets', startValue: 3);
      var fired = 0;
      final subscription = service.changes.listen((_) {
        fired++;
        expect(service.getGlobalValue(id), 8);
      });
      addTearDown(subscription.cancel);

      await db.counterDao.upsertValue(id, '', 8);
      await service.reload();
      await pumpEventQueue();

      expect(fired, 1);
    });

    test('fires after an import, never after a local write', () async {
      var fired = 0;
      final subscription = service.changes.listen((_) => fired++);
      addTearDown(subscription.cancel);

      final id = await service.addCounter(name: 'Sets');
      await service.incrementGlobal(id);
      await service.flush();
      await pumpEventQueue();
      expect(fired, 0);

      await service.importData(await service.exportData());
      await pumpEventQueue();
      expect(fired, 1);
    });
  });

  test(
    'a flush pending when the counter is deleted leaves no live value',
    () async {
      final id = await service.addCounter(
        name: 'Laps',
        scope: CounterScope.perNote,
      );
      await service.increment(id, noteId: 'n1');
      await service.incrementGlobal(id);

      await service.deleteCounter(id);
      await service.flush();

      final live =
          await (db.select(db.counterValues)..where(
                (v) => v.counterId.equals(id) & v.isDeleted.equals(false),
              ))
              .get();
      expect(live, isEmpty);
    },
  );
}
