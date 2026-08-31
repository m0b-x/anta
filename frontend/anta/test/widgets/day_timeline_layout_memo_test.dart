import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/day_timeline_layout.dart';
import 'package:anta/widgets/day_timeline_view.dart';

/// Guard for **5.7**: `DayTimelineView`'s `build` used to call
/// `DayTimelineLayout.compute` on every rebuild, including ones that changed
/// nothing it depends on (a keyboard-visibility tick, a theme rebuild
/// bubbling down from the page).
///
/// The most important case here is presence: `_isMissed` reads
/// `EventPresence`, a static cache the widget's constructor arguments do not
/// capture, so a memo keyed only on `events`/`missedDisplay` would keep
/// serving a layout computed against a stale presence mark after a toggle —
/// the class of bug **1.1** describes. `EventPresence.revision` is folded
/// into the memo key for exactly that reason.
///
/// Counted through `DayTimelineLayout.debugComputeCalls` because the memo has
/// no other seam: `compute`'s output is a fresh object either way, so an
/// output comparison could not tell a cache hit from a cache miss.
void main() {
  final day = DateTime.utc(2026, 8, 10);

  CalendarEvent event(
    String id, {
    String title = 'Event',
    EventTime? time,
    bool tracksPresence = false,
  }) {
    return CalendarEvent(
      id: id,
      title: title,
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 8, 1),
      rule: const DailyRecurrence(),
      time: time,
      tracksPresence: tracksPresence,
    );
  }

  Future<void> pumpTimeline(
    WidgetTester tester,
    List<CalendarEvent> events, {
    CalendarMissedDisplay missedDisplay = CalendarMissedDisplay.faded,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: DayTimelineView(
            day: day,
            events: events,
            onEventTap: (_) {},
            missedDisplay: missedDisplay,
          ),
        ),
      ),
    );
  }

  setUp(() {
    EventPresence.resetCache();
  });

  tearDown(() {
    EventPresence.resetCache();
  });

  testWidgets('an unrelated rebuild with the same inputs reuses the layout', (
    tester,
  ) async {
    final events = [
      event('a', time: const EventTime(startMinute: 540, durationMinutes: 60)),
      event('b', time: const EventTime(startMinute: 600, durationMinutes: 30)),
    ];

    await pumpTimeline(tester, events);
    DayTimelineLayout.debugComputeCalls = 0;

    // Same events list instance, same missedDisplay: nothing the memo keys
    // on has changed, just a plain repaint.
    await pumpTimeline(tester, events);
    await tester.pump();

    expect(DayTimelineLayout.debugComputeCalls, 0);
  });

  testWidgets('a changed events list recomputes', (tester) async {
    final events = [
      event('a', time: const EventTime(startMinute: 540, durationMinutes: 60)),
    ];

    await pumpTimeline(tester, events);
    DayTimelineLayout.debugComputeCalls = 0;

    final nextEvents = [
      event('a', time: const EventTime(startMinute: 540, durationMinutes: 60)),
      event('b', time: const EventTime(startMinute: 600, durationMinutes: 30)),
    ];
    await pumpTimeline(tester, nextEvents);

    expect(DayTimelineLayout.debugComputeCalls, 1);
  });

  testWidgets('a changed missedDisplay recomputes', (tester) async {
    final events = [
      event('a', time: const EventTime(startMinute: 540, durationMinutes: 60)),
    ];

    await pumpTimeline(tester, events);
    DayTimelineLayout.debugComputeCalls = 0;

    await pumpTimeline(
      tester,
      events,
      missedDisplay: CalendarMissedDisplay.hidden,
    );

    expect(DayTimelineLayout.debugComputeCalls, 1);
  });

  testWidgets(
    'toggling a presence mark recomputes even with unchanged events and '
    'missedDisplay — the stale-layout guard',
    (tester) async {
      final events = [
        event(
          'missed',
          time: const EventTime(startMinute: 540, durationMinutes: 60),
          tracksPresence: true,
        ),
        event(
          'kept',
          time: const EventTime(startMinute: 660, durationMinutes: 30),
        ),
      ];

      await pumpTimeline(
        tester,
        events,
        missedDisplay: CalendarMissedDisplay.hidden,
      );
      // Both events render: neither is marked missed yet.
      expect(find.byType(Opacity), findsNWidgets(2));

      DayTimelineLayout.debugComputeCalls = 0;
      EventPresence.updateCache(
        byEvent: {
          'missed': {day},
        },
      );

      await pumpTimeline(
        tester,
        events,
        missedDisplay: CalendarMissedDisplay.hidden,
      );

      expect(
        DayTimelineLayout.debugComputeCalls,
        1,
        reason:
            'the events list and missedDisplay are unchanged; only '
            'EventPresence.revision moved, and the memo must still catch it',
      );
      // Hidden mode drops the missed event before layout, so the stale
      // cache-hit bug would have kept rendering both blocks here.
      expect(find.byType(Opacity), findsNWidgets(1));
    },
  );

  testWidgets('rendered output is unchanged across a memo hit', (tester) async {
    final events = [
      event('a', time: const EventTime(startMinute: 540, durationMinutes: 60)),
      event('b', time: const EventTime(startMinute: 600, durationMinutes: 30)),
    ];

    await pumpTimeline(tester, events);
    final before = find.byType(Opacity).evaluate().length;

    // Same inputs: a memo hit, not a fresh compute.
    await pumpTimeline(tester, events);
    await tester.pump();
    final after = find.byType(Opacity).evaluate().length;

    expect(after, before);
    expect(after, 2);
  });
}
