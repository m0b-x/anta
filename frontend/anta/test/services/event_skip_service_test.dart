import 'dart:async';

// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';

import '../database/support/db_test_support.dart';

/// Runs the real DAO, the real CRDT stamping and the real facade against
/// `NativeDatabase.memory()`, the way the `test/database` suite does.
///
/// Structurally this mirrors the presence suite, because the tables are
/// identical — the assertions that earn their place are the two where skips
/// differ: cancelling a day must clear any absence mark on it, and a leaked
/// facade after a database switch *hides* occurrences rather than merely
/// mis-drawing them.
void main() {
  late AppDatabase db;
  late EventSkipService service;
  late _HeldSkipRead gate;

  final day = DateTime.utc(2026, 8, 10);
  final otherDay = DateTime.utc(2026, 8, 11);

  /// A tracked event on the classic implicit-attendance default, so an
  /// unmarked day reads as present. `EventPresence.isMissed` takes the event
  /// since **v37**.
  CalendarEvent eventOf(String id) => CalendarEvent(
    id: id,
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 8, 1),
    rule: const DailyRecurrence(),
    tracksPresence: true,
  );

  setUp(() async {
    EventSkipService.reset();
    EventPresenceService.reset();
    gate = _HeldSkipRead();
    db = await openTestDatabase(interceptor: gate);
    service = await EventSkipService.forTesting(db);
    await EventPresenceService.forTesting(db);
  });

  tearDown(() async {
    gate.release();
    EventSkipService.reset();
    EventPresenceService.reset();
    await db.close();
  });

  Future<List<EventSkipRow>> allRows() => db.select(db.eventSkips).get();

  Future<EventSkipRow> rowFor(String eventId, DateTime value) {
    return (db.select(db.eventSkips)
          ..where((s) => s.eventId.equals(eventId) & s.day.equals(value)))
        .getSingle();
  }

  group('marking', () {
    test('a cancelled day publishes to the facade', () async {
      await service.markSkipped('e1', day);

      expect(EventSkips.isSkipped('e1', day), isTrue);
      expect(EventSkips.isSkipped('e1', otherDay), isFalse);
      expect(EventSkips.daysFor('e1'), {day});
    });

    test('a first skip is a live version-1 row', () async {
      await service.markSkipped('e1', day);

      final row = await rowFor('e1', day);
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
      expect(row.hlcTimestamp, isNotEmpty);
      expect(row.deviceId, 'test-device');
    });

    test('cancelling twice does not churn the version', () async {
      await service.markSkipped('e1', day);
      final once = await rowFor('e1', day);

      await service.markSkipped('e1', day);

      expect((await rowFor('e1', day)).version, once.version);
    });

    test('a naive local day normalizes to the same row', () async {
      await service.markSkipped('e1', DateTime(2026, 8, 10, 22, 15));

      expect(EventSkips.isSkipped('e1', day), isTrue);
      expect(await allRows(), hasLength(1));
    });
  });

  group('restoring', () {
    test('tombstones rather than deleting', () async {
      await service.markSkipped('e1', day);

      await service.unskip('e1', day);

      expect(EventSkips.isSkipped('e1', day), isFalse);
      final row = await rowFor('e1', day);
      expect(row.isDeleted, isTrue);
      expect(row.deletedAt, isNotNull);
      expect(row.version, 2);
    });

    test('re-cancelling resurrects the same row', () async {
      await service.markSkipped('e1', day);
      final created = (await rowFor('e1', day)).createdAt;
      await service.unskip('e1', day);

      await service.markSkipped('e1', day);

      final row = await rowFor('e1', day);
      expect(row.isDeleted, isFalse);
      expect(row.createdAt, created);
      expect(await allRows(), hasLength(1));
    });

    test('restoring a day that was never cancelled is a no-op', () async {
      await service.unskip('e1', day);

      expect(await allRows(), isEmpty);
    });
  });

  /// One Save of the editor's Skipped days picker. A term's worth of days
  /// used to cost a transaction, an HLC and an outbox row each, because the
  /// picker was applied one day at a time.
  group('setSkips', () {
    final thirdDay = DateTime.utc(2026, 8, 12);

    test('writes the whole diff under one stamp', () async {
      await service.markSkipped('e1', day);
      await service.markSkipped('e1', otherDay);
      await service.unskip('e1', otherDay);

      expect(
        await service.setSkips('e1', {otherDay, thirdDay}),
        isTrue,
      );

      expect(EventSkips.daysFor('e1'), {otherDay, thirdDay});
      final rows = await allRows();
      expect(rows, hasLength(3));
      // The day that left, the tombstone that came back and the fresh mark
      // all carry one HLC: this is one act of the user's, not three.
      expect(rows.map((r) => r.hlcTimestamp).toSet(), hasLength(1));
      expect(
        await db.syncOutboxDao.pendingForTable('calendar_event_skips'),
        hasLength(3),
      );
    });

    test('keeps every row\'s soft-delete semantics and versions', () async {
      await service.markSkipped('e1', day);
      await service.markSkipped('e1', otherDay);
      await service.unskip('e1', otherDay);
      final resurrected = await rowFor('e1', otherDay);

      await service.setSkips('e1', {otherDay});

      final left = await rowFor('e1', day);
      expect(left.isDeleted, isTrue);
      expect(left.deletedAt, isNotNull);
      expect(left.version, 2);
      final back = await rowFor('e1', otherDay);
      expect(back.isDeleted, isFalse);
      expect(back.createdAt, resurrected.createdAt);
      expect(back.version, resurrected.version + 1);
    });

    test('an unchanged Save writes nothing and answers false', () async {
      await service.markSkipped('e1', day);
      final before = await rowFor('e1', day);

      expect(await service.setSkips('e1', {day}), isFalse);

      expect((await rowFor('e1', day)).version, before.version);
    });

    test('a naive local day normalizes to the same row', () async {
      await service.setSkips('e1', {DateTime(2026, 8, 10, 22, 15)});

      expect(EventSkips.isSkipped('e1', day), isTrue);
      expect(await allRows(), hasLength(1));
    });

    test('a newly cancelled day loses its absence mark', () async {
      final presence = await EventPresenceService.getInstance();
      await presence.setStatus('e1', day, PresenceStatus.missed);

      await service.setSkips('e1', {day});

      expect(EventPresence.isMissed(eventOf('e1'), day), isFalse);
    });
  });

  group('presence interaction', () {
    test('cancelling a day clears its absence mark', () async {
      final presence = await EventPresenceService.getInstance();
      await presence.setStatus('e1', day, PresenceStatus.missed);
      expect(EventPresence.isMissed(eventOf('e1'), day), isTrue);

      await service.markSkipped('e1', day);

      // An occurrence that does not exist cannot have been missed; leaving the
      // mark would resurface it the moment the skip is undone.
      expect(EventPresence.isMissed(eventOf('e1'), day), isFalse);
    });

    test('an absence on another day survives', () async {
      final presence = await EventPresenceService.getInstance();
      await presence.setStatus('e1', otherDay, PresenceStatus.missed);

      await service.markSkipped('e1', day);

      expect(EventPresence.isMissed(eventOf('e1'), otherDay), isTrue);
    });
  });

  group('a reload in flight', () {
    test('a skip landing inside it keeps the event\'s other days', () async {
      await service.markSkipped('e1', day);
      // The reload's rows are held, so the whole of the Skip tap below lands
      // inside the window the reload is open for — the sync pull's
      // `_appReloadCalendar` racing a tap on Skip. The cache used to be
      // emptied before that `await`, so the tap's targeted republish served
      // the one day it wrote and dropped every other.
      gate.holdNextSkipRead();
      final reload = service.reload();
      await pumpEventQueue();
      expect(gate.held, isTrue);

      await service.markSkipped('e1', otherDay);

      expect(EventSkips.isSkipped('e1', day), isTrue);

      gate.release();
      await reload;

      expect(EventSkips.isSkipped('e1', day), isTrue);
      expect(EventSkips.isSkipped('e1', otherDay), isTrue);
    });
  });

  group('reset', () {
    test('clears the facade so another database cannot hide days', () async {
      await service.markSkipped('e1', day);

      EventSkipService.reset();

      expect(EventSkips.isSkipped('e1', day), isFalse);
    });
  });

  group('backup', () {
    test('export/import round-trips live skips only', () async {
      await service.markSkipped('e1', day);
      await service.markSkipped('e1', otherDay);
      await service.unskip('e1', otherDay);
      final exported = await service.exportData();

      expect(exported, hasLength(1));

      await service.clearAllForImport();
      expect(EventSkips.daysFor('e1'), isEmpty);
      await service.importData(exported);

      expect(EventSkips.daysFor('e1'), {day});
    });

    test('import stamps fresh identity, never the backup\'s', () async {
      await service.importData([
        {'eventId': 'e1', 'dayMs': day.millisecondsSinceEpoch},
      ]);

      final row = await rowFor('e1', day);
      expect(row.deviceId, 'test-device');
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
    });

    test('a malformed row is skipped and the rest still imports', () async {
      await service.importData([
        'not a map',
        {'eventId': 'e1'},
        {'eventId': 'e2', 'dayMs': day.millisecondsSinceEpoch},
      ]);

      expect(EventSkips.daysFor('e1'), isEmpty);
      expect(EventSkips.daysFor('e2'), {day});
    });
  });
}

/// Delivers the skip table's reload late: the `SELECT` runs at once, so its
/// rows are what the table held when the service asked, and they are handed
/// back only on [release] — the window a sync reload is open for, in which a
/// Skip tap of its own lands.
class _HeldSkipRead extends QueryInterceptor {
  Completer<void>? _hold;
  bool _armed = false;
  bool held = false;

  /// Holds the next read of `calendar_event_skips`, which is the reload's:
  /// one shot, so the writes that follow inside the window run freely.
  void holdNextSkipRead() {
    _armed = true;
    _hold = Completer<void>();
  }

  void release() {
    final hold = _hold;
    _hold = null;
    _armed = false;
    if (hold != null && !hold.isCompleted) hold.complete();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await super.runSelect(executor, statement, args);
    final hold = _hold;
    if (_armed && hold != null && statement.contains('calendar_event_skips')) {
      _armed = false;
      held = true;
      await hold.future;
    }
    return rows;
  }
}
