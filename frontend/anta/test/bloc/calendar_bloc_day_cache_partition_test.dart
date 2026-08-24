import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';

/// Guards the 3.2a grid partition (`EventAgenda.partitionForWindow`, cached
/// by `CalendarBloc._partitionFor`) against serving a day out of an event set
/// that no longer exists.
///
/// A miss inside the focused window now reads a per-window partition instead
/// of scanning `allEvents` directly, so every mutation that can change which
/// events occur on which day — create, update, delete, and a skip — must
/// still be visible on the very next lookup, including for a day whose cache
/// entry was never touched by the mutation itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_day_cache_partition');
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
    final service = await CalendarEventService.getInstance();
    await service.deleteAll();
    await service.upsert(
      CalendarEvent(
        id: 'e1',
        title: 'Event 1',
        categoryId: 'gym',
        startDate: DateTime.utc(2020, 1, 1),
        rule: const DailyRecurrence(),
      ),
    );
    await service.upsert(
      CalendarEvent(
        id: 'e2',
        title: 'Event 2',
        categoryId: 'gym',
        startDate: DateTime.utc(2020, 1, 1),
        rule: const DailyRecurrence(),
      ),
    );
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    expect((bloc.state as CalendarPageLoaded).allEvents, hasLength(2));
  });

  tearDown(() async {
    await bloc.close();
  });

  test('creating an event is visible on its own day', () async {
    final today = (bloc.state as CalendarPageLoaded).focusedDay;
    final newDay = today.add(const Duration(days: 10));

    // Read a day first so the window partition is built from the two seeded
    // events, before the new one exists.
    bloc.eventsForDay(today);
    expect(bloc.eventsForDay(newDay).map((e) => e.id), isNot(contains('new')));

    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'new',
          title: 'New event',
          categoryId: 'gym',
          startDate: newDay,
          rule: const OneTimeRecurrence(),
        ),
      ),
    );

    expect(bloc.eventsForDay(newDay).map((e) => e.id), contains('new'));
  });

  test(
    'updating an event to a one-time rule moves it off its old days',
    () async {
      final today = (bloc.state as CalendarPageLoaded).focusedDay;
      final laterDay = today.add(const Duration(days: 10));

      // e1 is daily at setup; reading `today` builds the partition while it
      // still recurs.
      expect(bloc.eventsForDay(today).map((e) => e.id), contains('e1'));

      await dispatch(
        UpdateCalendarEvent(
          event: CalendarEvent(
            id: 'e1',
            title: 'Event 1',
            categoryId: 'gym',
            startDate: laterDay,
            rule: const OneTimeRecurrence(),
          ),
        ),
      );

      expect(bloc.eventsForDay(today).map((e) => e.id), isNot(contains('e1')));
      expect(bloc.eventsForDay(laterDay).map((e) => e.id), contains('e1'));
    },
  );

  test(
    'deleting an event drops it from a day never looked up before',
    () async {
      final today = (bloc.state as CalendarPageLoaded).focusedDay;
      final otherDay = today.add(const Duration(days: 15));

      // Builds the partition from both events.
      expect(
        bloc.eventsForDay(today).map((e) => e.id),
        containsAll(<String>['e1', 'e2']),
      );

      await dispatch(const DeleteCalendarEvent(eventId: 'e2'));

      expect(
        bloc.eventsForDay(otherDay).map((e) => e.id),
        isNot(contains('e2')),
      );
      expect(bloc.eventsForDay(otherDay).map((e) => e.id), contains('e1'));
    },
  );

  test('skipping an occurrence removes it on that day only', () async {
    final today = (bloc.state as CalendarPageLoaded).focusedDay;
    final otherDay = today.add(const Duration(days: 5));

    // Builds the partition and caches both days while e1 still occurs on
    // both.
    expect(bloc.eventsForDay(today).map((e) => e.id), contains('e1'));
    expect(bloc.eventsForDay(otherDay).map((e) => e.id), contains('e1'));

    await dispatch(SetOccurrenceSkipped(eventId: 'e1', day: otherDay));

    expect(bloc.eventsForDay(otherDay).map((e) => e.id), isNot(contains('e1')));
    expect(bloc.eventsForDay(today).map((e) => e.id), contains('e1'));
  });
}
