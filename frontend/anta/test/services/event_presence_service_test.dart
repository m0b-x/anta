// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/event_presence_service.dart';

import '../database/support/db_test_support.dart';

/// Runs the real DAO, the real CRDT stamping and the real facade against
/// `NativeDatabase.memory()`, the way the `test/database` suite does.
///
/// Presence is the first feature whose table is shaped for cloud sync before
/// any transport exists, so the assertions that matter most are the ones about
/// the columns nothing renders yet: un-marking must **tombstone** with a
/// version bump rather than delete, re-marking must resurrect the same row, and
/// a repeated tap must not churn the version. Those are the properties a merge
/// will depend on, and nothing in the UI would ever reveal them breaking.
void main() {
  late AppDatabase db;
  late EventPresenceService service;

  final day = DateTime.utc(2026, 8, 10);
  final otherDay = DateTime.utc(2026, 8, 11);

  setUp(() async {
    EventPresenceService.reset();
    db = await openTestDatabase();
    service = await EventPresenceService.forTesting(db);
  });

  tearDown(() async {
    EventPresenceService.reset();
    await db.close();
  });

  Future<List<EventAbsenceRow>> allRows() =>
      db.select(db.eventAbsences).get();

  Future<EventAbsenceRow> rowFor(String eventId, DateTime value) {
    return (db.select(db.eventAbsences)..where(
          (a) => a.eventId.equals(eventId) & a.day.equals(value),
        ))
        .getSingle();
  }

  group('marking', () {
    test('a mark is a live version-1 row stamped with this device', () async {
      await service.markMissed('e1', day);

      expect(EventPresence.isMissed('e1', day), isTrue);
      final row = await rowFor('e1', day);
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      expect(row.hlcTimestamp, isNotEmpty);
      expect(row.deviceId, 'test-device');
    });

    test('marking an already-missed day is a complete no-op', () async {
      await service.markMissed('e1', day);
      final before = await rowFor('e1', day);
      await service.markMissed('e1', day);
      final after = await rowFor('e1', day);

      // A repeated tap must not churn the version: every bump is an ordering
      // event once devices merge.
      expect(after.version, before.version);
      expect(after.updatedAt, before.updatedAt);
      expect(after.hlcTimestamp, before.hlcTimestamp);
      expect(await allRows(), hasLength(1));
    });

    test('marks are per (event, day), not per event', () async {
      await service.markMissed('e1', day);

      expect(EventPresence.isMissed('e1', otherDay), isFalse);
      expect(EventPresence.isMissed('e2', day), isFalse);
    });
  });

  group('un-marking', () {
    test('the row survives as a tombstone and leaves the facade', () async {
      await service.markMissed('e1', day);
      await service.unmark('e1', day);

      expect(EventPresence.isMissed('e1', day), isFalse);
      final rows = await allRows();
      expect(rows, hasLength(1));
      expect(rows.single.isDeleted, isTrue);
      expect(rows.single.deletedAt, isNotNull);
      expect(rows.single.version, 2);
    });

    test('un-marking a never-marked day writes nothing', () async {
      await service.unmark('e1', day);
      expect(await allRows(), isEmpty);
    });

    test('un-marking twice does not churn the version', () async {
      await service.markMissed('e1', day);
      await service.unmark('e1', day);
      final before = await rowFor('e1', day);
      await service.unmark('e1', day);
      final after = await rowFor('e1', day);

      expect(after.version, before.version);
      expect(after.hlcTimestamp, before.hlcTimestamp);
    });

    test('getActive filters tombstones out', () async {
      await service.markMissed('e1', day);
      await service.markMissed('e1', otherDay);
      await service.unmark('e1', day);

      final active = await db.eventAbsenceDao.getActive();
      expect(active.map((r) => r.day.millisecondsSinceEpoch), [
        otherDay.millisecondsSinceEpoch,
      ]);
      expect(await allRows(), hasLength(2));
    });
  });

  test('re-marking resurrects the row it first wrote', () async {
    await service.markMissed('e1', day);
    final original = await rowFor('e1', day);
    await service.unmark('e1', day);
    await service.markMissed('e1', day);

    final row = await rowFor('e1', day);
    expect(row.isDeleted, isFalse);
    expect(row.deletedAt, isNull);
    expect(row.version, 3);
    // A resurrected day keeps the date it was first marked — that is what the
    // update masks `created_at` for.
    expect(row.createdAt, original.createdAt);
    expect(await allRows(), hasLength(1));
    expect(EventPresence.isMissed('e1', day), isTrue);
  });

  group('facade', () {
    test('every republish bumps the revision', () async {
      final start = EventPresence.revision;
      await service.markMissed('e1', day);
      expect(EventPresence.revision, greaterThan(start));

      final afterMark = EventPresence.revision;
      await service.unmark('e1', day);
      expect(EventPresence.revision, greaterThan(afterMark));
    });

    test('reset clears the singleton and the facade', () async {
      await service.markMissed('e1', day);
      expect(EventPresence.isMissed('e1', day), isTrue);

      EventPresenceService.reset();
      expect(EventPresence.isMissed('e1', day), isFalse);

      // A fresh instance over the same database republishes what is stored.
      final rebound = await EventPresenceService.forTesting(db);
      expect(identical(rebound, service), isFalse);
      expect(EventPresence.isMissed('e1', day), isTrue);
    });

    test('appliesTo needs the opt-in and more than one occurrence', () {
      final tracked = CalendarEvent(
        id: 'e1',
        title: 'Leg day',
        categoryId: 'gym',
        startDate: DateTime.utc(2026, 8, 1),
        rule: const DailyRecurrence(),
        tracksPresence: true,
      );

      expect(EventPresence.appliesTo(tracked), isTrue);
      expect(
        EventPresence.appliesTo(tracked.copyWith(tracksPresence: false)),
        isFalse,
      );
      // An event that fires on exactly one day has no attendance to keep.
      expect(
        EventPresence.appliesTo(
          tracked.copyWith(rule: const OneTimeRecurrence()),
        ),
        isFalse,
      );
      // A specific-dates rule is a list of distinct occasions and does
      // participate — never gate on the editor's `_RepeatMode`, which files
      // specific dates under one-time.
      expect(
        EventPresence.appliesTo(
          tracked.copyWith(
            rule: SpecificDatesRecurrence(dates: {day, otherDay}),
          ),
        ),
        isTrue,
      );
    });
  });

  group('backup', () {
    test('export carries live marks only, without CRDT identity', () async {
      await service.markMissed('e1', day);
      await service.markMissed('e1', otherDay);
      await service.unmark('e1', otherDay);

      final exported = await service.exportData();
      expect(exported, hasLength(1));
      expect(exported.single['eventId'], 'e1');
      expect(exported.single['dayMs'], day.millisecondsSinceEpoch);
      expect(exported.single.keys.toSet(), {
        'eventId',
        'dayMs',
        'createdAtMs',
        'updatedAtMs',
      });
    });

    test('import keeps audit timestamps but stamps fresh identity', () async {
      final createdAt = DateTime(2024, 3, 1, 9, 30);
      final updatedAt = DateTime(2024, 3, 2, 18, 5);
      await service.importData([
        {
          'eventId': 'e1',
          'dayMs': day.millisecondsSinceEpoch,
          'createdAtMs': createdAt.millisecondsSinceEpoch,
          'updatedAtMs': updatedAt.millisecondsSinceEpoch,
        },
        'not a row',
        {'eventId': 'e2'},
      ]);

      final row = await rowFor('e1', day);
      // Drift stores unix seconds, so a restored timestamp round-trips to the
      // second, not the millisecond.
      expect(
        row.createdAt.millisecondsSinceEpoch ~/ 1000,
        createdAt.millisecondsSinceEpoch ~/ 1000,
      );
      expect(
        row.updatedAt.millisecondsSinceEpoch ~/ 1000,
        updatedAt.millisecondsSinceEpoch ~/ 1000,
      );
      // A backup is not a sync channel: the restored mark is this device's own
      // live row, never a replayed one.
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
      expect(row.hlcTimestamp, isNotEmpty);
      expect(row.deviceId, 'test-device');
      // Malformed entries are skipped individually, not fatal.
      expect(await allRows(), hasLength(1));
      expect(EventPresence.isMissed('e1', day), isTrue);
    });

    test('a tombstone does not round-trip an export/import', () async {
      await service.markMissed('e1', day);
      await service.unmark('e1', day);

      await service.importData(await service.exportData());
      expect(await allRows(), isEmpty);
    });

    test('clearAllForImport empties the table and the facade', () async {
      await service.markMissed('e1', day);
      await service.unmark('e1', otherDay);

      await service.clearAllForImport();
      expect(await allRows(), isEmpty);
      expect(EventPresence.isMissed('e1', day), isFalse);
    });
  });

  group('event delete cascade', () {
    test('hard-deletes every row of that event, tombstones included', () async {
      await db.calendarEventDao.upsert(
        CalendarEventsCompanion.insert(
          id: 'e1',
          title: 'Leg day',
          category: 'gym',
          startDate: DateTime.utc(2026, 8, 1),
          ruleKind: 'daily',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await service.markMissed('e1', day);
      await service.markMissed('e1', otherDay);
      await service.unmark('e1', otherDay);
      await service.markMissed('e2', day);

      await db.eventAbsenceDao.deleteForEvent('e1');
      await service.refreshAfterEventRemoval();

      final rows = await allRows();
      expect(rows.map((r) => r.eventId), ['e2']);
      expect(EventPresence.isMissed('e1', day), isFalse);
      expect(EventPresence.isMissed('e2', day), isTrue);
    });
  });
}
