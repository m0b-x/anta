import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/calendar_cache_limits.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_grid_filters.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_window_index.dart';

import '../services/support/event_window_fixture.dart';

/// The bloc's reads outside the grid's seven-month window go through the
/// [EventWindowIndex] (scalability record §5.6, S13): a picker month far from
/// the focus validates the recurring events plus that month's one-time
/// events, never the whole store, and answers exactly what the full scan
/// answered. Its two per-day memos stay under
/// [CalendarCacheLimits.maxDayCacheEntries] however many picker months are
/// paged, without ever dropping a day of the window.
///
/// Drives the real stack over a throwaway database, as
/// `calendar_occurs_on_budget_test.dart` does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarEventService service;

  /// The focus every case pins: the window is May .. November 2026.
  final anchor = DateTime.utc(2026, 8, 15);

  List<DateTime> grid(DateTime firstCell) => [
    for (var i = 0; i < 42; i++)
      DateTime.utc(firstCell.year, firstCell.month, firstCell.day + i),
  ];

  /// June 2024, February 2028 with its 29th, March 2026 with both DST
  /// Sundays: all outside the window.
  final pickerDays = [
    ...grid(DateTime.utc(2024, 5, 27)),
    ...grid(DateTime.utc(2028, 1, 31)),
    ...grid(DateTime.utc(2026, 2, 23)),
  ];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_window_index_bloc');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    service = await CalendarEventService.getInstance();
    await service.tombstoneAll();
    for (final event in seededWindowStore()) {
      await service.upsert(event);
    }
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  tearDown(() => EventWindowIndex.debugFullScan = false);

  Future<CalendarBloc> loaded({
    CalendarGridFilters filters = CalendarGridFilters.none,
  }) async {
    final bloc = CalendarBloc(service: service);
    addTearDown(bloc.close);
    Future<void> dispatch(CalendarPageEvent event) async {
      final next = bloc.stream.first.timeout(const Duration(seconds: 30));
      bloc.add(event);
      await next;
    }

    await dispatch(const LoadCalendarEvents());
    if ((bloc.state as CalendarPageLoaded).focusedDay != anchor) {
      await dispatch(ChangeFocusedDay(focusedDay: anchor));
    }
    if (!filters.isEmpty) {
      await dispatch(ChangeCalendarFilters(filters: filters));
    }
    return bloc;
  }

  List<String> ids(List<CalendarEvent> events) => [
    for (final e in events) e.id,
  ];

  group('the same days as the full scan', () {
    for (final (name, filters) in [
      ('unfiltered', CalendarGridFilters.none),
      (
        'a denylist and priorities',
        const CalendarGridFilters(
          hiddenCategoryIds: {'other'},
          priorities: {1, 3, 5},
        ),
      ),
      (
        'tracked and missed only, the per-occurrence axis',
        const CalendarGridFilters(trackedOnly: true, missedOnly: true),
      ),
    ]) {
      test('$name: eventsForDay and allEventsForDay', () async {
        Future<List<String>> read({required bool full}) async {
          EventWindowIndex.debugFullScan = full;
          final bloc = await loaded(filters: filters);
          return [
            for (final day in pickerDays) ...[
              '$day ${ids(bloc.eventsForDay(day)).join(',')}',
              '$day all ${ids(bloc.allEventsForDay(day)).join(',')}',
            ],
          ];
        }

        final indexed = await read(full: false);
        final full = await read(full: true);
        expect(indexed, full);
        expect(
          indexed.where((line) => line.endsWith(' ')),
          isNot(hasLength(indexed.length)),
          reason: 'the fixture puts events on these days',
        );
      });
    }
  });

  test('a picker month outside the window validates the recurring events '
      'and that month\'s one-time events alone', () async {
    final bloc = await loaded();
    final events = (bloc.state as CalendarPageLoaded).allEvents;
    final recurring = events.where((e) => e.rule is! OneTimeRecurrence).length;
    int oneTimeIn(DateTime day) => events
        .where(
          (e) =>
              e.rule is OneTimeRecurrence &&
              e.startDateUtc.year == day.year &&
              e.startDateUtc.month == day.month,
        )
        .length;
    final month = grid(DateTime.utc(2024, 5, 27));
    final expected = month.fold(
      0,
      (sum, day) => sum + recurring + oneTimeIn(day),
    );

    CalendarEvent.debugOccursOnCalls = 0;
    for (final day in month) {
      bloc.eventsForDay(day);
    }

    expect(CalendarEvent.debugOccursOnCalls, expected);
    expect(
      expected,
      lessThan(42 * events.length ~/ 10),
      reason: 'a tenth of the full scan at most over this store',
    );
  });

  group('the memos stay bounded between month changes', () {
    const flood = CalendarCacheLimits.maxDayCacheEntries + 88;
    final far = [for (var i = 0; i < flood; i++) DateTime.utc(2032, 1, 1 + i)];

    Future<void> expectCapped(
      List<CalendarEvent> Function(DateTime day) read,
    ) async {
      read(anchor);
      for (final day in far) {
        read(day);
      }

      CalendarEvent.debugOccursOnCalls = 0;
      read(anchor);
      expect(
        CalendarEvent.debugOccursOnCalls,
        0,
        reason: 'a day of the window is never evicted by the cap',
      );
      read(far.last);
      expect(CalendarEvent.debugOccursOnCalls, 0, reason: 'the newest stays');
      read(far.first);
      expect(
        CalendarEvent.debugOccursOnCalls,
        greaterThan(0),
        reason: 'the oldest day outside the window went first',
      );
    }

    test('the grid memo', () async {
      final bloc = await loaded();
      await expectCapped(bloc.eventsForDay);
    });

    test("the panel's unfiltered memo", () async {
      final bloc = await loaded(
        filters: const CalendarGridFilters(hiddenCategoryIds: {'other'}),
      );
      await expectCapped(bloc.allEventsForDay);
    });
  });
}
