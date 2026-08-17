// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/event_occurrence_service.dart';

import '../database/support/db_test_support.dart';

/// Runs the real DAO, the real CRDT stamping and the real facade against
/// `NativeDatabase.memory()`, the way the `test/database` suite does.
///
/// Two things changed under this feature in v28 and neither is visible on
/// screen: the scope gate moved from one global setting onto the event, and
/// "reset this day" became a **tombstone** instead of a delete. A tombstoned
/// reset and a deleted one render identically — the template comes back either
/// way — so only the columns nothing draws can tell them apart, and only until
/// a merge depends on them.
void main() {
  late AppDatabase db;
  late EventOccurrenceService service;

  final day = DateTime.utc(2026, 8, 10);
  final otherDay = DateTime.utc(2026, 8, 11);

  setUp(() async {
    EventOccurrenceService.reset();
    db = await openTestDatabase();
    service = await EventOccurrenceService.forTesting(db);
  });

  tearDown(() async {
    EventOccurrenceService.reset();
    await db.close();
  });

  Future<List<EventOccurrenceRow>> allRows() =>
      db.select(db.eventOccurrenceDescriptions).get();

  Future<EventOccurrenceRow> rowFor(String eventId, DateTime value) {
    return (db.select(db.eventOccurrenceDescriptions)..where(
          (o) => o.eventId.equals(eventId) & o.day.equals(value),
        ))
        .getSingle();
  }

  CalendarEvent event({
    bool perOccurrenceDescriptions = true,
    RecurrenceRule rule = const DailyRecurrence(),
    String? description = 'shared template',
  }) {
    return CalendarEvent(
      id: 'e1',
      title: 'Leg day',
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 8, 1),
      rule: rule,
      description: description,
      perOccurrenceDescriptions: perOccurrenceDescriptions,
    );
  }

  group('facade', () {
    test('a written day publishes, a reset day does not', () async {
      await service.setDescription('e1', day, 'squats felt heavy');
      expect(OccurrenceDescriptions.overrideFor('e1', day), 'squats felt heavy');

      await service.clearDescription('e1', day);
      // The row is still there — the cache is built from live rows only, which
      // is what makes the tombstone invisible above the DAO.
      expect(OccurrenceDescriptions.overrideFor('e1', day), isNull);
      expect(await allRows(), hasLength(1));
      expect(OccurrenceDescriptions.hasAnyOverride('e1'), isFalse);
    });

    test('an empty override still wins over the template', () async {
      await service.setDescription('e1', day, '');

      // A deliberately blanked day is a live row holding `''`; only a missing
      // (or tombstoned) row falls back.
      expect(OccurrenceDescriptions.overrideFor('e1', day), '');
      expect(OccurrenceDescriptions.descriptionFor(event(), day), '');
    });

    test('every republish bumps the revision', () async {
      final start = OccurrenceDescriptions.revision;
      await service.setDescription('e1', day, 'squats felt heavy');
      expect(OccurrenceDescriptions.revision, greaterThan(start));

      final afterWrite = OccurrenceDescriptions.revision;
      await service.clearDescription('e1', day);
      expect(OccurrenceDescriptions.revision, greaterThan(afterWrite));
    });

    test('reset clears the singleton and the facade', () async {
      await service.setDescription('e1', day, 'squats felt heavy');

      EventOccurrenceService.reset();
      expect(OccurrenceDescriptions.overrideFor('e1', day), isNull);

      // A fresh instance over the same database republishes what is stored.
      final rebound = await EventOccurrenceService.forTesting(db);
      expect(identical(rebound, service), isFalse);
      expect(OccurrenceDescriptions.overrideFor('e1', day), 'squats felt heavy');
    });

    test('appliesTo follows the event flag, one-time excluded', () {
      expect(OccurrenceDescriptions.appliesTo(event()), isTrue);
      // The global switch is gone: the scope is the event's own choice, so two
      // events side by side can disagree.
      expect(
        OccurrenceDescriptions.appliesTo(
          event(perOccurrenceDescriptions: false),
        ),
        isFalse,
      );
      // An event that fires on exactly one day has nothing to separate.
      expect(
        OccurrenceDescriptions.appliesTo(
          event(rule: const OneTimeRecurrence()),
        ),
        isFalse,
      );
      // A specific-dates rule is a list of distinct occasions and does
      // participate — never gate on the editor's `_RepeatMode`, which files
      // specific dates under one-time.
      expect(
        OccurrenceDescriptions.appliesTo(
          event(rule: SpecificDatesRecurrence(dates: {day, otherDay})),
        ),
        isTrue,
      );
    });

    test('descriptionFor falls back to the template once a day is reset', () async {
      await service.setDescription('e1', day, 'squats felt heavy');
      expect(
        OccurrenceDescriptions.descriptionFor(event(), day),
        'squats felt heavy',
      );

      await service.clearDescription('e1', day);
      // The badge-driving read: a reset day is back to the shared text, which
      // is the whole observable meaning of "reset this day".
      expect(
        OccurrenceDescriptions.descriptionFor(event(), day),
        'shared template',
      );
    });

    test('an event with the flag off reads the template on every day', () async {
      await service.setDescription('e1', day, 'squats felt heavy');

      // v24's reversibility rule, kept verbatim: the rows are the user's data
      // and stay dormant rather than being cleaned up.
      expect(
        OccurrenceDescriptions.descriptionFor(
          event(perOccurrenceDescriptions: false),
          day,
        ),
        'shared template',
      );
      expect(await allRows(), hasLength(1));
    });
  });

  group('backup', () {
    test('export carries live overrides only, without CRDT identity', () async {
      await service.setDescription('e1', day, 'squats felt heavy');
      await service.setDescription('e1', otherDay, 'easy run');
      await service.clearDescription('e1', otherDay);

      final exported = await service.exportData();
      expect(exported, hasLength(1));
      expect(exported.single['eventId'], 'e1');
      expect(exported.single['dayMs'], day.millisecondsSinceEpoch);
      expect(exported.single['description'], 'squats felt heavy');
      expect(exported.single.keys.toSet(), {
        'eventId',
        'dayMs',
        'description',
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
          'description': 'restored',
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
      // A backup is not a sync channel: the restored day is this device's own
      // live row, never a replayed one.
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
      expect(row.hlcTimestamp, isNotEmpty);
      expect(row.deviceId, 'test-device');
      // Malformed entries are skipped individually, not fatal.
      expect(await allRows(), hasLength(1));
      expect(OccurrenceDescriptions.overrideFor('e1', day), 'restored');
    });

    test('a tombstone does not round-trip an export/import', () async {
      await service.setDescription('e1', day, 'squats felt heavy');
      await service.clearDescription('e1', day);

      await service.importData(await service.exportData());
      expect(await allRows(), isEmpty);
    });

    test('clearAllForImport empties the table and the facade', () async {
      await service.setDescription('e1', day, 'squats felt heavy');
      await service.clearDescription('e1', otherDay);

      await service.clearAllForImport();
      expect(await allRows(), isEmpty);
      expect(OccurrenceDescriptions.overrideFor('e1', day), isNull);
    });
  });

  group('event delete cascade', () {
    /// The shape `CalendarEventService.deleteById` runs in one transaction
    /// since v28: the event tombstones, and both per-day tables tombstone with
    /// it so the whole act keeps one merge order.
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

    test('leaves tombstones, not hard-deleted rows', () async {
      await service.setDescription('e1', day, 'squats felt heavy');
      await service.setDescription('e1', otherDay, 'easy run');
      await service.setDescription('e2', day, 'other event');

      await deleteEvent('e1');

      // v27 left these hard because phase-02 had called them device-local;
      // that premise died with v28, so parent and children merge as one act.
      final rows = await allRows();
      expect(rows, hasLength(3));
      for (final row in rows.where((r) => r.eventId == 'e1')) {
        expect(row.isDeleted, isTrue);
        expect(row.deletedAt, isNotNull);
      }
      expect(await db.eventOccurrenceDao.getActive(), hasLength(1));
      expect(OccurrenceDescriptions.overrideFor('e1', day), isNull);
      expect(OccurrenceDescriptions.overrideFor('e2', day), 'other event');
    });

    test('the bulk wipe still hard-deletes everything', () async {
      await service.setDescription('e1', day, 'squats felt heavy');
      await service.clearDescription('e1', otherDay);

      await service.deleteAll();

      // "Delete all events" promises the removal is permanent, and the backup
      // import re-inserts backed-up ids over the wipe — tombstoning either
      // would leave dead rows for no one to merge with.
      expect(await allRows(), isEmpty);
      expect(OccurrenceDescriptions.overrideFor('e1', day), isNull);
    });
  });
}
