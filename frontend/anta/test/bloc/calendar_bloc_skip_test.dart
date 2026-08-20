import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';

/// The exact **inverse** of `calendar_bloc_presence_test.dart`, and that is the
/// whole point of the file.
///
/// A missed day still occurs, so presence must leave the day cache warm and
/// ride `occurrenceRevision`. A cancelled day does not occur, so a skip must
/// invalidate the cache and ride `membershipRevision` — otherwise the grid
/// keeps drawing an occurrence `occursOn` already denies, for up to 512
/// memoized days, and the agenda never rescans.
///
/// `CalendarEventService` is a `getInstance()` singleton over `AppDatabase`
/// with no injection seam, so this drives the real stack over a throwaway
/// database rather than a fake.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;

  final day = DateTime.utc(2026, 8, 10);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_skip');
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

  /// Dispatches and waits for the emit it causes. `pumpEventQueue` is not
  /// enough: every handler awaits real SQLite work on drift's background
  /// isolate.
  Future<void> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    await next;
  }

  CalendarPageLoaded loaded() => bloc.state as CalendarPageLoaded;

  setUp(() async {
    final service = await CalendarEventService.getInstance();
    await service.deleteAll();
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'e1',
          title: 'Leg day',
          categoryId: 'gym',
          startDate: DateTime.utc(2026, 8, 1),
          rule: const DailyRecurrence(),
          tracksPresence: true,
        ),
      ),
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  test('a skip removes the occurrence from the day lookup', () async {
    // Warm the cache first: without invalidation this is exactly the entry
    // that would keep being served.
    expect(bloc.eventsForDay(day), hasLength(1));

    await dispatch(SetOccurrenceSkipped(eventId: 'e1', day: day));

    expect(bloc.eventsForDay(day), isEmpty);
    expect(EventSkips.isSkipped('e1', day), isTrue);
  });

  test('other days keep occurring', () async {
    await dispatch(SetOccurrenceSkipped(eventId: 'e1', day: day));

    expect(bloc.eventsForDay(day.add(const Duration(days: 1))), hasLength(1));
  });

  test('restoring brings the occurrence back', () async {
    await dispatch(SetOccurrenceSkipped(eventId: 'e1', day: day));
    expect(bloc.eventsForDay(day), isEmpty);

    await dispatch(ClearOccurrenceSkipped(eventId: 'e1', day: day));

    expect(bloc.eventsForDay(day), hasLength(1));
  });

  test('a skip bumps membershipRevision, not occurrenceRevision', () async {
    final before = loaded();

    await dispatch(SetOccurrenceSkipped(eventId: 'e1', day: day));

    // The agenda must rescan (membership) but must not be told the overlay
    // changed — those are different consumers with different costs.
    expect(loaded().membershipRevision, before.membershipRevision + 1);
    expect(loaded().occurrenceRevision, before.occurrenceRevision);
  });

  test('a presence mark leaves membershipRevision alone', () async {
    final before = loaded();

    await dispatch(SetOccurrenceMissed(eventId: 'e1', day: day));

    expect(loaded().occurrenceRevision, before.occurrenceRevision + 1);
    expect(loaded().membershipRevision, before.membershipRevision);
    // And the occurrence is still there — a missed day is a rendering
    // concern, never a membership one.
    expect(bloc.eventsForDay(day), hasLength(1));
  });

  test('deleting the event clears its skips', () async {
    await dispatch(SetOccurrenceSkipped(eventId: 'e1', day: day));
    expect(EventSkips.isSkipped('e1', day), isTrue);

    await dispatch(const DeleteCalendarEvent(eventId: 'e1'));

    // A leaked skip would hide occurrences of whatever event next takes the
    // id — worse than a leaked presence mark, which only mis-draws.
    expect(EventSkips.isSkipped('e1', day), isFalse);
  });
}
