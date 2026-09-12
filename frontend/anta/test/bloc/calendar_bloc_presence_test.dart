import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';

/// The presence write path — one event since **v37**, `SetOccurrencePresence`,
/// because "Clear" would have named a write that now *inserts* a `present` row
/// — checked for the property no surface would reveal until it is far too
/// late: it must bump `occurrenceRevision` **and leave the day cache warm**.
///
/// A missed day still occurs (presence is a rendering concern, never a
/// membership one), so invalidating would silently throw away up to 512
/// memoized days on every toggle — invisible except as a slow calendar. The
/// revision bump is the other half: the state is `Equatable`, so without it
/// bloc drops the emit and the agenda's identity memo keeps serving stale rows.
///
/// `CalendarEventService` is a `getInstance()` singleton over `AppDatabase`
/// with no injection seam, so this drives the real stack over a throwaway
/// database rather than a fake.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;

  final day = DateTime.utc(2026, 8, 10);

  /// The event the bloc's own `setUp` creates. `EventPresence.isMissed` takes
  /// the event since **v37** — with no explicit mark it has to read the
  /// event's own default.
  final tracked = CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 8, 1),
    rule: const DailyRecurrence(),
    tracksPresence: true,
  );

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_bloc');
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

  /// Dispatches and waits for the emit it causes.
  ///
  /// `pumpEventQueue` is not enough here: every handler below awaits real
  /// SQLite work on drift's background isolate, and the first one also pays
  /// for schema creation. Listening before adding makes the wait exact.
  Future<void> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    await next;
  }

  setUp(() async {
    final service = await CalendarEventService.getInstance();
    await service.deleteAll();
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    await dispatch(CreateCalendarEvent(event: tracked));
  });

  tearDown(() async => bloc.close());

  int revision() => (bloc.state as CalendarPageLoaded).occurrenceRevision;

  int presenceRevision() => (bloc.state as CalendarPageLoaded).presenceRevision;

  test('marking bumps the revision and keeps the memoized day', () async {
    final warm = bloc.eventsForDay(day);
    expect(warm.map((e) => e.id), ['e1']);
    final before = revision();

    await dispatch(
      SetOccurrencePresence(
        eventId: 'e1',
        day: day,
        status: PresenceStatus.missed,
      ),
    );

    expect(revision(), before + 1);
    expect(EventPresence.isMissed(tracked, day), isTrue);
    // Identity, not equality: the bloc returns the cached list object itself,
    // so a fresh instance would mean the cache was dropped and recomputed.
    expect(identical(bloc.eventsForDay(day), warm), isTrue);
  });

  test('un-marking bumps the revision and keeps the memoized day', () async {
    await dispatch(
      SetOccurrencePresence(
        eventId: 'e1',
        day: day,
        status: PresenceStatus.missed,
      ),
    );

    final warm = bloc.eventsForDay(day);
    final before = revision();

    await dispatch(
      SetOccurrencePresence(
        eventId: 'e1',
        day: day,
        status: PresenceStatus.present,
      ),
    );

    expect(revision(), before + 1);
    expect(EventPresence.isMissed(tracked, day), isFalse);
    expect(identical(bloc.eventsForDay(day), warm), isTrue);
  });

  test('confirming an unmarked day writes a present row', () async {
    final warm = bloc.eventsForDay(day);
    final before = revision();
    final beforePresence = presenceRevision();

    await dispatch(
      SetOccurrencePresence(
        eventId: 'e1',
        day: day,
        status: PresenceStatus.present,
      ),
    );

    // Since v37 confirming a day is a write, not the removal of one: on an
    // assume-absent event the row is the *only* thing that can make the day
    // read attended, so a handler that treated "present" as "clear" would
    // leave the tap with nothing to show for it.
    expect(EventPresence.marksFor('e1')[day], PresenceStatus.present);
    // One handler, both counters — the grid reads presence through
    // `DayBarsResolver` and the panel through `occurrenceRevision`, and a
    // missing bump on either side ships a permanently stale surface.
    expect(revision(), before + 1);
    expect(presenceRevision(), beforePresence + 1);
    // Presence is a painting concern, so the memoized day survives untouched.
    expect(identical(bloc.eventsForDay(day), warm), isTrue);
  });

  test(
    'a marked day still occurs — presence never changes membership',
    () async {
      await dispatch(
        SetOccurrencePresence(
          eventId: 'e1',
          day: day,
          status: PresenceStatus.missed,
        ),
      );

      expect(bloc.eventsForDay(day).map((e) => e.id), ['e1']);
    },
  );
}
