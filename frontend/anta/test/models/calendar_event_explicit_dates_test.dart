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

    test('a single date makes it one-time, drops the series flags and keeps '
        'presence', () {
      final updated = event(
        rule: SpecificDatesRecurrence(dates: {d(2026, 9, 25), d(2026, 10, 2)}),
        endDate: d(2027, 1, 1),
        retroactive: true,
        countOccurrences: true,
        tracksPresence: true,
        assumeAbsent: true,
        assumeAbsentFrom: d(2026, 9, 25),
        perOccurrenceDescriptions: true,
        showInDayRail: true,
      ).withExplicitDates({d(2026, 10, 2)});

      expect(updated.startDate, d(2026, 10, 2));
      expect(updated.rule, const OneTimeRecurrence());
      // Decision B: a one-off keeps its mark and its assume-absent default.
      expect(updated.tracksPresence, isTrue);
      expect(updated.assumeAbsent, isTrue);
      expect(updated.assumeAbsentFrom, d(2026, 9, 25));
      expect(updated.endDate, isNull);
      expect(updated.retroactive, isFalse);
      expect(updated.countOccurrences, isFalse);
      expect(updated.perOccurrenceDescriptions, isFalse);
      expect(updated.showInDayRail, isNull);
    });

    test('an untracked single date still clears a stray assume-absent', () {
      final updated = event(
        rule: SpecificDatesRecurrence(dates: {d(2026, 9, 25), d(2026, 10, 2)}),
        assumeAbsent: true,
        assumeAbsentFrom: d(2026, 9, 25),
      ).withExplicitDates({d(2026, 10, 2)});

      expect(updated.tracksPresence, isFalse);
      expect(updated.assumeAbsent, isFalse);
      expect(updated.assumeAbsentFrom, isNull);
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

  // The rule the editor and the Dates sheet share (S1b): a save that leaves a
  // one-off where a series' skip rows could hide it clears them.
  group('strandsSkipsOf', () {
    final series = event(
      rule: const SpecificDatesRecurrence(dates: {}),
    ).withExplicitDates({d(2026, 9, 25), d(2026, 9, 28)});
    final oneOff = event(rule: const OneTimeRecurrence());

    test('a series picked down to one date strands its skips', () {
      expect(
        series.withExplicitDates({d(2026, 9, 28)}).strandsSkipsOf(series),
        isTrue,
      );
      expect(
        oneOff.strandsSkipsOf(event(rule: const DailyRecurrence())),
        isTrue,
      );
    });

    test('a one-off moved to another day strands them', () {
      expect(
        oneOff.withExplicitDates({d(2026, 9, 30)}).strandsSkipsOf(oneOff),
        isTrue,
      );
    });

    test('a one-off kept on its day, and any series, strand nothing', () {
      expect(oneOff.copyWith(title: 'Dentist').strandsSkipsOf(oneOff), isFalse);
      expect(series.strandsSkipsOf(oneOff), isFalse);
      expect(
        series
            .withExplicitDates({d(2026, 9, 25), d(2026, 9, 30)})
            .strandsSkipsOf(series),
        isFalse,
      );
    });
  });
}
