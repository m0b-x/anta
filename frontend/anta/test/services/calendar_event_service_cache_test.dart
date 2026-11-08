import 'dart:async';

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
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

/// The synchronous cache behind `CalendarEventService.events` — the list the
/// bloc, the agenda and `AlertScheduler.reconcileAll` all read.
///
/// Two things it owes its readers: the start-date order
/// `CalendarEventDao.getAll` documents as the store's contract, between two
/// loads as well as after one; and never reading a write back out again,
/// because a reload holding rows older than the user's own save would hand the
/// scheduler a plan the save is missing from.
void main() {
  late AppDatabase db;
  late _HeldEventRead gate;
  late CalendarEventService service;

  CalendarEvent eventOf(String id, DateTime startDate) => CalendarEvent(
    id: id,
    title: id,
    categoryId: 'gym',
    startDate: startDate,
    rule: const OneTimeRecurrence(),
  );

  setUp(() async {
    _resetSingletons();
    gate = _HeldEventRead();
    db = await openTestDatabase(interceptor: gate);
    // The delete path refreshes all four facades; bound to the same database
    // so it runs as it does in the app instead of logging a tolerated miss.
    await EventOccurrenceService.forTesting(db);
    await EventPresenceService.forTesting(db);
    await EventSkipService.forTesting(db);
    await EventAlertService.forTesting(db);
    service = await CalendarEventService.forTesting(db);
  });

  tearDown(() async {
    gate.release();
    _resetSingletons();
    await db.close();
  });

  List<String> cachedIds() => [for (final event in service.events) event.id];

  test('an upsert lands in start-date order, not at the end', () async {
    await service.upsert(eventOf('march', DateTime.utc(2026, 3, 1)));
    await service.upsert(eventOf('january', DateTime.utc(2026, 1, 1)));
    await service.upsert(eventOf('february', DateTime.utc(2026, 2, 1)));

    expect(cachedIds(), ['january', 'february', 'march']);
    // The same order the one read path answers with, so a reload changes
    // nothing a reader can see.
    expect([
      for (final row in await db.calendarEventDao.getAll()) row.id,
    ], cachedIds());
  });

  test('an edit that moves the start date moves the event with it', () async {
    await service.upsert(eventOf('a', DateTime.utc(2026, 1, 1)));
    await service.upsert(eventOf('b', DateTime.utc(2026, 2, 1)));

    await service.upsert(eventOf('a', DateTime.utc(2026, 3, 1)));

    expect(cachedIds(), ['b', 'a']);
  });

  test('a new event is cached with the createdAt its row holds', () async {
    await service.upsert(eventOf('fresh', DateTime.utc(2026, 1, 1)));

    final row = (await db.calendarEventDao.getAll()).single;
    expect(service.events.single.createdAt, isNotNull);
    expect(service.events.single.createdAt, row.createdAt);

    await service.reload();
    expect(service.events.single.createdAt, row.createdAt);
  });

  test('an edit without createdAt caches the first save\'s', () async {
    await service.upsert(eventOf('a', DateTime.utc(2026, 1, 1)));
    final created = service.events.single.createdAt;

    await service.upsert(eventOf('a', DateTime.utc(2026, 3, 1)));

    expect(service.events.single.createdAt, created);
    expect((await db.calendarEventDao.getAll()).single.createdAt, created);
  });

  /// A stored event copied under a fresh id carries the original's date,
  /// while the insert stamps its own: the cache must hold the row's.
  test(
    'a new id carrying another event\'s createdAt caches the row\'s',
    () async {
      final carried = DateTime(2020, 1, 1);
      await service.upsert(
        eventOf('copy', DateTime.utc(2026, 1, 1)).copyWith(createdAt: carried),
      );

      final row = (await db.calendarEventDao.getAll()).single;
      expect(row.createdAt, isNot(carried));
      expect(service.events.single.createdAt, row.createdAt);
    },
  );

  test('a save inside a reload is not read back out of the cache', () async {
    await service.upsert(eventOf('kept', DateTime.utc(2026, 1, 1)));
    // The reload's rows are held, so the save below commits after they were
    // read: replacing the cache with them would drop the saved event, and the
    // alert pass the save provokes plans from this very list.
    gate.holdNextEventRead();
    final reload = service.reload();
    await pumpEventQueue();
    expect(gate.held, isTrue);

    await service.upsert(eventOf('saved', DateTime.utc(2026, 2, 1)));
    expect(cachedIds(), ['kept', 'saved']);

    gate.release();
    await reload;

    expect(cachedIds(), ['kept', 'saved']);
  });

  test('a delete inside a reload stays deleted', () async {
    await service.upsert(eventOf('kept', DateTime.utc(2026, 1, 1)));
    await service.upsert(eventOf('gone', DateTime.utc(2026, 2, 1)));
    gate.holdNextEventRead();
    final reload = service.reload();
    await pumpEventQueue();
    expect(gate.held, isTrue);

    await service.deleteById('gone');

    gate.release();
    await reload;

    expect(cachedIds(), ['kept']);
  });

  test('a pull merged while the instance is still being built reaches it '
      '(S13)', () async {
    await service.upsert(eventOf('pulled', DateTime.utc(2026, 1, 1)));
    CalendarEventService.reset();
    // The construction's rows are read, then held: the merge below commits
    // after them, and the instance the construction publishes is the one the
    // bloc seeds from without a reload of its own.
    gate.holdNextEventRead();
    final creating = CalendarEventService.forTesting(db);
    await pumpEventQueue();
    expect(gate.held, isTrue);
    expect(CalendarEventService.isLive, isFalse);

    await db.customStatement(
      "UPDATE calendar_events SET title = 'merged' WHERE id = 'pulled'",
    );
    final refresh = CalendarEventService.refreshAfterSync();
    gate.release();
    final built = await creating;
    await refresh;

    expect(built.events.single.title, 'merged');
    expect(
      identical(await CalendarEventService.forTesting(db), built),
      isTrue,
      reason: 'the refresh reloaded the published instance, built no other',
    );
  });

  test('a construction a database switch overtook never publishes the old '
      'database\'s store (S14)', () async {
    await service.upsert(eventOf('old', DateTime.utc(2026, 1, 1)));
    CalendarEventService.reset();
    gate.holdNextEventRead();
    final creatingA = CalendarEventService.forTesting(db);
    await pumpEventQueue();
    expect(gate.held, isTrue);
    final refresh = CalendarEventService.refreshAfterSync();

    // The switch: the singleton dropped, the new database's instance built.
    CalendarEventService.reset();
    final other = await openTestDatabase();
    addTearDown(other.close);
    final now = DateTime.now();
    await other.calendarEventDao.upsert(
      CalendarEventsCompanion.insert(
        id: 'new',
        title: 'new',
        category: 'gym',
        startDate: DateTime.utc(2026, 2, 1),
        ruleKind: 'oneTime',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final b = await CalendarEventService.forTesting(other);

    gate.release();
    final a = await creatingA;
    await refresh;

    expect(identical(a, b), isTrue, reason: 'the old caller gets the new one');
    expect(identical(await CalendarEventService.forTesting(other), b), isTrue);
    expect([for (final e in b.events) e.id], ['new']);
  });
}

/// Delivers the event table's reload late: the `SELECT` runs at once, so its
/// rows are what the table held when the service asked, and they are handed
/// back only on [release] — the window a reload is open for, in which a save
/// of the user's own lands.
class _HeldEventRead extends QueryInterceptor {
  Completer<void>? _hold;
  bool _armed = false;
  bool held = false;

  /// Holds the next read of `calendar_events`, which is the reload's: one
  /// shot, so the write that follows inside the window runs freely.
  void holdNextEventRead() {
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
    if (_armed && hold != null && statement.contains('calendar_events')) {
      _armed = false;
      held = true;
      await hold.future;
    }
    return rows;
  }
}
