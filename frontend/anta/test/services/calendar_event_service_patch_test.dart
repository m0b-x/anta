import 'package:drift/drift.dart' show QueryExecutor;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_cache_limits.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';

import '../database/support/db_test_support.dart';

void _resetSingletons() {
  CalendarEventService.reset();
  EventOccurrenceService.reset();
  EventPresenceService.reset();
  EventSkipService.reset();
  EventAlertService.reset();
}

/// The event cache maintained by the row instead of by the store
/// (scalability record §5.6, S14): pulled events patched in by id, an event
/// delete and its Undo patching the four child facades in place, and a
/// failed read that says so instead of publishing an empty calendar.
void main() {
  late _FailingCounter counter;
  late AppDatabase db;
  late CalendarEventService service;

  final now = DateTime.utc(2026, 11, 8, 9);

  CalendarEvent eventOf(String id, DateTime start) => CalendarEvent(
    id: id,
    title: id,
    categoryId: 'gym',
    startDate: start,
    rule: const OneTimeRecurrence(),
  );

  /// A row written behind the service, as a pull's merge writes it.
  Future<void> writeBehind(String id, DateTime start, {String? title}) =>
      db.calendarEventDao.upsert(
        CalendarEventsCompanion.insert(
          id: id,
          title: title ?? id,
          category: 'gym',
          startDate: start,
          ruleKind: 'oneTime',
          createdAt: now,
          updatedAt: now,
        ),
      );

  setUp(() async {
    _resetSingletons();
    counter = _FailingCounter();
    db = await openTestDatabase(interceptor: counter);
    await EventOccurrenceService.forTesting(db);
    await EventPresenceService.forTesting(db);
    await EventSkipService.forTesting(db);
    await EventAlertService.forTesting(db);
    service = await CalendarEventService.forTesting(db);
    for (final (id, day) in [
      ('a', 1),
      ('b', 3),
      ('c', 3),
      ('d', 5),
      ('e', 9),
    ]) {
      await service.upsert(eventOf(id, DateTime.utc(2026, 11, day)));
    }
  });

  tearDown(() async {
    _resetSingletons();
    await db.close();
  });

  List<String> eventReads() => [
    for (final s in counter.selects)
      if (s.sql.contains('"calendar_events"')) s.sql,
  ];

  /// The patched cache against what a whole read of the store gives: the
  /// same events, field for field, in the same start order; events sharing a
  /// start may sit in another order (the read orders by start alone).
  Future<void> expectMatchesStore() async {
    final patched = service.events;
    final rows = await db.calendarEventDao.getAll();
    expect({for (final e in patched) e.id}, {for (final r in rows) r.id});
    await service.reload();
    final read = service.events;
    expect(
      [for (final e in patched) e.startDate],
      [for (final e in read) e.startDate],
    );
    expect({for (final e in patched) e.id: e}, {for (final e in read) e.id: e});
  }

  group('applyMerged', () {
    test('a new event lands by its start, in one keyed read', () async {
      await writeBehind('new', DateTime.utc(2026, 11, 3));
      counter.reset();

      expect(await CalendarEventService.applyMerged({'new'}), isTrue);

      expect(eventReads(), hasLength(1));
      expect(eventReads().single, contains(' IN '));
      final ids = [for (final e in service.events) e.id];
      expect(ids.indexOf('new'), greaterThan(ids.indexOf('a')));
      expect(ids.indexOf('new'), lessThan(ids.indexOf('d')));
      await expectMatchesStore();
    });

    test('a partner\'s event the reader stored is patched in as the '
        'partner\'s, as a whole read would have it', () async {
      await writeBehind('theirs', DateTime.utc(2026, 11, 4));
      await db.customStatement(
        "UPDATE calendar_events SET owner_id = 'partner' WHERE id = 'theirs'",
      );
      await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');

      await CalendarEventService.applyMerged({'theirs'});

      final byId = {for (final e in service.events) e.id: e};
      expect(byId['theirs']!.fromPartner, isTrue);
      expect(byId['a']!.fromPartner, isFalse);
      await expectMatchesStore();
    });

    test('an update that moves the start day moves the event', () async {
      await writeBehind('a', DateTime.utc(2026, 11, 7), title: 'moved');
      counter.reset();

      await CalendarEventService.applyMerged({'a'});

      expect(eventReads(), hasLength(1));
      expect([for (final e in service.events) e.id], ['b', 'c', 'd', 'a', 'e']);
      await expectMatchesStore();
    });

    test('an update in place keeps its position', () async {
      final before = [for (final e in service.events) e.id];
      await writeBehind('c', DateTime.utc(2026, 11, 3), title: 'renamed');

      await CalendarEventService.applyMerged({'c'});

      expect([for (final e in service.events) e.id], before);
      expect(service.events.firstWhere((e) => e.id == 'c').title, 'renamed');
      await expectMatchesStore();
    });

    test('a tombstone leaves, and its restore comes back', () async {
      await db.customStatement(
        "UPDATE calendar_events SET is_deleted = 1 WHERE id = 'd'",
      );
      await CalendarEventService.applyMerged({'d'});
      expect([for (final e in service.events) e.id], isNot(contains('d')));
      await expectMatchesStore();

      await db.customStatement(
        "UPDATE calendar_events SET is_deleted = 0 WHERE id = 'd'",
      );
      await CalendarEventService.applyMerged({'d'});
      expect([for (final e in service.events) e.id], contains('d'));
      await expectMatchesStore();
    });

    test('a mixed run patches every kind at once', () async {
      await writeBehind('new', DateTime.utc(2026, 11, 2));
      await writeBehind('b', DateTime.utc(2026, 11, 10));
      await writeBehind('e', DateTime.utc(2026, 11, 9), title: 'same day');
      await db.customStatement(
        "UPDATE calendar_events SET is_deleted = 1 WHERE id = 'a'",
      );
      counter.reset();

      await CalendarEventService.applyMerged({'new', 'b', 'e', 'a', 'gone'});

      expect(eventReads(), hasLength(1));
      await expectMatchesStore();
    });

    test('past the limit the whole store is read instead', () async {
      await writeBehind('new', DateTime.utc(2026, 11, 2));
      counter.reset();

      await CalendarEventService.applyMerged({
        'new',
        for (var i = 0; i < CalendarCacheLimits.maxKeyedPatchIds; i++) 'x$i',
      });

      expect(eventReads(), hasLength(1));
      expect(eventReads().single, isNot(contains(' IN ')));
      expect(eventReads().single, contains('ORDER BY "start_date"'));
      await expectMatchesStore();
    });

    test('a keyed read that fails falls back to the whole read', () async {
      await writeBehind('new', DateTime.utc(2026, 11, 2));
      counter
        ..reset()
        ..failNext(' IN ');

      expect(await CalendarEventService.applyMerged({'new'}), isTrue);

      expect(eventReads(), hasLength(1), reason: 'the failed one is not run');
      expect([for (final e in service.events) e.id], contains('new'));
    });

    test('with no instance it reads nothing and builds none', () async {
      CalendarEventService.reset();
      counter.reset();

      expect(await CalendarEventService.applyMerged({'a'}), isTrue);

      expect(counter.count, 0);
      expect(CalendarEventService.isLive, isFalse);
    });
  });

  group('a whole read that fails', () {
    test('keeps the cache, reports it, and is retried whole', () async {
      final before = service.events;
      counter.failNext('ORDER BY "start_date"');

      expect(await service.reload(), isFalse);

      expect(service.events, same(before));
      expect(service.lastLoadFailed, isTrue);

      await writeBehind('new', DateTime.utc(2026, 11, 2));
      counter.reset();
      expect(await CalendarEventService.applyMerged({'new'}), isTrue);
      expect(eventReads().single, contains('ORDER BY "start_date"'));
      expect(service.lastLoadFailed, isFalse);
    });
  });

  group('one event deleted and put back', () {
    final markDay = DateTime.utc(2026, 11, 2);
    final noteDay = DateTime.utc(2026, 11, 3);
    final skipDay = DateTime.utc(2026, 11, 4);
    const alert = EventAlert(id: 'al', eventId: 'a');

    setUp(() async {
      await (await EventPresenceService.forTesting(
        db,
      )).setStatus('a', markDay, PresenceStatus.missed);
      await (await EventOccurrenceService.forTesting(
        db,
      )).setDescription('a', noteDay, 'legs');
      await (await EventSkipService.forTesting(db)).markSkipped('a', skipDay);
      await (await EventAlertService.forTesting(
        db,
      )).replaceForEvent('a', const [alert]);
      // An untouched neighbour, which a patch must leave where it is.
      await (await EventPresenceService.forTesting(
        db,
      )).setStatus('b', markDay, PresenceStatus.present);
    });

    /// Every read of a child table the step ran names the event: none is a
    /// whole-table reload.
    void expectOnlyKeyedChildReads() {
      for (final table in [
        'calendar_event_absences',
        'calendar_event_occurrences',
        'calendar_event_skips',
        'calendar_event_alerts',
      ]) {
        for (final s in counter.selects) {
          if (!s.sql.contains('"$table"')) continue;
          expect(s.args, contains('a'), reason: '$table: ${s.sql}');
        }
      }
    }

    test('the capture reads that event alone', () async {
      counter.reset();

      final captured = await service.captureCascade('a');

      expect(counter.selects, hasLength(4));
      expectOnlyKeyedChildReads();
      expect(captured.marks, {markDay: PresenceStatus.missed});
      expect(captured.descriptions, {noteDay: 'legs'});
      expect(captured.skips, {skipDay});
      expect(captured.alerts.single.id, 'al');
    });

    test('the delete drops its rows in place and reloads no child '
        'wholesale; the restore puts them back from the sets', () async {
      final captured = await service.captureCascade('a');
      final event = service.events.firstWhere((e) => e.id == 'a');
      counter.reset();

      await service.deleteById('a');

      expectOnlyKeyedChildReads();
      // The cascade's own thirteen statements, whose one read is the event
      // row; the four whole-table child reads that followed it are gone.
      expect(counter.count, 13, reason: counter.statements.join('\n'));
      expect(counter.selects, hasLength(1));
      expect(EventPresence.marksFor('a'), isEmpty);
      expect(EventPresence.marksFor('b'), {markDay: PresenceStatus.present});
      expect(OccurrenceDescriptions.overrideFor('a', noteDay), isNull);
      expect(EventSkips.isSkipped('a', skipDay), isFalse);
      expect(EventAlerts.alertsFor('a'), isEmpty);

      counter.reset();
      await service.restoreCascade(
        event,
        marks: captured.marks,
        descriptions: captured.descriptions,
        skips: captured.skips,
        alerts: captured.alerts,
      );

      expectOnlyKeyedChildReads();
      expect(EventPresence.marksFor('a'), {markDay: PresenceStatus.missed});
      expect(OccurrenceDescriptions.overrideFor('a', noteDay), 'legs');
      expect(EventSkips.isSkipped('a', skipDay), isTrue);
      expect([for (final a in EventAlerts.alertsFor('a')) a.id], ['al']);
    });

    test('a delete with no child service live builds none', () async {
      EventOccurrenceService.reset();
      EventPresenceService.reset();
      EventSkipService.reset();
      EventAlertService.reset();
      counter.reset();

      await service.deleteById('a');

      expectOnlyKeyedChildReads();
    });
  });
}

/// [StatementCounter] that can fail the next read whose SQL holds a
/// fragment — the one way to make a DAO read throw under a real service.
class _FailingCounter extends StatementCounter {
  String? _failing;

  void failNext(String fragment) => _failing = fragment;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    final failing = _failing;
    if (failing != null && statement.contains(failing)) {
      _failing = null;
      throw StateError('read failed on purpose');
    }
    return super.runSelect(executor, statement, args);
  }
}
