import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';

import '../database/support/db_test_support.dart';

/// The calendar services are no longer constructed before `runApp`; the first
/// `LoadCalendarEvents` resolves them instead. That makes the handler's own
/// `reload()` redundant on the first pass — building the service already read
/// the table — but load-bearing on every later one, because a category delete
/// reassigns events to `other` behind the service's cache.
///
/// So the guard is "the service was just built", not "the cache is warm", and
/// the second case is what stops someone widening it into a permanent skip.
///
/// The rest cover how the bloc survives its store being replaced underneath it.
/// It lives above `MaterialApp` and is never disposed, so a backup restore or a
/// database switch leaves it holding a store that no longer exists — and every
/// wrong answer here is silent: a stale seed binds to a closed database, a
/// failed seed strands the bloc with every write silently no-oping, and an
/// over-eager freshness claim serves events from before the switch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late StatementCounter counter;
  late CalendarBloc bloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_load');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    await next;
  }

  setUp(() async {
    CalendarEventService.reset();
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
    // The seed is the unawaited future, exactly as DI passes it.
    bloc = CalendarBloc(service: CalendarEventService.forTesting(db));
  });

  tearDown(() async {
    await bloc.close();
    CalendarEventService.reset();
    await db.close();
  });

  test('the first load reads the event table exactly once', () async {
    counter.reset();
    await dispatch(const LoadCalendarEvents());

    expect(
      counter.matching('calendar_events'),
      hasLength(1),
      reason:
          'getInstance() already read the table, so _onLoad must not call '
          'reload() on the first pass. Issued:\n'
          '${counter.statements.join('\n')}',
    );
  });

  test('a later load re-reads and picks up an out-of-band write', () async {
    await dispatch(const LoadCalendarEvents());
    expect((bloc.state as CalendarPageLoaded).allEvents, isEmpty);

    // Written straight to the table, behind the service's cache — the shape a
    // category delete takes, and the reason the guard cannot be permanent.
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
    counter.reset();

    await dispatch(const LoadCalendarEvents());

    expect(
      counter
          .matching('calendar_events')
          .where((sql) => sql.trimLeft().toUpperCase().startsWith('SELECT')),
      hasLength(1),
      reason:
          'The guard is one-shot. Widening it to "skip whenever the cache is '
          'non-empty" would leave the calendar showing pre-settings-change '
          'data. Issued:\n${counter.statements.join('\n')}',
    );
    expect((bloc.state as CalendarPageLoaded).allEvents, hasLength(1));
  });

  test('the bloc resolves its service from an unawaited future', () async {
    await dispatch(const LoadCalendarEvents());

    expect(bloc.state, isA<CalendarPageLoaded>());
    expect((bloc.state as CalendarPageLoaded).allEvents, isEmpty);
  });

  test('a failed seed recovers instead of stranding the bloc', () async {
    await bloc.close();
    final seed = Future<CalendarEventService>.error(
      StateError('database locked'),
    );
    // Mark handled so the error is not reported before the bloc awaits it.
    seed.then((_) {}, onError: (Object _) {});
    bloc = CalendarBloc(service: seed);

    await dispatch(const LoadCalendarEvents());
    expect(bloc.state, isA<CalendarPageLoaded>());

    // The real assertion: the bloc can still *write*. A rejected future stays
    // rejected, so before the fix `_service` stayed null forever and every
    // create/update/delete re-awaited the same failure and silently no-oped —
    // not even a database switch could recover it.
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'after-recovery',
          title: 'Recovered',
          categoryId: 'gym',
          startDate: DateTime.utc(2026, 8, 1),
          rule: const DailyRecurrence(),
        ),
      ),
    );

    expect(
      (bloc.state as CalendarPageLoaded).allEvents.map((e) => e.id),
      contains('after-recovery'),
    );
  });

  group('external replacement', () {
    test('a fresh bloc is not stale', () async {
      expect(bloc.isStale, isFalse);

      await dispatch(const LoadCalendarEvents());

      expect(
        bloc.isStale,
        isFalse,
        reason:
            'Seeding from the current revision rather than a sentinel is what '
            'stops the page double-dispatching against DI\'s own load.',
      );
    });

    test('replacing the store underneath the bloc marks it stale', () async {
      await dispatch(const LoadCalendarEvents());
      expect(bloc.isStale, isFalse);

      // The database-switch path. A backup restore bumps the same counter at
      // the end of importData.
      CalendarEventService.reset();

      expect(
        bloc.isStale,
        isTrue,
        reason:
            'CalendarBloc outlives both a restore and a database switch, so '
            'without this it keeps serving events from a store that is gone.',
      );
    });

    test('a stale seed is never used, even before the first load', () async {
      // The seed resolves against this database...
      await db.calendarEventDao.upsert(
        CalendarEventsCompanion.insert(
          id: 'from-old-store',
          title: 'Old',
          category: 'gym',
          startDate: DateTime.utc(2026, 8, 1),
          ruleKind: 'daily',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await bloc.close();
      final seed = CalendarEventService.forTesting(db);
      await seed;
      bloc = CalendarBloc(service: seed);

      // ...but the store is swapped before the bloc ever loads. Resolving the
      // seed here would bind the bloc to a database that is no longer active.
      CalendarEventService.reset();
      final replacement = await openTestDatabase();
      addTearDown(replacement.close);
      await CalendarEventService.forTesting(replacement);
      await replacement.calendarEventDao.upsert(
        CalendarEventsCompanion.insert(
          id: 'from-new-store',
          title: 'New',
          category: 'gym',
          startDate: DateTime.utc(2026, 8, 1),
          ruleKind: 'daily',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await dispatch(const LoadCalendarEvents());

      expect((bloc.state as CalendarPageLoaded).allEvents.map((e) => e.id), [
        'from-new-store',
      ]);
    });

    test('reloading clears the stale flag', () async {
      await dispatch(const LoadCalendarEvents());
      CalendarEventService.reset();
      expect(bloc.isStale, isTrue);

      // Re-bind to the same in-memory database, as getInstance() would to the
      // newly active one.
      await CalendarEventService.forTesting(db);
      await db.calendarEventDao.upsert(
        CalendarEventsCompanion.insert(
          id: 'restored',
          title: 'Restored',
          category: 'gym',
          startDate: DateTime.utc(2026, 8, 1),
          ruleKind: 'daily',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await dispatch(const LoadCalendarEvents());

      expect(bloc.isStale, isFalse);
      expect((bloc.state as CalendarPageLoaded).allEvents, hasLength(1));
    });
  });
}
