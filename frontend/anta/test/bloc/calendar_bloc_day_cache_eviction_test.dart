import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';

/// Guards the 3.4 fix to `_dayCache` eviction.
///
/// `eventsForDay` used to clear all 512 entries from inside the lookup once
/// the cache filled up — mid-build, between `eventLoader`'s and
/// `_buildDayCell`'s two lookups of the same cell — which could wipe the very
/// day a frame was in the middle of painting. Eviction now runs only from
/// `_onChangeFocusedDay`, dropping entries outside a window around the newly
/// focused month rather than clearing wholesale on every overflow.
///
/// Uses `CalendarEvent.debugOccursOnCalls` the way
/// `calendar_occurs_on_budget_test.dart` does: a cache hit costs 0 calls, a
/// cold recompute costs one call per event.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const eventCount = 3;

  late Directory tempDir;
  late CalendarBloc bloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'anta_day_cache_eviction',
    );
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
    for (var i = 0; i < eventCount; i++) {
      await service.upsert(
        CalendarEvent(
          id: 'e$i',
          title: 'Event $i',
          categoryId: 'gym',
          startDate: DateTime.utc(2020, 1, 1),
          rule: switch (i % 3) {
            0 => const DailyRecurrence(),
            1 => const WeeklyRecurrence(weekdays: {DateTime.monday}),
            _ => const YearlyRecurrence(),
          },
        ),
      );
    }
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    expect((bloc.state as CalendarPageLoaded).allEvents, hasLength(eventCount));
  });

  tearDown(() async {
    await bloc.close();
  });

  test(
    'a cached day survives the cache exceeding its cap with no focus change',
    () async {
      final windowDay = (bloc.state as CalendarPageLoaded).focusedDay;

      bloc.eventsForDay(windowDay);

      // Flood with enough distinct days, via plain lookups and no
      // `ChangeFocusedDay` in between, to cross `_maxDayCacheEntries` (512) —
      // exactly what the date pickers and the day/timeline panels can do.
      for (var i = 1; i <= 520; i++) {
        bloc.eventsForDay(windowDay.add(Duration(days: i)));
      }

      CalendarEvent.debugOccursOnCalls = 0;
      bloc.eventsForDay(windowDay);

      expect(
        CalendarEvent.debugOccursOnCalls,
        0,
        reason:
            'eventsForDay must never clear the cache from inside the '
            'lookup — only a focus change may evict, and only entries '
            'outside its window',
      );
    },
  );

  test('a focus change evicts only days outside the new window', () async {
    final today = (bloc.state as CalendarPageLoaded).focusedDay;
    final farDay = DateTime.utc(today.year, today.month + 5, 15);
    final nextMonth = DateTime.utc(today.year, today.month + 1, 1);

    bloc.eventsForDay(today);
    bloc.eventsForDay(farDay);

    await dispatch(ChangeFocusedDay(focusedDay: nextMonth));

    CalendarEvent.debugOccursOnCalls = 0;
    bloc.eventsForDay(today);
    expect(
      CalendarEvent.debugOccursOnCalls,
      0,
      reason: 'today stays inside the new focus month ± 3 months',
    );

    CalendarEvent.debugOccursOnCalls = 0;
    bloc.eventsForDay(farDay);
    expect(
      CalendarEvent.debugOccursOnCalls,
      eventCount,
      reason: 'farDay (5 months out) falls outside the retained window',
    );
  });
}
