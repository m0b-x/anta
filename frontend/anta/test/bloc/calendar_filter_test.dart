import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_grid_filters.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/utils/event_agenda.dart';

/// Guards the grid's side of `CalendarGridFilters`: that every axis actually
/// reaches `eventsForDay`, on both of its paths, and that the memos it is
/// applied through are invalidated when the filters change.
///
/// The day cache and the window partition are built over the **filtered**
/// list, which is what keeps an active filter free on the 42-cell path. That
/// only holds while a filter change invalidates all of it — the second group
/// is what stands between a future axis and a grid that keeps drawing what the
/// user just hid.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;

  // Anchored on the clock rather than a literal, because the day cache's warm
  // window is three months either side of the focused day — which `_onLoad`
  // sets to today. `nearDay` is served by the window partition, `farDay` by
  // the full-list fallback, and both must honour the same filters.
  final today = EventAgenda.dateOnly(DateTime.now());
  final nearDay = today.add(const Duration(days: 3));
  final farDay = today.add(const Duration(days: 400));

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_filter');
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

  Future<CalendarPageLoaded> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    return await next as CalendarPageLoaded;
  }

  CalendarPageLoaded loaded() => bloc.state as CalendarPageLoaded;

  Set<String> idsOn(DateTime day) =>
      {for (final event in bloc.eventsForDay(day)) event.id};

  setUp(() async {
    final service = await CalendarEventService.getInstance();
    await service.deleteAll();
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    // One daily event per trait under test, all occurring on every day so a
    // missing id is always the filter and never the recurrence.
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'tracked',
          title: 'Leg day',
          categoryId: 'gym',
          startDate: today,
          rule: const DailyRecurrence(),
          tracksPresence: true,
          priority: kMinEventPriority,
        ),
      ),
    );
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'timed',
          title: 'Physio',
          categoryId: 'mobility',
          startDate: today,
          rule: const DailyRecurrence(),
          time: const EventTime(startMinute: 540),
        ),
      ),
    );
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'once',
          title: 'Competition',
          categoryId: 'competition',
          startDate: nearDay,
          priority: kMaxEventPriority,
        ),
      ),
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  group('the filtered list is what the grid reads', () {
    test('unfiltered, every occurrence is there', () async {
      expect(idsOn(nearDay), {'tracked', 'timed', 'once'});
      expect(idsOn(farDay), {'tracked', 'timed'});
    });

    test('a recurrence filter reaches both day paths', () async {
      await dispatch(
        const ChangeCalendarFilters(
          filters: CalendarGridFilters(eventType: AgendaEventType.oneTime),
        ),
      );

      expect(idsOn(nearDay), {'once'});
      expect(idsOn(farDay), isEmpty);
    });

    test('a timing filter reaches both day paths', () async {
      await dispatch(
        const ChangeCalendarFilters(
          filters: CalendarGridFilters(timing: CalendarEventTiming.timed),
        ),
      );

      expect(idsOn(nearDay), {'timed'});
      expect(idsOn(farDay), {'timed'});
    });

    test('a priority filter reaches both day paths', () async {
      await dispatch(
        ChangeCalendarFilters(
          filters: CalendarGridFilters(priorities: {kMinEventPriority}),
        ),
      );

      expect(idsOn(nearDay), {'tracked'});
      expect(idsOn(farDay), {'tracked'});
    });

    test('tracked-only keeps the commitments with attendance', () async {
      await dispatch(
        const ChangeCalendarFilters(
          filters: CalendarGridFilters(trackedOnly: true),
        ),
      );

      expect(idsOn(nearDay), {'tracked'});
    });

    /// The one axis that reads the clock. Its date also lives in
    /// `_visibleEvents`' memo key, so the filtered list cannot outlive a
    /// midnight rollover.
    test('hide-ended drops a commitment that is over', () async {
      await dispatch(
        CreateCalendarEvent(
          event: CalendarEvent(
            id: 'finished',
            title: 'Old program',
            categoryId: 'gym',
            startDate: today.subtract(const Duration(days: 60)),
            rule: const DailyRecurrence(),
            endDate: today.subtract(const Duration(days: 1)),
            retroactive: true,
          ),
        ),
      );
      final past = today.subtract(const Duration(days: 10));
      expect(idsOn(past), contains('finished'));

      await dispatch(
        const ChangeCalendarFilters(
          filters: CalendarGridFilters(hideEnded: true),
        ),
      );

      expect(idsOn(past), isNot(contains('finished')));
      // Everything still running is untouched.
      expect(idsOn(nearDay), {'tracked', 'timed', 'once'});
    });

    test('axes compose', () async {
      await dispatch(
        const ChangeCalendarFilters(
          filters: CalendarGridFilters(
            eventType: AgendaEventType.recurring,
            timing: CalendarEventTiming.allDay,
          ),
        ),
      );

      expect(idsOn(nearDay), {'tracked'});
    });
  });

  group('memo invalidation', () {
    /// Reads a day *before* filtering so it is memoized, then filters: a day
    /// cache that survived the change would keep serving the hidden event.
    test('a warm day is recomputed after a filter change', () async {
      expect(idsOn(nearDay), contains('once'));

      await dispatch(
        const ChangeCalendarFilters(
          filters: CalendarGridFilters(eventType: AgendaEventType.recurring),
        ),
      );

      expect(idsOn(nearDay), isNot(contains('once')));

      await dispatch(
        const ChangeCalendarFilters(filters: CalendarGridFilters.none),
      );

      expect(idsOn(nearDay), contains('once'));
    });

    /// The sheet returns a fresh instance on every Apply, so an unchanged set
    /// must be compared by value — otherwise tapping Apply on an untouched
    /// sheet throws away four memos and repaints 42 cells.
    test('an equal filter set is not re-emitted', () async {
      final before = loaded();

      bloc.add(
        ChangeCalendarFilters(
          filters: CalendarGridFilters(
            hiddenCategoryIds: {...before.filters.hiddenCategoryIds},
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(identical(before, bloc.state), isTrue);
    });

    /// The trap the whole occurrence tier exists around: presence normally
    /// changes painting, not membership, so the presence handlers leave the
    /// day cache warm. With `missedOnly` on they must stop doing that, or the
    /// grid keeps drawing a day it has already been told to re-filter.
    test('a presence mark reaches a warm day while missed-only is on', () async {
      await dispatch(
        const ChangeCalendarFilters(
          filters: CalendarGridFilters(missedOnly: true),
        ),
      );

      expect(idsOn(nearDay), isEmpty);

      await dispatch(SetOccurrenceMissed(eventId: 'tracked', day: nearDay));

      expect(idsOn(nearDay), {'tracked'});

      await dispatch(ClearOccurrenceMissed(eventId: 'tracked', day: nearDay));

      expect(idsOn(nearDay), isEmpty);
    });

    /// The other half of the same gate: with no occurrence axis active, a
    /// presence tick must stay as cheap as it has always been, leaving the
    /// memoized days untouched.
    test('a presence mark leaves the day memo alone otherwise', () async {
      final before = bloc.eventsForDay(nearDay);

      await dispatch(SetOccurrenceMissed(eventId: 'tracked', day: nearDay));

      expect(identical(before, bloc.eventsForDay(nearDay)), isTrue);

      await dispatch(ClearOccurrenceMissed(eventId: 'tracked', day: nearDay));
    });

    test('an unrelated emission keeps the filter instance', () async {
      final before = await dispatch(
        const ChangeCalendarFilters(
          filters: CalendarGridFilters(trackedOnly: true),
        ),
      );

      final after = await dispatch(ChangeFocusedDay(focusedDay: farDay));

      // `sameGridInputs` compares filters by identity, which is only sound
      // because copyWith passes the same instance through.
      expect(identical(before.filters, after.filters), isTrue);
    });
  });

  group('the panel opt-out', () {
    test('allEventsForDay ignores every narrowing axis', () async {
      await dispatch(
        const ChangeCalendarFilters(
          filters: CalendarGridFilters(
            trackedOnly: true,
            panelShowsAll: true,
          ),
        ),
      );

      expect(idsOn(nearDay), {'tracked'});
      expect(
        {for (final e in bloc.allEventsForDay(nearDay)) e.id},
        {'tracked', 'timed', 'once'},
      );
    });

    /// The second memo only fills while the two answers differ, so with
    /// nothing filtered the unfiltered read is the *same list instance* the
    /// grid already has.
    test('with nothing filtered it delegates outright', () async {
      final filtered = bloc.eventsForDay(nearDay);

      expect(identical(bloc.allEventsForDay(nearDay), filtered), isTrue);
    });

    test('it is recomputed after a change to the event set', () async {
      await dispatch(
        const ChangeCalendarFilters(
          filters: CalendarGridFilters(
            trackedOnly: true,
            panelShowsAll: true,
          ),
        ),
      );
      expect(bloc.allEventsForDay(nearDay), hasLength(3));

      await dispatch(const DeleteCalendarEvent(eventId: 'once'));

      expect(bloc.allEventsForDay(nearDay), hasLength(2));
    });
  });

  group('surviving a reload', () {
    /// `_onLoad` emits a **fresh** `CalendarPageLoaded`, so without the bloc
    /// holding the filters a backup restore or a database switch would
    /// silently clear whatever the user was filtering by — and the persisted
    /// set would be contradicted by the very next load.
    test('a reload keeps the filters', () async {
      await dispatch(
        const ChangeCalendarFilters(
          filters: CalendarGridFilters(trackedOnly: true),
        ),
      );

      final reloaded = await dispatch(const LoadCalendarEvents());

      expect(reloaded.filters.trackedOnly, isTrue);
      expect(idsOn(nearDay), {'tracked'});
    });

    /// The page restores the persisted set as soon as settings resolve, which
    /// can beat the first load. That dispatch has nowhere to land unless the
    /// bloc records it while still `CalendarPageInitial`.
    test('filters dispatched before the first load are not dropped', () async {
      final service = await CalendarEventService.getInstance();
      final early = CalendarBloc(service: service);
      addTearDown(early.close);

      early.add(
        const ChangeCalendarFilters(
          filters: CalendarGridFilters(trackedOnly: true),
        ),
      );
      final next = early.stream.first.timeout(const Duration(seconds: 30));
      early.add(const LoadCalendarEvents());
      final loaded = await next as CalendarPageLoaded;

      expect(loaded.filters.trackedOnly, isTrue);
    });
  });
}
