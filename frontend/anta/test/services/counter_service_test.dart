// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/common.dart' show SqliteException;

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

    test('a Reset while memory still shows the start value survives the '
        'merge (A1b review R24)', () async {
      final id = await service.addCounter(name: 'Sets', startValue: 3);
      await service.flush();
      // The page merged another device's 8; memory still holds the start
      // value, so a Reset reads as a no-op and would be dropped.
      await db.counterDao.upsertValue(id, '', 8);

      await service.resetGlobal(id);
      await service.reload();

      expect(service.getGlobalValue(id), 3);
      await service.flush();
      expect(await db.counterDao.getValue(id, ''), 3);
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

  test('a flush whose transaction fails keeps every pending change for the '
      'next one, taps made meanwhile on top (S4a review L8)', () async {
    final writes = _FailCounterValueWrites();
    final failing = await openTestDatabase(interceptor: writes);
    addTearDown(failing.close);
    final counters = await CounterService.forTesting(failing);
    final sets = await counters.addCounter(name: 'Sets', startValue: 3);
    final laps = await counters.addCounter(
      name: 'Laps',
      scope: CounterScope.perNote,
    );
    await counters.incrementGlobal(sets);
    await counters.setValueForNote(laps, 7, noteId: 'n1');

    writes.armed = true;
    await counters.flush();
    expect(writes.refused, isPositive);
    expect(await failing.counterDao.getValue(sets, ''), isNot(4));

    await counters.incrementGlobal(sets);
    await counters.increment(laps, noteId: 'n1');
    writes.armed = false;
    await counters.flush();

    expect(await failing.counterDao.getValue(sets, ''), 5);
    expect(await failing.counterDao.getValue(laps, 'n1'), 8);
    expect(counters.getGlobalValue(sets), 5);
  });

  test('a flush whose writes outlived its rollback is not applied twice '
      '(A1b review R26)', () async {
    final commit = _ThrowAfterCommit();
    final failing = await openTestDatabase(interceptor: commit);
    addTearDown(failing.close);
    final counters = await CounterService.forTesting(failing);
    final sets = await counters.addCounter(name: 'Sets', startValue: 3);
    await counters.incrementGlobal(sets);

    commit.armed = true;
    await counters.flush();
    // The transaction committed before the throw, so the 4 is durable: a
    // restored snapshot would put the same tap on top of it again.
    expect(await failing.counterDao.getValue(sets, ''), 4);
    expect(counters.getGlobalValue(sets), 4);

    await counters.flush();
    expect(await failing.counterDao.getValue(sets, ''), 4);
  });

  test('a flush a locked database refused keeps the tap for the next one '
      '(A6 review R107)', () async {
    final locked = _FailCounterValueWrites(
      // SQLITE_BUSY: another connection holds the database. The statement
      // fails, the transaction rolls back clean, and nothing was written.
      error: () =>
          SqliteException(extendedResultCode: 5, message: 'database is locked'),
    );
    final failing = await openTestDatabase(interceptor: locked);
    addTearDown(failing.close);
    final counters = await CounterService.forTesting(failing);
    final sets = await counters.addCounter(name: 'Sets', startValue: 3);
    await counters.incrementGlobal(sets);

    locked.armed = true;
    await counters.flush();
    expect(locked.refused, isPositive);
    expect(
      await failing.counterDao.getValue(sets, ''),
      3,
      reason: 'the transaction rolled back',
    );

    locked.armed = false;
    await counters.flush();

    expect(await failing.counterDao.getValue(sets, ''), 4);
    expect(counters.getGlobalValue(sets), 4);
  });

  test('a tap made during a flush whose rollback failed reaches the table '
      'with no further tap (A6 review R108)', () async {
    final commit = _ThrowAfterCommit();
    final failing = await openTestDatabase(interceptor: commit);
    addTearDown(failing.close);
    final counters = await CounterService.forTesting(failing);
    final sets = await counters.addCounter(name: 'Sets', startValue: 3);
    await counters.incrementGlobal(sets);

    // Tapped while the write the flush had already copied was in flight: the
    // recovery re-applies it to memory and leaves it pending.
    commit.duringCommit = () => unawaited(counters.incrementGlobal(sets));
    commit.armed = true;
    await counters.flush();
    expect(counters.getGlobalValue(sets), 5);

    // No further tap and no `flush()`.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(await failing.counterDao.getValue(sets, ''), 5);
  });

  test('a Reset on a counter with no value row writes nothing, bound or not '
      '(A6 review R117/R119)', () async {
    await db
        .into(db.counters)
        .insert(
          CounterRow(
            id: 'merged',
            name: 'Merged',
            startValue: 3,
            step: 1,
            scope: 'global',
            position: 0,
            isPinned: false,
            createdAt: DateTime.utc(2026, 1, 1),
            hlcTimestamp: 'ffffffffffff:0000:remote',
            deviceId: 'remote',
            version: 2,
            isDeleted: false,
          ),
        );
    // A counter whose value row never arrived: the merge carried the
    // `counters` row alone.
    final reloaded = await CounterService.forTesting(db);
    await db.syncOutboxDao.clear();

    await reloaded.resetGlobal('merged');
    await reloaded.flush();

    expect(await db.syncOutboxDao.pending(), isEmpty);
    expect(await db.counterDao.getValue('merged', ''), isNull);
    expect(reloaded.getGlobalValue('merged'), 3);
  });

  test('a flush that failed arms the next one itself, with no further tap '
      'and no explicit flush (A1b review R21)', () async {
    final writes = _FailCounterValueWrites();
    final failing = await openTestDatabase(interceptor: writes);
    addTearDown(failing.close);
    final counters = await CounterService.forTesting(failing);
    final sets = await counters.addCounter(name: 'Sets', startValue: 3);

    writes.armed = true;
    await counters.incrementGlobal(sets);
    // Past the 300 ms debounce: the timer's own flush ran and failed.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(writes.refused, isPositive);
    expect(await failing.counterDao.getValue(sets, ''), 3);

    // No further tap and no `flush()` — the failed flush has to have armed
    // the next one, or the tap waits for a tap that may never come.
    writes.armed = false;
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(await failing.counterDao.getValue(sets, ''), 4);
    expect(counters.getGlobalValue(sets), 4);
  });

  test(
    'an import waits for a flush already in flight (A1b review R25)',
    () async {
      final slow = _HoldFirstTransaction();
      final held = await openTestDatabase(interceptor: slow);
      addTearDown(held.close);
      final counters = await CounterService.forTesting(held);
      final sets = await counters.addCounter(name: 'Sets', startValue: 3);
      final archive = await counters.exportData();

      await counters.incrementGlobal(sets);
      slow.armed = true;
      final flushing = counters.flush();
      // The flush has copied its pending tap and is waiting for its BEGIN.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await counters.importData(archive);
      await flushing;

      expect(
        await held.counterDao.getValue(sets, ''),
        3,
        reason: 'the restore is the last writer, not the tap before it',
      );
      expect(counters.getGlobalValue(sets), 3);
    },
  );

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

/// Commits, then throws a SQLite I/O error while [armed]: the writes are
/// durable and the flush still sees a failure, which is what
/// `CouldNotRollBackException` and a post-commit fault both leave behind.
class _ThrowAfterCommit extends QueryInterceptor {
  bool armed = false;

  /// The DAO opens its own transaction inside the flush's, and only the
  /// outermost commit makes the writes durable.
  int _depth = 0;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    _depth++;
    return super.beginTransaction(parent);
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) {
    _depth--;
    return super.rollbackTransaction(inner);
  }

  /// Runs inside the flush's own turn, just before the throw, so a test can
  /// make a tap the flush has already copied past.
  void Function()? duringCommit;

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    await inner.send();
    if (--_depth > 0 || !armed) return;
    armed = false;
    duringCommit?.call();
    throw SqliteException(extendedResultCode: 10, message: 'disk I/O error');
  }
}

/// Delays the first transaction opened while [armed], as a busy database
/// would: the flush has copied its pending changes and is waiting for its
/// `BEGIN`, so another writer — a backup restore — can still get in front of
/// it unless they share a queue.
class _HoldFirstTransaction extends QueryInterceptor {
  bool armed = false;

  @override
  Future<bool> ensureOpen(
    QueryExecutor executor,
    QueryExecutorUser user,
  ) async {
    if (armed && executor is TransactionExecutor) {
      armed = false;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return super.ensureOpen(executor, user);
  }
}

/// Refuses every write to `counter_values` while [armed], as a failing disk
/// would: the flush's transaction throws and rolls back.
class _FailCounterValueWrites extends QueryInterceptor {
  _FailCounterValueWrites({this.error});

  /// What a refused write throws, for a test that cares about the SQLite
  /// result code behind it; a plain failure by default.
  final Object Function()? error;

  bool armed = false;
  int refused = 0;

  void _check(String statement) {
    if (armed && statement.contains('counter_values')) {
      refused++;
      throw error?.call() ?? StateError('counter_values refused');
    }
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(statement);
    return super.runUpdate(executor, statement, args);
  }
}
