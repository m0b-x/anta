import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_skips.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/ics_serializer.dart';

/// `.ics` export is the one surface the model-layer skip filter does **not**
/// reach: `IcsSerializer` queries `event.rule` directly so it can drop
/// `retroactive`, which drops the skip filter with it.
///
/// So every path here is wired by hand, and every one of them is a place a
/// cancelled occurrence could silently leak into a file the user hands to
/// their phone calendar.
void main() {
  CalendarEvent event({
    required RecurrenceRule rule,
    DateTime? startDate,
    String id = 'e1',
  }) {
    return CalendarEvent(
      id: id,
      title: 'Leg day',
      categoryId: 'gym',
      startDate: startDate ?? DateTime.utc(2026, 8, 3),
      rule: rule,
    );
  }

  void skip(Iterable<DateTime> days, {String id = 'e1'}) {
    EventSkips.updateCache(byEvent: {id: days.toSet()});
  }

  String export(CalendarEvent e) =>
      IcsSerializer.serialize(events: [e], now: DateTime.utc(2026, 8, 1));

  setUp(EventSkips.resetCache);
  tearDown(EventSkips.resetCache);

  group('RRULE rules', () {
    test('a cancelled day becomes an EXDATE', () {
      // Anchored on a Monday; the following Monday is cancelled.
      final skipped = DateTime.utc(2026, 8, 10);
      skip([skipped]);

      final ics = export(
        event(rule: const WeeklyRecurrence(weekdays: {DateTime.monday})),
      );

      expect(ics, contains('RRULE:FREQ=WEEKLY'));
      expect(ics, contains('EXDATE'));
      expect(ics, contains('20260810'));
    });

    test('no skips means no EXDATE at all', () {
      final ics = export(
        event(rule: const WeeklyRecurrence(weekdays: {DateTime.monday})),
      );

      expect(ics, isNot(contains('EXDATE')));
    });

    test('a skip on a day the rule never fires is not an EXDATE', () {
      // A Tuesday, on a Monday-only rule: excluding it would be noise.
      skip([DateTime.utc(2026, 8, 11)]);

      final ics = export(
        event(rule: const WeeklyRecurrence(weekdays: {DateTime.monday})),
      );

      expect(ics, isNot(contains('EXDATE')));
    });

    test('cancelling the anchor moves DTSTART to the next occurrence', () {
      // DTSTART must be a real occurrence, or consumers drift the whole
      // series' phase off a day that no longer exists.
      final anchor = DateTime.utc(2026, 8, 3);
      skip([anchor]);

      final ics = export(
        event(rule: const WeeklyRecurrence(weekdays: {DateTime.monday})),
      );

      expect(ics, contains('DTSTART;VALUE=DATE:20260810'));
    });
  });

  group('RDATE rules', () {
    test('a cancelled explicit date is dropped, not excluded', () {
      final first = DateTime.utc(2026, 8, 3);
      final kept = DateTime.utc(2026, 8, 20);
      final dropped = DateTime.utc(2026, 8, 12);
      skip([dropped]);

      final ics = export(
        event(
          rule: SpecificDatesRecurrence(dates: {first, kept, dropped}),
          startDate: first,
        ),
      );

      expect(ics, contains('RDATE'));
      expect(ics, contains('20260820'));
      // An RDATE that is also an EXDATE would be pure noise.
      expect(ics, isNot(contains('20260812')));
      expect(ics, isNot(contains('EXDATE')));
    });
  });

  group('one-time events', () {
    test('a stale row cannot suppress one', () {
      final only = DateTime.utc(2026, 8, 3);
      skip([only]);

      final ics = export(
        event(rule: const OneTimeRecurrence(), startDate: only),
      );

      expect(ics, contains('DTSTART;VALUE=DATE:20260803'));
    });
  });
}
