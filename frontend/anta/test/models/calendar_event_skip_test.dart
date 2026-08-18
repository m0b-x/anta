import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_skips.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';

/// `CalendarEvent.occursOn` is the single choke point every calendar surface
/// goes through, which is exactly why the skip filter lives there — and why a
/// mistake in it is invisible until several surfaces quietly disagree.
///
/// The gate on [OneTimeRecurrence] carries the most weight: a stale row must
/// never be able to hide a one-time event, because there is no UI to restore
/// one.
void main() {
  final day = DateTime.utc(2026, 8, 12);

  CalendarEvent event({
    RecurrenceRule rule = const DailyRecurrence(),
    DateTime? startDate,
    DateTime? endDate,
    bool retroactive = false,
    String id = 'e1',
  }) {
    return CalendarEvent(
      id: id,
      title: 'Leg day',
      categoryId: 'gym',
      startDate: startDate ?? DateTime.utc(2026, 1, 1),
      endDate: endDate,
      rule: rule,
      retroactive: retroactive,
    );
  }

  void skip(Iterable<DateTime> days, {String id = 'e1'}) {
    EventSkips.updateCache(byEvent: {
      id: days.toSet(),
    });
  }

  setUp(EventSkips.resetCache);
  tearDown(EventSkips.resetCache);

  group('recurring rules', () {
    test('a cancelled day stops occurring', () {
      expect(event().occursOn(day), isTrue);

      skip([day]);

      expect(event().occursOn(day), isFalse);
    });

    test('neighbouring days are untouched', () {
      skip([day]);

      expect(
        event().occursOn(day.subtract(const Duration(days: 1))),
        isTrue,
      );
      expect(event().occursOn(day.add(const Duration(days: 1))), isTrue);
    });

    test('applies to every recurring kind', () {
      final rules = <RecurrenceRule>[
        const DailyRecurrence(),
        const WeeklyRecurrence(weekdays: {DateTime.wednesday}),
        const MonthlyRecurrence(),
        const YearlyRecurrence(),
        const WorkdaysRecurrence(),
        SpecificDatesRecurrence(dates: {day}),
      ];
      // The fixture day is a Wednesday and a workday, so every rule above
      // fires on it before the skip.
      for (final rule in rules) {
        EventSkips.resetCache();
        expect(
          event(rule: rule, startDate: day).occursOn(day),
          isTrue,
          reason: '$rule should occur before the skip',
        );
        skip([day]);
        expect(
          event(rule: rule, startDate: day).occursOn(day),
          isFalse,
          reason: '$rule should not occur after the skip',
        );
      }
    });

    test('a skip on another event does not affect this one', () {
      skip([day], id: 'other');

      expect(event().occursOn(day), isTrue);
    });

    test('a naive local day still matches the date-only key', () {
      skip([day]);

      expect(event().occursOn(DateTime(2026, 8, 12, 17, 30)), isFalse);
    });

    test('restoring brings the occurrence back', () {
      skip([day]);
      expect(event().occursOn(day), isFalse);

      EventSkips.resetCache();

      expect(event().occursOn(day), isTrue);
    });
  });

  group('one-time events', () {
    test('a stale row can never hide one', () {
      // The row should not exist — the UI offers delete instead — so this is
      // about what happens if one ever does.
      skip([day]);

      expect(
        event(rule: const OneTimeRecurrence(), startDate: day).occursOn(day),
        isTrue,
      );
    });

    test('appliesTo excludes them', () {
      expect(
        EventSkips.appliesTo(event(rule: const OneTimeRecurrence())),
        isFalse,
      );
      expect(EventSkips.appliesTo(event()), isTrue);
    });
  });

  group('interaction with the other bounds', () {
    test('endDate still clamps regardless of skips', () {
      final bounded = event(endDate: day.subtract(const Duration(days: 1)));

      expect(bounded.occursOn(day), isFalse);
    });

    test('a retroactive occurrence can be cancelled too', () {
      final future = event(
        startDate: DateTime.utc(2026, 12, 1),
        retroactive: true,
      );
      expect(future.occursOn(day), isTrue);

      skip([day]);

      expect(future.occursOn(day), isFalse);
    });

    test('a pre-start day stays absent whether skipped or not', () {
      final later = event(startDate: DateTime.utc(2026, 12, 1));

      expect(later.occursOn(day), isFalse);
      skip([day]);
      expect(later.occursOn(day), isFalse);
    });
  });

  group('facade', () {
    test('daysFor returns the cancelled set and is empty when unknown', () {
      skip([day, day.add(const Duration(days: 2))]);

      expect(EventSkips.daysFor('e1'), hasLength(2));
      expect(EventSkips.daysFor('ghost'), isEmpty);
    });

    test('the revision moves on every republish', () {
      final before = EventSkips.revision;

      skip([day]);

      expect(EventSkips.revision, greaterThan(before));
    });
  });
}
