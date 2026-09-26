import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';

void main() {
  DateTime d(int year, int month, int day) => DateTime.utc(year, month, day);

  CalendarEvent event({
    required RecurrenceRule rule,
    DateTime? startDate,
    DateTime? endDate,
    bool tracksPresence = false,
    bool assumeAbsent = false,
    DateTime? assumeAbsentFrom,
    bool perOccurrenceDescriptions = false,
    bool? showInDayRail,
    bool removeAfterAlert = false,
    bool retroactive = false,
    bool countOccurrences = false,
  }) => CalendarEvent(
    id: 'e1',
    title: 'Physio',
    categoryId: 'health',
    startDate: startDate ?? d(2026, 9, 25),
    rule: rule,
    endDate: endDate,
    tracksPresence: tracksPresence,
    assumeAbsent: assumeAbsent,
    assumeAbsentFrom: assumeAbsentFrom,
    perOccurrenceDescriptions: perOccurrenceDescriptions,
    showInDayRail: showInDayRail,
    removeAfterAlert: removeAfterAlert,
    retroactive: retroactive,
    countOccurrences: countOccurrences,
  );

  group('explicitDates', () {
    test('a one-time event is its start day', () {
      expect(event(rule: const OneTimeRecurrence()).explicitDates, {
        d(2026, 9, 25),
      });
    });

    test('a pinned-dates event is its set', () {
      final dates = {d(2026, 9, 25), d(2026, 10, 2)};
      expect(
        event(rule: SpecificDatesRecurrence(dates: dates)).explicitDates,
        dates,
      );
    });

    test('a periodic rule has none', () {
      expect(
        event(
          rule: const WeeklyRecurrence(weekdays: {1}, interval: 1),
        ).explicitDates,
        isNull,
      );
    });
  });

  group('withExplicitDates', () {
    test('several dates pin the event and anchor it on the earliest', () {
      final updated = event(
        rule: const OneTimeRecurrence(),
        endDate: d(2027, 1, 1),
        removeAfterAlert: true,
        tracksPresence: true,
        perOccurrenceDescriptions: true,
      ).withExplicitDates({d(2026, 10, 2), d(2026, 9, 25), d(2026, 10, 9)});

      expect(updated.startDate, d(2026, 9, 25));
      expect(updated.rule, isA<SpecificDatesRecurrence>());
      expect((updated.rule as SpecificDatesRecurrence).dates, {
        d(2026, 9, 25),
        d(2026, 10, 2),
        d(2026, 10, 9),
      });
      expect(updated.endDate, isNull);
      expect(updated.retroactive, isFalse);
      expect(updated.countOccurrences, isFalse);
      expect(updated.tracksPresence, isTrue);
      expect(updated.perOccurrenceDescriptions, isTrue);
      expect(updated.removeAfterAlert, isFalse);
    });

    test('a single date makes it one-time and drops the series flags', () {
      final updated = event(
        rule: SpecificDatesRecurrence(dates: {d(2026, 9, 25), d(2026, 10, 2)}),
        tracksPresence: true,
        assumeAbsent: true,
        assumeAbsentFrom: d(2026, 9, 25),
        perOccurrenceDescriptions: true,
        showInDayRail: true,
      ).withExplicitDates({d(2026, 10, 2)});

      expect(updated.startDate, d(2026, 10, 2));
      expect(updated.rule, const OneTimeRecurrence());
      expect(updated.tracksPresence, isFalse);
      expect(updated.assumeAbsent, isFalse);
      expect(updated.assumeAbsentFrom, isNull);
      expect(updated.perOccurrenceDescriptions, isFalse);
      expect(updated.showInDayRail, isNull);
    });

    test('a single date keeps the remove-after-alert promise', () {
      final updated = event(
        rule: const OneTimeRecurrence(),
        removeAfterAlert: true,
      ).withExplicitDates({d(2026, 9, 25)});
      expect(updated.removeAfterAlert, isTrue);
    });

    test('inputs are normalized to date-only UTC', () {
      final updated = event(
        rule: const OneTimeRecurrence(),
      ).withExplicitDates({DateTime(2026, 10, 2, 13, 30), d(2026, 10, 2)});
      expect(updated.rule, const OneTimeRecurrence());
      expect(updated.startDate, d(2026, 10, 2));
    });

    test('an empty set changes nothing', () {
      final original = event(rule: const OneTimeRecurrence());
      expect(identical(original.withExplicitDates({}), original), isTrue);
    });
  });
}
