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

  /// A plain tracked event with the classic implicit-attendance default, so an
  /// unmarked day still resolves to "present" the way every assertion here
  /// assumes. `EventPresence.isMissed` takes the event since **v37** — it has
  /// to consult `assumesAbsentOn` when there is no explicit mark.
  CalendarEvent eventOf(String id) => CalendarEvent(
    id: id,
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 8, 1),
    rule: const DailyRecurrence(),
    tracksPresence: true,
  );

  /// The **v37** inverted default: every unmarked day reads missed, so the
  /// only thing that can make [EventPresence.isMissed] false is a stored
  /// `present` row. That makes it the one shape where a lost status column is
  /// visible rather than merely wrong.
  CalendarEvent assumeAbsentEventOf(String id) =>
      eventOf(id).copyWith(assumeAbsent: true);

  setUp(() async {
    EventPresenceService.reset();
    db = await openTestDatabase();
    service = await EventPresenceService.forTesting(db);
  });

  tearDown(() async {
    EventPresenceService.reset();
    await db.close();
  });

  Future<List<EventAbsenceRow>> allRows() => db.select(db.eventAbsences).get();

  Future<EventAbsenceRow> rowFor(String eventId, DateTime value) {
    return (db.select(db.eventAbsences)
          ..where((a) => a.eventId.equals(eventId) & a.day.equals(value)))
        .getSingle();
  }

  group('marking', () {
    test('a mark is a live version-1 row stamped with this device', () async {
      await service.setStatus('e1', day, PresenceStatus.missed);

      expect(EventPresence.isMissed(eventOf('e1'), day), isTrue);
      final row = await rowFor('e1', day);
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      expect(row.hlcTimestamp, isNotEmpty);
      expect(row.deviceId, 'test-device');
    });

    test('marking an already-missed day is a complete no-op', () async {
      await service.setStatus('e1', day, PresenceStatus.missed);
      final before = await rowFor('e1', day);
      await service.setStatus('e1', day, PresenceStatus.missed);
      final after = await rowFor('e1', day);

      // A repeated tap must not churn the version: every bump is an ordering
      // event once devices merge.
      expect(after.version, before.version);
      expect(after.updatedAt, before.updatedAt);
      expect(after.hlcTimestamp, before.hlcTimestamp);
      expect(await allRows(), hasLength(1));
    });

    test('the opposite status rewrites the row in place', () async {
      await service.setStatus('e1', day, PresenceStatus.missed);
      final original = await rowFor('e1', day);

      await service.setStatus('e1', day, PresenceStatus.present);

      final row = await rowFor('e1', day);
      expect(row.status, PresenceStatus.present.name);
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      // One ordering event, not two: v26 flipped a day by tombstoning the row
      // and letting its absence mean "present", which is exactly the reading
      // an assume-absent event no longer shares.
      expect(row.version, original.version + 1);
      // The day keeps the date it was first marked — that is what the update
      // masks `created_at` for.
      expect(row.createdAt, original.createdAt);
      expect(await allRows(), hasLength(1));
    });

    test('marking an already-present day is a complete no-op', () async {
      await service.setStatus('e1', day, PresenceStatus.present);
      final before = await rowFor('e1', day);
      await service.setStatus('e1', day, PresenceStatus.present);
      final after = await rowFor('e1', day);

      expect(after.version, before.version);
      expect(after.updatedAt, before.updatedAt);
      expect(after.hlcTimestamp, before.hlcTimestamp);
    });

    test('a present mark outranks an assume-absent default', () async {
      final subject = assumeAbsentEventOf('e1');
      expect(EventPresence.isMissed(subject, day), isTrue);

      await service.setStatus('e1', day, PresenceStatus.present);

      expect(EventPresence.isMissed(subject, day), isFalse);
      // The confirmation is one day wide; nothing else about the event moved.
      expect(EventPresence.isMissed(subject, otherDay), isTrue);
    });

    test('a present mark survives a reload of the facade', () async {
      await service.setStatus('e1', day, PresenceStatus.present);

      await service.reload();

      // The status has to come back off the *index-only* projection, so a
      // `getActiveKeys` that dropped the column would read every stored
      // confirmation as a miss and leave an assume-absent event permanently
      // unconfirmable.
      expect(
        EventPresence.marksFor('e1')[day],
        PresenceStatus.present,
        reason: 'the load must carry the status, not just the key',
      );
      expect(EventPresence.isMissed(assumeAbsentEventOf('e1'), day), isFalse);
    });

    test('clearing a present mark returns the day to the default', () async {
      await service.setStatus('e1', day, PresenceStatus.present);

      await service.clearMark('e1', day);

      // `clearMark` is the only tombstoning path since v37, and it means
      // "no answer yet" — which reads differently on each of the two defaults.
      expect(EventPresence.isMissed(assumeAbsentEventOf('e1'), day), isTrue);
      expect(EventPresence.isMissed(eventOf('e1'), day), isFalse);
      expect((await rowFor('e1', day)).isDeleted, isTrue);
    });

    test('marks are per (event, day), not per event', () async {
      await service.setStatus('e1', day, PresenceStatus.missed);

      expect(EventPresence.isMissed(eventOf('e1'), otherDay), isFalse);
      expect(EventPresence.isMissed(eventOf('e2'), day), isFalse);
    });
  });

  group('un-marking', () {
    test('the row survives as a tombstone and leaves the facade', () async {
      await service.setStatus('e1', day, PresenceStatus.missed);
      await service.clearMark('e1', day);

      expect(EventPresence.isMissed(eventOf('e1'), day), isFalse);
      final rows = await allRows();
      expect(rows, hasLength(1));
      expect(rows.single.isDeleted, isTrue);
      expect(rows.single.deletedAt, isNotNull);
      expect(rows.single.version, 2);
    });

    test('un-marking a never-marked day writes nothing', () async {
      await service.clearMark('e1', day);
      expect(await allRows(), isEmpty);
    });

    test('un-marking twice does not churn the version', () async {
      await service.setStatus('e1', day, PresenceStatus.missed);
      await service.clearMark('e1', day);
      final before = await rowFor('e1', day);
      await service.clearMark('e1', day);
      final after = await rowFor('e1', day);

      expect(after.version, before.version);
      expect(after.hlcTimestamp, before.hlcTimestamp);
    });

    test('getActive filters tombstones out', () async {
      await service.setStatus('e1', day, PresenceStatus.missed);
      await service.setStatus('e1', otherDay, PresenceStatus.missed);
      await service.clearMark('e1', day);

      final active = await db.eventAbsenceDao.getActive();
      expect(active.map((r) => r.day.millisecondsSinceEpoch), [
        otherDay.millisecondsSinceEpoch,
      ]);
      expect(await allRows(), hasLength(2));
    });
  });

  test('re-marking resurrects the row it first wrote', () async {
    await service.setStatus('e1', day, PresenceStatus.missed);
    final original = await rowFor('e1', day);
    await service.clearMark('e1', day);
    await service.setStatus('e1', day, PresenceStatus.missed);

    final row = await rowFor('e1', day);
    expect(row.isDeleted, isFalse);
    expect(row.deletedAt, isNull);
    expect(row.version, 3);
    // A resurrected day keeps the date it was first marked — that is what the
    // update masks `created_at` for.
    expect(row.createdAt, original.createdAt);
    expect(await allRows(), hasLength(1));
    expect(EventPresence.isMissed(eventOf('e1'), day), isTrue);
  });

  group('facade', () {
    test('every republish bumps the revision', () async {
      final start = EventPresence.revision;
      await service.setStatus('e1', day, PresenceStatus.missed);
      expect(EventPresence.revision, greaterThan(start));

      final afterMark = EventPresence.revision;
      await service.clearMark('e1', day);
      expect(EventPresence.revision, greaterThan(afterMark));
    });

    test('reset clears the singleton and the facade', () async {
      await service.setStatus('e1', day, PresenceStatus.missed);
      expect(EventPresence.isMissed(eventOf('e1'), day), isTrue);

      EventPresenceService.reset();
      expect(EventPresence.isMissed(eventOf('e1'), day), isFalse);

      // A fresh instance over the same database republishes what is stored.
      final rebound = await EventPresenceService.forTesting(db);
      expect(identical(rebound, service), isFalse);
      expect(EventPresence.isMissed(eventOf('e1'), day), isTrue);
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
      await service.setStatus('e1', day, PresenceStatus.missed);
      await service.setStatus('e1', otherDay, PresenceStatus.missed);
      await service.clearMark('e1', otherDay);

      final exported = await service.exportData();
      expect(exported, hasLength(1));
      expect(exported.single['eventId'], 'e1');
      expect(exported.single['dayMs'], day.millisecondsSinceEpoch);
      expect(exported.single['status'], PresenceStatus.missed.name);
      expect(exported.single.keys.toSet(), {
        'eventId',
        'dayMs',
        'status',
        'createdAtMs',
        'updatedAtMs',
      });
    });

    test('a present mark round-trips through an archive', () async {
      await service.setStatus('e1', day, PresenceStatus.present);
      final exported = await service.exportData();
      expect(exported.single['status'], PresenceStatus.present.name);

      await service.clearAllForImport();
      await service.importData(exported);

      expect((await rowFor('e1', day)).status, PresenceStatus.present.name);
      // The only assertion that proves the restored row is still a
      // confirmation: on an assume-absent event, a status lost in transit
      // would come back as a miss and look like data that never existed.
      expect(EventPresence.isMissed(assumeAbsentEventOf('e1'), day), isFalse);
    });

    test('a row with no status imports as missed', () async {
      // Every pre-v37 archive is exactly this: a live row could only mean one
      // thing, so it never carried a name for it.
      await service.importData([
        {'eventId': 'e1', 'dayMs': day.millisecondsSinceEpoch},
        {
          'eventId': 'e1',
          'dayMs': otherDay.millisecondsSinceEpoch,
          'status': 'partial',
        },
      ]);

      expect((await rowFor('e1', day)).status, PresenceStatus.missed.name);
      // And a status a newer build invented decodes the same way rather than
      // failing the whole restore.
      expect((await rowFor('e1', otherDay)).status, PresenceStatus.missed.name);
      expect(EventPresence.isMissed(eventOf('e1'), day), isTrue);
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
      expect(EventPresence.isMissed(eventOf('e1'), day), isTrue);
    });

    test('a tombstone does not round-trip an export/import', () async {
      await service.setStatus('e1', day, PresenceStatus.missed);
      await service.clearMark('e1', day);

      await service.importData(await service.exportData());
      expect(await allRows(), isEmpty);
    });

    test('clearAllForImport empties the table and the facade', () async {
      await service.setStatus('e1', day, PresenceStatus.missed);
      await service.clearMark('e1', otherDay);

      await service.clearAllForImport();
      expect(await allRows(), isEmpty);
      expect(EventPresence.isMissed(eventOf('e1'), day), isFalse);
    });
  });

  group('event delete cascade', () {
    /// The shape `CalendarEventService.deleteById` runs in one transaction
    /// since v28: the event tombstones, and both per-day tables — marks and
    /// descriptions — tombstone with it.
    Future<void> deleteEvent(String eventId) async {
      await db.transaction(() async {
        await db.calendarEventDao.softDeleteById(eventId);
        await db.eventAbsenceDao.tombstoneForEvent(eventId);
        await db.eventOccurrenceDao.tombstoneForEvent(eventId);
      });
      await service.refreshAfterEventRemoval();
    }

    setUp(() async {
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
    });

    test('tombstones every live mark and leaves the facade clean', () async {
      await service.setStatus('e1', day, PresenceStatus.missed);
      await service.setStatus('e1', otherDay, PresenceStatus.missed);
      await service.clearMark('e1', otherDay);
      await service.setStatus('e2', day, PresenceStatus.missed);

      await deleteEvent('e1');

      // The parent is a tombstone now, so its children are too: delete and
      // marks merge as one act instead of the marks outliving the event.
      final rows = await allRows();
      expect(rows, hasLength(3));
      for (final row in rows.where((r) => r.eventId == 'e1')) {
        expect(row.isDeleted, isTrue);
        expect(row.deletedAt, isNotNull);
      }
      expect(await db.eventAbsenceDao.getActive(), hasLength(1));
      expect(EventPresence.isMissed(eventOf('e1'), day), isFalse);
      expect(EventPresence.isMissed(eventOf('e2'), day), isTrue);
    });

    test(
      'bumps live marks once and leaves existing tombstones alone',
      () async {
        await service.setStatus('e1', day, PresenceStatus.missed);
        await service.setStatus('e1', otherDay, PresenceStatus.missed);
        await service.clearMark('e1', otherDay);
        final alreadyDead = await rowFor('e1', otherDay);

        await deleteEvent('e1');

        expect((await rowFor('e1', day)).version, 2);
        // Rewriting a row that was already tombstoned would invent an ordering
        // event out of nothing.
        final untouched = await rowFor('e1', otherDay);
        expect(untouched.version, alreadyDead.version);
        expect(untouched.hlcTimestamp, alreadyDead.hlcTimestamp);
      },
    );

    test('per-day descriptions tombstone alongside the marks', () async {
      await db.eventOccurrenceDao.upsert(
        EventOccurrenceDescriptionsCompanion.insert(
          eventId: 'e1',
          day: day,
          description: 'skipped, sore knee',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await deleteEvent('e1');

      // Since v28 they carry the CRDT block too, so all three tables die
      // together with one merge order instead of one of them vanishing.
      expect(await db.eventOccurrenceDao.getActive(), isEmpty);
      expect(
        await db.select(db.eventOccurrenceDescriptions).get(),
        hasLength(1),
      );
    });

    test('the bulk wipe still hard-deletes everything', () async {
      await service.setStatus('e1', day, PresenceStatus.missed);
      await service.clearMark('e1', otherDay);

      await db.eventAbsenceDao.deleteAll();
      await service.refreshAfterEventRemoval();

      // "Delete all events" promises the removal is permanent, and the backup
      // import re-inserts backed-up ids over the wipe — tombstoning either
      // would leave dead rows for no one to merge with.
      expect(await allRows(), isEmpty);
      expect(EventPresence.isMissed(eventOf('e1'), day), isFalse);
    });
  });
}
