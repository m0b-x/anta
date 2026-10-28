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
