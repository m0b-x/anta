// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/event_presence_service.dart';

import 'support/db_test_support.dart';

/// Guards the change feed on the calendar-side synced tables (R3b): every
/// local write leaves exactly one `sync_outbox` entry per row it touched,
/// carrying that row's HLC and op, and an action that writes several rows —
/// an event delete, a category delete, an alert save — writes them all under
/// one HLC.
///
/// Nothing here is visible in the app. A write that commits without its entry
/// is a change that never leaves the device; two HLCs for one action are a
/// delete another device could merge half of.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<List<SyncOutboxRow>> queued([TableInfo? table]) {
    final query = db.select(db.syncOutbox);
    if (table != null) {
      query.where((o) => o.syncedTable.equals(table.actualTableName));
    }
    return query.get();
  }

  Future<SyncOutboxRow> onlyEntry(TableInfo table) async {
    final rows = await queued(table);
    expect(
      rows,
      hasLength(1),
      reason: 'one entry per touched ${table.actualTableName} row',
    );
    return rows.single;
  }

  /// The stored HLC and version of an id-keyed row, tombstone or not.
  Future<({String hlc, int version})> idRow(TableInfo table, String id) async {
    final row = await db
        .customSelect(
          'SELECT hlc_timestamp, version FROM ${table.actualTableName} '
          'WHERE id = ?',
          variables: [Variable<String>(id)],
        )
        .getSingle();
    return (
      hlc: row.read<String>('hlc_timestamp'),
      version: row.read<int>('version'),
    );
  }

  /// The same for an `{eventId, day}` row.
  Future<({String hlc, int version})> dayRow(
    TableInfo table,
    String eventId,
    DateTime day,
  ) async {
    final row = await db
        .customSelect(
          'SELECT hlc_timestamp, version FROM ${table.actualTableName} '
          'WHERE event_id = ? AND day = ?',
          variables: [Variable<String>(eventId), Variable<DateTime>(day)],
        )
        .getSingle();
    return (
      hlc: row.read<String>('hlc_timestamp'),
      version: row.read<int>('version'),
    );
  }

  CalendarEventsCompanion event(String id, {String category = 'gym'}) {
    return CalendarEventsCompanion.insert(
      id: id,
      title: 'Leg day',
      category: category,
      startDate: DateTime.utc(2026, 1, 1),
      ruleKind: 'daily',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  EventOccurrenceDescriptionsCompanion description(
    String eventId,
    DateTime day,
    String text,
  ) {
    return EventOccurrenceDescriptionsCompanion.insert(
      eventId: eventId,
      day: day,
      description: text,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  EventAlertsCompanion alert(String id, String eventId, {int offset = 0}) {
    return EventAlertsCompanion(
      id: Value(id),
      eventId: Value(eventId),
      offsetMinutes: Value(offset),
    );
  }

  CalendarCategoryAlertsCompanion categoryAlert(
    String id,
    String categoryId, {
    int offset = 0,
  }) {
    return CalendarCategoryAlertsCompanion(
      id: Value(id),
      categoryId: Value(categoryId),
      offsetMinutes: Value(offset),
    );
  }

  // Days on and next to the 2026 DST switches (US 8 Mar / 1 Nov, EU 29 Mar /
  // 25 Oct): the days a local-midnight conversion would land on the wrong
  // side of.
  final springForward = DateTime.utc(2026, 3, 29);
  final fallBack = DateTime.utc(2026, 10, 25);

  group('calendar_events', () {
    test(
      'a create queues the row; an edit coalesces; a delete tombstones',
      () async {
        await db.calendarEventDao.upsert(event('e1'));
        final created = await onlyEntry(db.calendarEvents);
        expect(created.rowKey, 'e1');
        expect(created.op, 'upsert');
        expect(created.hlc, (await idRow(db.calendarEvents, 'e1')).hlc);

        await db.calendarEventDao.upsert(
          event('e1').copyWith(title: const Value('Arm day')),
        );
        final edited = await onlyEntry(db.calendarEvents);
        expect(edited.hlc.compareTo(created.hlc), greaterThan(0));

        await db.calendarEventDao.softDeleteById('e1');
        final deleted = await onlyEntry(db.calendarEvents);
        expect(deleted.op, 'tombstone');
        expect(deleted.hlc, (await idRow(db.calendarEvents, 'e1')).hlc);
      },
    );

    test('an import queues every restored row at its own HLC', () async {
      await db.calendarEventDao.importAll([event('e1'), event('e2')]);

      final rows = await queued(db.calendarEvents);
      expect(rows.map((r) => r.rowKey), unorderedEquals(['e1', 'e2']));
      for (final row in rows) {
        expect(row.op, 'upsert');
        expect(row.hlc, (await idRow(db.calendarEvents, row.rowKey)).hlc);
      }
    });

    test(
      'a category reassignment queues exactly the events it moved',
      () async {
        await db.calendarEventDao.upsert(event('e1', category: 'climb'));
        await db.calendarEventDao.upsert(event('e2', category: 'climb'));
        await db.calendarEventDao.upsert(event('e3', category: 'gym'));
        await db.calendarEventDao.upsert(event('e4', category: 'climb'));
        await db.calendarEventDao.softDeleteById('e4');
        await db.syncOutboxDao.clear();

        final moved = await db.calendarEventDao.reassignCategory(
          'climb',
          'other',
        );

        expect(moved, 2);
        final rows = await queued();
        expect(rows.map((r) => r.rowKey), unorderedEquals(['e1', 'e2']));
        expect(rows.map((r) => r.hlc).toSet(), {
          (await idRow(db.calendarEvents, 'e1')).hlc,
        });
        expect(rows.every((r) => r.op == 'upsert'), isTrue);
      },
    );
  });

  group('the event delete cascade', () {
    test('tombstones every row it owns under one HLC, each queued', () async {
      await db.calendarEventDao.upsert(event('e1'));
      await db.calendarEventDao.upsert(event('e2'));
      await db.eventAbsenceDao.setStatus(
        'e1',
        springForward,
        PresenceStatus.missed,
      );
      await db.eventAbsenceDao.setStatus(
        'e1',
        fallBack,
        PresenceStatus.present,
      );
      await db.eventOccurrenceDao.upsert(
        description('e1', springForward, 'squat'),
      );
      await db.eventSkipDao.markSkipped('e1', fallBack);
      await db.eventAlertDao.replaceForEvent('e1', [
        alert('a1', 'e1'),
        alert('a2', 'e1', offset: 10),
      ]);
      // A bystander's child and an already-cleared mark must stay out.
      await db.eventAbsenceDao.setStatus(
        'e2',
        springForward,
        PresenceStatus.missed,
      );
      await db.eventOccurrenceDao.upsert(description('e1', fallBack, 'rest'));
      await db.eventOccurrenceDao.tombstone('e1', fallBack);
      await db.syncOutboxDao.clear();

      await db.calendarEventDao.tombstoneEventCascade('e1');

      final rows = await queued();
      expect(
        rows.map((r) => (r.syncedTable, r.rowKey)),
        unorderedEquals([
          ('calendar_events', 'e1'),
          ('calendar_event_absences', dayRowKey('e1', springForward)),
          ('calendar_event_absences', dayRowKey('e1', fallBack)),
          ('calendar_event_occurrences', dayRowKey('e1', springForward)),
          ('calendar_event_skips', dayRowKey('e1', fallBack)),
          ('calendar_event_alerts', 'a1'),
          ('calendar_event_alerts', 'a2'),
        ]),
      );
      expect(rows.every((r) => r.op == 'tombstone'), isTrue);
      expect(rows.map((r) => r.hlc).toSet(), {
        (await idRow(db.calendarEvents, 'e1')).hlc,
      });
      expect(
        (await dayRow(db.eventAbsences, 'e1', springForward)).hlc,
        rows.first.hlc,
      );
    });

    test('a repeat queues nothing new', () async {
      await db.calendarEventDao.upsert(event('e1'));
      await db.eventSkipDao.markSkipped('e1', springForward);
      await db.calendarEventDao.tombstoneEventCascade('e1');
      await db.syncOutboxDao.clear();

      await db.calendarEventDao.tombstoneEventCascade('e1');

      expect(await queued(), isEmpty);
    });
  });

  group('the category delete cascade', () {
    test('moves, tombstones and queues everything under one HLC', () async {
      final at = DateTime.utc(2026, 10, 1);
      await db.calendarCategoryDao.insertCategory(
        CalendarCategoriesCompanion(
          id: const Value('climb'),
          name: const Value('Climb'),
          colorValue: const Value(0xFF00FF00),
          iconKey: const Value('event'),
          createdAt: Value(at),
          updatedAt: Value(at),
        ),
      );
      await db.calendarEventDao.upsert(event('e1', category: 'climb'));
      await db.categoryAlertDao.replaceForCategory('climb', [
        categoryAlert('ca1', 'climb'),
        categoryAlert('ca2', 'climb', offset: 30),
      ]);
      await db.syncOutboxDao.clear();

      final deleted = await db.calendarCategoryDao.tombstoneCascade(
        'climb',
        reassignTo: 'other',
      );

      expect(deleted, isTrue);
      final rows = await queued();
      expect(
        rows.map((r) => (r.syncedTable, r.rowKey, r.op)),
        unorderedEquals([
          ('calendar_categories', 'climb', 'tombstone'),
          ('calendar_events', 'e1', 'upsert'),
          ('calendar_category_alerts', 'ca1', 'tombstone'),
          ('calendar_category_alerts', 'ca2', 'tombstone'),
        ]),
      );
      expect(rows.map((r) => r.hlc).toSet(), {
        (await idRow(db.calendarCategories, 'climb')).hlc,
      });
    });

    test('a refused delete moves no event and queues nothing', () async {
      await db.calendarEventDao.upsert(event('e1', category: 'other'));
      await db.calendarEventDao.upsert(event('e2', category: 'gone'));
      await db.categoryAlertDao.replaceForCategory('gone', [
        categoryAlert('ca1', 'gone'),
      ]);
      await db.syncOutboxDao.clear();

      // A built-in, and a category with no live row.
      expect(
        await db.calendarCategoryDao.tombstoneCascade(
          'other',
          reassignTo: 'other',
        ),
        isFalse,
      );
      expect(
        await db.calendarCategoryDao.tombstoneCascade(
          'gone',
          reassignTo: 'other',
        ),
        isFalse,
      );

      expect(await queued(), isEmpty);
      expect((await idRow(db.calendarEvents, 'e1')).version, 1);
      expect((await idRow(db.calendarEvents, 'e2')).version, 1);
      expect((await idRow(db.calendarCategoryAlerts, 'ca1')).version, 1);
    });
  });

  group('the {eventId, day} tables', () {
    test(
      'a presence mark coalesces, and a clear records a tombstone',
      () async {
        await db.eventAbsenceDao.setStatus(
          'e1',
          springForward,
          PresenceStatus.missed,
        );
        final first = await onlyEntry(db.eventAbsences);
        expect(first.rowKey, dayRowKey('e1', springForward));
        expect(first.op, 'upsert');

        await db.eventAbsenceDao.setStatus(
          'e1',
          springForward,
          PresenceStatus.present,
        );
        final flipped = await onlyEntry(db.eventAbsences);
        expect(flipped.hlc.compareTo(first.hlc), greaterThan(0));
        expect(
          flipped.hlc,
          (await dayRow(db.eventAbsences, 'e1', springForward)).hlc,
        );

        await db.eventAbsenceDao.clearMark('e1', springForward);
        expect((await onlyEntry(db.eventAbsences)).op, 'tombstone');
      },
    );

    test('a skip queues the day; an unskip records a tombstone', () async {
      await db.eventSkipDao.markSkipped('e1', fallBack);
      final skipped = await onlyEntry(db.eventSkips);
      expect(skipped.rowKey, dayRowKey('e1', fallBack));
      expect(skipped.hlc, (await dayRow(db.eventSkips, 'e1', fallBack)).hlc);

      await db.eventSkipDao.unskip('e1', fallBack);
      final unskipped = await onlyEntry(db.eventSkips);
      expect(unskipped.op, 'tombstone');
      expect(unskipped.hlc.compareTo(skipped.hlc), greaterThan(0));
    });

    test('a day description queues; a reset records a tombstone', () async {
      await db.eventOccurrenceDao.upsert(
        description('e1', springForward, 'squat'),
      );
      final described = await onlyEntry(db.eventOccurrenceDescriptions);
      expect(described.rowKey, dayRowKey('e1', springForward));

      await db.eventOccurrenceDao.tombstone('e1', springForward);
      final reset = await onlyEntry(db.eventOccurrenceDescriptions);
      expect(reset.op, 'tombstone');
      expect(
        reset.hlc,
        (await dayRow(db.eventOccurrenceDescriptions, 'e1', springForward)).hlc,
      );
    });

    test('imports queue one entry per restored day', () async {
      final now = DateTime.now();
      await db.eventAbsenceDao.importAll([
        EventAbsencesCompanion.insert(
          eventId: 'e1',
          day: springForward,
          createdAt: now,
          updatedAt: now,
          hlcTimestamp: '',
          deviceId: '',
        ),
      ]);
      await db.eventSkipDao.importAll([
        EventSkipsCompanion.insert(
          eventId: 'e1',
          day: fallBack,
          createdAt: now,
          updatedAt: now,
          hlcTimestamp: '',
          deviceId: '',
        ),
      ]);
      await db.eventOccurrenceDao.importAll([
        description('e1', springForward, 'a'),
        description('e1', fallBack, 'b'),
      ]);

      final rows = await queued();
      expect(
        rows.map((r) => (r.syncedTable, r.rowKey)),
        unorderedEquals([
          ('calendar_event_absences', dayRowKey('e1', springForward)),
          ('calendar_event_skips', dayRowKey('e1', fallBack)),
          ('calendar_event_occurrences', dayRowKey('e1', springForward)),
          ('calendar_event_occurrences', dayRowKey('e1', fallBack)),
        ]),
      );
      expect(rows.every((r) => r.op == 'upsert'), isTrue);
      expect(
        rows.firstWhere((r) => r.syncedTable == 'calendar_event_skips').hlc,
        (await dayRow(db.eventSkips, 'e1', fallBack)).hlc,
      );
    });
  });

  group('dayRowKey', () {
    ({String eventId, DateTime day}) parse(String key) {
      final bar = key.lastIndexOf('|');
      return (
        eventId: key.substring(0, bar),
        day: DateTime.fromMillisecondsSinceEpoch(
          int.parse(key.substring(bar + 1)),
          isUtc: true,
        ),
      );
    }

    test('is the event id and the day in epoch milliseconds', () {
      expect(dayRowKey('e1', springForward), 'e1|1774742400000');
    });

    test('round-trips, and is the same in every zone', () {
      for (final day in [
        DateTime.utc(2026, 3, 8),
        springForward,
        fallBack,
        DateTime.utc(2026, 11, 1),
      ]) {
        final key = dayRowKey('e1', day);
        expect(parse(key), (eventId: 'e1', day: day));
        // Drift hands the column back as a local DateTime: the key must not
        // see the difference, wherever the device is.
        expect(dayRowKey('e1', day.toLocal()), key);
        expect(
          dayRowKey(
            'e1',
            DateTime.fromMillisecondsSinceEpoch(day.millisecondsSinceEpoch),
          ),
          key,
        );
      }
    });

    /// The key the backup carries for the one live absence mark: the owning
    /// service's own `exportData`, never a re-derivation of it.
    Future<String> exportedKey() async {
      EventPresenceService.reset();
      addTearDown(EventPresenceService.reset);
      final service = await EventPresenceService.forTesting(db);
      final row = (await service.exportData()).single;
      return '${row['eventId']}|${row['dayMs']}';
    }

    test(
      'a cascade keys a row as its own write did, and as export does',
      () async {
        await db.eventAbsenceDao.setStatus(
          'e1',
          springForward,
          PresenceStatus.missed,
        );
        final exported = await exportedKey();
        await db.eventAbsenceDao.tombstoneForEvent('e1');

        // The write keyed the row from the caller's UTC day, the cascade from
        // the local DateTime drift read back: one entry means one key.
        final entry = await onlyEntry(db.eventAbsences);
        final stored = await db.select(db.eventAbsences).getSingle();
        expect(entry.rowKey, exported);
        expect(entry.rowKey, 'e1|${stored.day.millisecondsSinceEpoch}');
      },
    );

    test(
      'a day carrying milliseconds keys the second the row stores',
      () async {
        final withMillis = springForward.add(const Duration(milliseconds: 123));
        await db.eventAbsenceDao.setStatus(
          'e1',
          withMillis,
          PresenceStatus.missed,
        );

        final entry = await onlyEntry(db.eventAbsences);
        final stored = await db.select(db.eventAbsences).getSingle();
        expect(entry.rowKey, dayRowKey('e1', withMillis));
        expect(entry.rowKey, dayRowKey('e1', stored.day));
        expect(entry.rowKey, await exportedKey());
        expect(entry.rowKey, endsWith('000'));
      },
    );
  });

  group('event alerts', () {
    test('a save queues removals as tombstones and the rest as upserts, '
        'under one HLC', () async {
      await db.eventAlertDao.replaceForEvent('e1', [
        alert('a1', 'e1'),
        alert('a2', 'e1', offset: 10),
        alert('a3', 'e1', offset: 20),
      ]);
      await db.syncOutboxDao.clear();

      await db.eventAlertDao.replaceForEvent('e1', [
        alert('a1', 'e1'),
        alert('a2', 'e1', offset: 15),
        alert('a4', 'e1', offset: 60),
      ]);

      final rows = await queued(db.eventAlerts);
      expect(
        rows.map((r) => (r.rowKey, r.op)),
        unorderedEquals([
          ('a2', 'upsert'),
          ('a3', 'tombstone'),
          ('a4', 'upsert'),
        ]),
      );
      expect(rows.map((r) => r.hlc).toSet(), {
        (await idRow(db.eventAlerts, 'a3')).hlc,
      });
      expect((await idRow(db.eventAlerts, 'a1')).version, 1);
    });

    test('a save that changes nothing queues nothing', () async {
      await db.eventAlertDao.replaceForEvent('e1', [alert('a1', 'e1')]);
      await db.syncOutboxDao.clear();

      await db.eventAlertDao.replaceForEvent('e1', [alert('a1', 'e1')]);

      expect(await queued(), isEmpty);
    });

    test(
      'a removed alert re-added under its id resurrects as an upsert',
      () async {
        await db.eventAlertDao.replaceForEvent('e1', [alert('a1', 'e1')]);
        await db.eventAlertDao.replaceForEvent('e1', const []);
        expect((await onlyEntry(db.eventAlerts)).op, 'tombstone');

        await db.eventAlertDao.replaceForEvent('e1', [alert('a1', 'e1')]);

        final entry = await onlyEntry(db.eventAlerts);
        expect(entry.op, 'upsert');
        expect(entry.hlc, (await idRow(db.eventAlerts, 'a1')).hlc);
        expect(await db.eventAlertDao.getAllActive(), hasLength(1));
      },
    );

    test('an import queues every restored alert', () async {
      final now = DateTime.now();
      await db.eventAlertDao.importAll([
        for (final id in ['a1', 'a2'])
          alert(
            id,
            'e1',
          ).copyWith(createdAt: Value(now), updatedAt: Value(now)),
      ]);

      final rows = await queued(db.eventAlerts);
      expect(rows.map((r) => r.rowKey), unorderedEquals(['a1', 'a2']));
      expect(
        rows.first.hlc,
        (await idRow(db.eventAlerts, rows.first.rowKey)).hlc,
      );
    });
  });

  group('category alerts', () {
    test('a save queues under one HLC; a cascade tombstones', () async {
      await db.categoryAlertDao.replaceForCategory('climb', [
        categoryAlert('ca1', 'climb'),
        categoryAlert('ca2', 'climb', offset: 5),
      ]);
      final saved = await queued(db.calendarCategoryAlerts);
      expect(saved.map((r) => r.rowKey), unorderedEquals(['ca1', 'ca2']));
      expect(saved.map((r) => r.hlc).toSet(), hasLength(1));

      await db.categoryAlertDao.tombstoneForCategory('climb');

      final rows = await queued(db.calendarCategoryAlerts);
      expect(rows, hasLength(2));
      expect(rows.every((r) => r.op == 'tombstone'), isTrue);
      expect(rows.map((r) => r.hlc).toSet(), {
        (await idRow(db.calendarCategoryAlerts, 'ca1')).hlc,
      });
    });

    test('a save that changes nothing queues nothing', () async {
      await db.categoryAlertDao.replaceForCategory('climb', [
        categoryAlert('ca1', 'climb'),
      ]);
      await db.syncOutboxDao.clear();

      await db.categoryAlertDao.replaceForCategory('climb', [
        categoryAlert('ca1', 'climb'),
      ]);

      expect(await queued(), isEmpty);
    });

    test(
      'a removed alert re-added under its id resurrects as an upsert',
      () async {
        await db.categoryAlertDao.replaceForCategory('climb', [
          categoryAlert('ca1', 'climb'),
        ]);
        await db.categoryAlertDao.replaceForCategory('climb', const []);
        expect((await onlyEntry(db.calendarCategoryAlerts)).op, 'tombstone');

        await db.categoryAlertDao.replaceForCategory('climb', [
          categoryAlert('ca1', 'climb'),
        ]);

        final entry = await onlyEntry(db.calendarCategoryAlerts);
        expect(entry.op, 'upsert');
        expect(entry.hlc, (await idRow(db.calendarCategoryAlerts, 'ca1')).hlc);
        expect(await db.categoryAlertDao.getAllActive(), hasLength(1));
      },
    );

    test('an import queues every restored alert', () async {
      final now = DateTime.now();
      await db.categoryAlertDao.importAll([
        categoryAlert(
          'ca1',
          'climb',
        ).copyWith(createdAt: Value(now), updatedAt: Value(now)),
      ]);

      expect((await onlyEntry(db.calendarCategoryAlerts)).rowKey, 'ca1');
    });
  });

  // The four id-keyed saved lists share one write shape, so one set of cases
  // runs against each.
  final savedLists =
      <
        ({
          String name,
          TableInfo Function(AppDatabase) table,
          Future<void> Function(AppDatabase, String id, String name, int order)
          upsert,
          Future<void> Function(AppDatabase, String id) delete,
          Future<void> Function(AppDatabase, List<String> ids)? reorder,
          Future<void> Function(AppDatabase, List<String> ids) import,
        })
      >[
        (
          name: 'calendar_event_templates',
          table: (db) => db.eventTemplates,
          upsert: (db, id, name, order) => db.eventTemplateDao.upsertTemplate(
            EventTemplatesCompanion(
              id: Value(id),
              name: Value(name),
              category: const Value('gym'),
              sortOrder: Value(order),
            ),
          ),
          delete: (db, id) => db.eventTemplateDao.softDeleteById(id),
          reorder: null,
          import: (db, ids) => db.eventTemplateDao.importAll([
            for (final id in ids)
              EventTemplatesCompanion(
                id: Value(id),
                name: Value(id),
                category: const Value('gym'),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
          ]),
        ),
        (
          name: 'event_digests',
          table: (db) => db.eventDigests,
          upsert: (db, id, name, order) => db.eventDigestDao.upsertDigest(
            EventDigestsCompanion(
              id: Value(id),
              name: Value(name),
              payload: const Value('{}'),
              sortOrder: Value(order),
            ),
          ),
          delete: (db, id) => db.eventDigestDao.softDeleteById(id),
          reorder: (db, ids) => db.eventDigestDao.reorder(ids),
          import: (db, ids) => db.eventDigestDao.importAll([
            for (final id in ids)
              EventDigestsCompanion(
                id: Value(id),
                name: Value(id),
                payload: const Value('{}'),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
          ]),
        ),
        (
          name: 'calendar_filter_presets',
          table: (db) => db.calendarFilterPresets,
          upsert: (db, id, name, order) => db.filterPresetDao.upsertPreset(
            CalendarFilterPresetsCompanion(
              id: Value(id),
              name: Value(name),
              filters: const Value('{}'),
              sortOrder: Value(order),
            ),
          ),
          delete: (db, id) => db.filterPresetDao.softDeleteById(id),
          reorder: (db, ids) => db.filterPresetDao.reorder(ids),
          import: (db, ids) => db.filterPresetDao.importAll([
            for (final id in ids)
              CalendarFilterPresetsCompanion(
                id: Value(id),
                name: Value(id),
                filters: const Value('{}'),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
          ]),
        ),
        (
          name: 'overview_views',
          table: (db) => db.overviewViews,
          upsert: (db, id, name, order) => db.overviewViewDao.upsertView(
            OverviewViewsCompanion(
              id: Value(id),
              name: Value(name),
              payload: const Value('{}'),
              sortOrder: Value(order),
            ),
          ),
          delete: (db, id) => db.overviewViewDao.softDeleteById(id),
          reorder: (db, ids) => db.overviewViewDao.reorder(ids),
          import: (db, ids) => db.overviewViewDao.importAll([
            for (final id in ids)
              OverviewViewsCompanion(
                id: Value(id),
                name: Value(id),
                payload: const Value('{}'),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
          ]),
        ),
      ];

  for (final list in savedLists) {
    group(list.name, () {
      test('a create queues; an edit coalesces; a delete tombstones', () async {
        final table = list.table(db);
        expect(table.actualTableName, list.name);
        await list.upsert(db, 'x', 'Mine', 0);
        final created = await onlyEntry(table);
        expect(created.rowKey, 'x');
        expect(created.hlc, (await idRow(table, 'x')).hlc);

        await list.upsert(db, 'x', 'Renamed', 0);
        final edited = await onlyEntry(table);
        expect(edited.hlc.compareTo(created.hlc), greaterThan(0));

        await list.delete(db, 'x');
        final deleted = await onlyEntry(table);
        expect(deleted.op, 'tombstone');
        expect(deleted.hlc, (await idRow(table, 'x')).hlc);
      });

      test('a save that changes nothing writes and queues nothing', () async {
        final table = list.table(db);
        await list.upsert(db, 'x', 'Mine', 0);
        await db.syncOutboxDao.clear();

        await list.upsert(db, 'x', 'Mine', 0);

        expect(await queued(), isEmpty);
        expect((await idRow(table, 'x')).version, 1);
      });

      test('an import queues every restored row', () async {
        final table = list.table(db);
        await list.import(db, ['x', 'y']);

        final rows = await queued(table);
        expect(rows.map((r) => r.rowKey), unorderedEquals(['x', 'y']));
        expect(rows.every((r) => r.op == 'upsert'), isTrue);
        expect(rows.first.hlc, (await idRow(table, rows.first.rowKey)).hlc);
      });

      final reorder = list.reorder;
      if (reorder != null) {
        test(
          'a reorder queues only the rows it moved, under one HLC',
          () async {
            final table = list.table(db);
            await list.upsert(db, 'a', 'A', 0);
            await list.upsert(db, 'b', 'B', 1);
            await list.upsert(db, 'c', 'C', 2);
            await db.syncOutboxDao.clear();

            await reorder(db, ['a', 'c', 'b']);

            final rows = await queued(table);
            expect(rows.map((r) => r.rowKey), unorderedEquals(['b', 'c']));
            expect(rows.map((r) => r.hlc).toSet(), {
              (await idRow(table, 'b')).hlc,
            });
            expect((await idRow(table, 'a')).version, 1);

            await db.syncOutboxDao.clear();
            await reorder(db, ['a', 'c', 'b']);
            expect(await queued(), isEmpty, reason: 'nothing moved');
          },
        );
      }
    });
  }

  // `changesNothing` compares stored values; these pin that every kind of
  // column still reads as a change — a date, a flag, a number, a value
  // cleared to null — and not only text.
  group('a one-field edit writes and queues', () {
    /// Runs [write] and expects it to have bumped [id]'s version once and
    /// queued it at the row's new HLC.
    Future<void> expectWrites(
      TableInfo table,
      String id,
      Future<void> Function() write,
    ) async {
      final before = await idRow(table, id);
      await db.syncOutboxDao.clear();
      await write();
      final after = await idRow(table, id);
      expect(after.version, before.version + 1);
      final entry = await onlyEntry(table);
      expect(entry.rowKey, id);
      expect(entry.hlc, after.hlc);
    }

    test('an event: a date set, moved and cleared; a flag', () async {
      await db.calendarEventDao.upsert(event('e1'));
      Future<void> save(CalendarEventsCompanion entry) =>
          db.calendarEventDao.upsert(entry);

      await expectWrites(
        db.calendarEvents,
        'e1',
        () => save(event('e1').copyWith(endDate: Value(DateTime.utc(2026, 6)))),
      );
      await expectWrites(
        db.calendarEvents,
        'e1',
        () => save(event('e1').copyWith(endDate: Value(DateTime.utc(2026, 7)))),
      );
      await expectWrites(
        db.calendarEvents,
        'e1',
        () => save(
          event('e1').copyWith(
            endDate: Value(DateTime.utc(2026, 7)),
            tintIcon: const Value(false),
          ),
        ),
      );
      await expectWrites(
        db.calendarEvents,
        'e1',
        () => save(
          event(
            'e1',
          ).copyWith(endDate: const Value(null), tintIcon: const Value(false)),
        ),
      );
    });

    test('a template: a flag; a number cleared to null', () async {
      EventTemplatesCompanion template({
        required bool tint,
        required int? startMinute,
      }) {
        return EventTemplatesCompanion(
          id: const Value('t1'),
          name: const Value('Leg day'),
          category: const Value('gym'),
          tintIcon: Value(tint),
          startMinute: Value(startMinute),
        );
      }

      await db.eventTemplateDao.upsertTemplate(
        template(tint: true, startMinute: 600),
      );
      await expectWrites(
        db.eventTemplates,
        't1',
        () => db.eventTemplateDao.upsertTemplate(
          template(tint: false, startMinute: 600),
        ),
      );
      await expectWrites(
        db.eventTemplates,
        't1',
        () => db.eventTemplateDao.upsertTemplate(
          template(tint: false, startMinute: null),
        ),
      );
    });

    test('a preset and a view: a number', () async {
      for (final (table, save) in [
        (
          db.calendarFilterPresets as TableInfo,
          (int order) => db.filterPresetDao.upsertPreset(
            CalendarFilterPresetsCompanion(
              id: const Value('p1'),
              name: const Value('Mine'),
              filters: const Value('{}'),
              sortOrder: Value(order),
            ),
          ),
        ),
        (
          db.overviewViews as TableInfo,
          (int order) => db.overviewViewDao.upsertView(
            OverviewViewsCompanion(
              id: const Value('p1'),
              name: const Value('Mine'),
              payload: const Value('{}'),
              sortOrder: Value(order),
            ),
          ),
        ),
      ]) {
        await save(0);
        await expectWrites(table, 'p1', () => save(3));
      }
    });

    test('a digest: a flag and a number', () async {
      Future<void> save({required bool enabled, required int order}) {
        return db.eventDigestDao.upsertDigest(
          EventDigestsCompanion(
            id: const Value('d1'),
            name: const Value('Week'),
            payload: const Value('{}'),
            enabled: Value(enabled),
            sortOrder: Value(order),
          ),
        );
      }

      await save(enabled: true, order: 0);
      await expectWrites(
        db.eventDigests,
        'd1',
        () => save(enabled: false, order: 0),
      );
      await expectWrites(
        db.eventDigests,
        'd1',
        () => save(enabled: false, order: 2),
      );
    });

    test('an alert: a flag; a number cleared to null', () async {
      EventAlertsCompanion withDay({required bool enabled, int? dayMinute}) {
        return alert(
          'a1',
          'e1',
        ).copyWith(enabled: Value(enabled), dayMinute: Value(dayMinute));
      }

      await db.eventAlertDao.replaceForEvent('e1', [
        withDay(enabled: true, dayMinute: 480),
      ]);
      await expectWrites(
        db.eventAlerts,
        'a1',
        () => db.eventAlertDao.replaceForEvent('e1', [
          withDay(enabled: false, dayMinute: 480),
        ]),
      );
      await expectWrites(
        db.eventAlerts,
        'a1',
        () => db.eventAlertDao.replaceForEvent('e1', [withDay(enabled: false)]),
      );
    });
  });

  group('guards: a write that changes nothing queues nothing', () {
    test('an unchanged event save', () async {
      await db.calendarEventDao.upsert(event('e1'));
      await db.syncOutboxDao.clear();

      // A fresh companion, its dates built in UTC with the clock's
      // milliseconds in the audit columns — what the service hands over.
      await db.calendarEventDao.upsert(event('e1'));

      expect(await queued(), isEmpty);
      expect((await idRow(db.calendarEvents, 'e1')).version, 1);
    });

    test(
      'an unchanged event save over a tombstone still resurrects it',
      () async {
        await db.calendarEventDao.upsert(event('e1'));
        await db.calendarEventDao.softDeleteById('e1');
        await db.syncOutboxDao.clear();

        await db.calendarEventDao.upsert(event('e1'));

        final entry = await onlyEntry(db.calendarEvents);
        expect(entry.op, 'upsert');
        expect(await db.calendarEventDao.getAll(), hasLength(1));
      },
    );

    test('a presence mark it already has', () async {
      await db.eventAbsenceDao.setStatus(
        'e1',
        springForward,
        PresenceStatus.missed,
      );
      await db.syncOutboxDao.clear();
      await db.eventAbsenceDao.setStatus(
        'e1',
        springForward,
        PresenceStatus.missed,
      );
      await db.eventAbsenceDao.clearMark('e1', fallBack);
      expect(await queued(), isEmpty);
    });

    test('a skip already in place, an unskip of nothing', () async {
      await db.eventSkipDao.markSkipped('e1', springForward);
      await db.syncOutboxDao.clear();
      await db.eventSkipDao.markSkipped('e1', springForward);
      await db.eventSkipDao.unskip('e1', fallBack);
      expect(await queued(), isEmpty);
    });

    test('a day description re-saved with the same text', () async {
      await db.eventOccurrenceDao.upsert(
        description('e1', springForward, 'squat'),
      );
      await db.syncOutboxDao.clear();
      await db.eventOccurrenceDao.upsert(
        description('e1', springForward, 'squat'),
      );
      expect(await queued(), isEmpty);
    });

    test('a digest switch set to the value it holds', () async {
      await db.eventDigestDao.upsertDigest(
        const EventDigestsCompanion(
          id: Value('d1'),
          name: Value('Week'),
          payload: Value('{}'),
        ),
      );
      final enabled = (await db.select(db.eventDigests).getSingle()).enabled;
      await db.syncOutboxDao.clear();

      await db.eventDigestDao.setEnabled('d1', enabled);
      expect(await queued(), isEmpty);

      await db.eventDigestDao.setEnabled('d1', !enabled);
      expect(
        (await onlyEntry(db.eventDigests)).hlc,
        (await idRow(db.eventDigests, 'd1')).hlc,
      );
    });
  });

  test('a write that throws inside its transaction leaves no entry', () async {
    await expectLater(
      db.transaction(() async {
        await db.eventSkipDao.markSkipped('e1', springForward);
        await db.calendarEventDao.tombstoneEventCascade('e1');
        throw StateError('the write fails after the rows');
      }),
      throwsStateError,
    );

    expect(await queued(), isEmpty);
    expect(await db.select(db.eventSkips).get(), isEmpty);
  });
}
