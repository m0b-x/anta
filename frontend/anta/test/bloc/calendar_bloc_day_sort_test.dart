import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/utils/event_agenda.dart';

/// Pins the ordering guarantee 3.3 moved upstream.
///
/// `DayBarsResolver` and `DaySummaryResolver` used to copy-and-sort their
/// input per cell per frame. 3.3 deleted both sorts and made `eventsForDay`
/// sort once instead — so the resolvers' stable tie-break passes, and the
/// "events arrive pre-sorted" comments they rest on, now depend entirely on
/// this. Nothing else asserts it: without this file, removing the sort in
/// `eventsForDay` scrambles equal-priority bars back into `allEvents` order
/// and every resolver test still passes, because they were rewritten to feed
/// pre-sorted input.
///
/// Both lookup paths are covered. 3.2a/3.2b split `eventsForDay` into a
/// pruned in-window path and a full-scan fallback for days outside the
/// focused month +/- 3 months, and only the in-window one goes through the
/// partition — an unsorted fallback would surface as bars reordering the
/// moment a user paged far enough away.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;

  final anchor = DateTime.utc(2026, 8, 15);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_day_sort');
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
    // Inserted in an order that is wrong on every axis the comparator ranks:
    // the lowest-priority event goes in last, and the titles descend. Cache
    // order is insertion order, so an unsorted lookup returns exactly this.
    final seeds = <(String, String, int)>[
      ('e-zulu', 'Zulu', 3),
      ('e-alpha', 'Alpha', 3),
      ('e-mike', 'mike', 3),
      ('e-bravo', 'Bravo', 5),
      ('e-urgent', 'Urgent', 1),
    ];
    for (final (id, title, priority) in seeds) {
      await service.upsert(
        CalendarEvent(
          id: id,
          title: title,
          categoryId: 'gym',
          startDate: DateTime.utc(2026, 1, 1),
          rule: const DailyRecurrence(),
          priority: priority,
        ),
      );
    }
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    await dispatch(ChangeFocusedDay(focusedDay: anchor));
  });

  tearDown(() async {
    await bloc.close();
  });

  void expectSorted(List<CalendarEvent> events, String reason) {
    expect(events, hasLength(5), reason: reason);
    final resorted = [...events]..sort(EventAgenda.compareWithinDay);
    expect(
      events.map((e) => e.id).toList(),
      resorted.map((e) => e.id).toList(),
      reason: reason,
    );
    // Anchored so the test fails loudly if the comparator itself changes,
    // rather than silently comparing a wrong order against itself.
    expect(events.map((e) => e.id).toList(), [
      'e-urgent',
      'e-alpha',
      'e-mike',
      'e-zulu',
      'e-bravo',
    ], reason: reason);
  }

  test('a day inside the focused window comes back sorted', () async {
    expectSorted(
      bloc.eventsForDay(anchor),
      'the pruned in-window path must sort before memoizing',
    );
  });

  test('a day outside the focused window comes back sorted', () async {
    // Five months out: past the focused month +/- 3, so `_dayCandidates`
    // falls back to the unpruned scan over every event.
    final far = DateTime.utc(2027, 1, 20);
    expectSorted(
      bloc.eventsForDay(far),
      'the full-scan fallback must sort too',
    );
  });

  test('the memoized second lookup is still sorted', () async {
    bloc.eventsForDay(anchor);
    expectSorted(
      bloc.eventsForDay(anchor),
      'the cached list is the same sorted list',
    );
  });
}
