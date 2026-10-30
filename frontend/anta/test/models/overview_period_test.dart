import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/calendar_bounds.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/overview_list_options.dart';
import 'package:anta/models/overview_period.dart';

/// The overview list's unit and its options: what each period resolves to
/// against today, how the Period menu reads it back, and the codecs a stored
/// value goes through — forward-compatible both ways.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  final today = DateTime.utc(2026, 10, 11);
  const bounds = (first: 2019, last: 2030);
  final en = lookupAppLocalizations(const Locale('en'));
  const monday = CalendarWeekStart.monday;

  group('resolve', () {
    test('a year is January 1 to December 31', () {
      expect(
        const OverviewYearPeriod(
          2024,
        ).resolve(today: today, yearBounds: bounds),
        (start: DateTime.utc(2024, 1, 1), end: DateTime.utc(2024, 12, 31)),
      );
    });

    test('the rolling presets end today', () {
      expect(
        const OverviewRollingPeriod(
          OverviewRollingPreset.last12Months,
        ).resolve(today: today, yearBounds: bounds),
        (start: DateTime.utc(2025, 10, 12), end: today),
      );
      expect(
        const OverviewRollingPeriod(
          OverviewRollingPreset.last90Days,
        ).resolve(today: today, yearBounds: bounds),
        (start: DateTime.utc(2026, 7, 14), end: today),
      );
      expect(
        const OverviewRollingPeriod(
          OverviewRollingPreset.allTime,
        ).resolve(today: today, yearBounds: bounds),
        (start: DateTime.utc(2019, 1, 1), end: today),
      );
    });

    test('a rolling span counts days across a leap day exactly', () {
      final range = const OverviewRollingPeriod(
        OverviewRollingPreset.last12Months,
      ).resolve(today: DateTime.utc(2028, 3, 1), yearBounds: bounds);
      expect(range.end.difference(range.start).inDays, 364);
      expect(range.start, DateTime.utc(2027, 3, 3));
    });

    test('a wall-clock today is read as its date', () {
      expect(
        const OverviewRollingPeriod(
          OverviewRollingPreset.last90Days,
        ).resolve(today: DateTime(2026, 10, 11, 23, 30), yearBounds: bounds),
        (start: DateTime.utc(2026, 7, 14), end: today),
      );
    });

    test('a custom span is kept as is', () {
      final period = OverviewCustomPeriod(
        DateTime.utc(2025, 9, 25),
        DateTime.utc(2026, 1, 16),
      );
      expect(period.resolve(today: today, yearBounds: bounds), (
        start: DateTime.utc(2025, 9, 25),
        end: DateTime.utc(2026, 1, 16),
      ));
    });

    test('every span is clamped to the calendar bounds', () {
      expect(
        OverviewCustomPeriod(
          DateTime.utc(1850, 1, 1),
          DateTime.utc(2150, 1, 1),
        ).resolve(today: today, yearBounds: bounds),
        (start: CalendarBounds.earliest, end: CalendarBounds.latest),
      );
      expect(
        const OverviewRollingPeriod(
          OverviewRollingPreset.allTime,
        ).resolve(today: today, yearBounds: (first: 0, last: 0)),
        (start: CalendarBounds.earliest, end: today),
      );
    });

    test('a start past the end collapses onto the end', () {
      expect(
        OverviewCustomPeriod(
          DateTime.utc(2026, 5, 1),
          DateTime.utc(2026, 4, 1),
        ).resolve(today: today, yearBounds: bounds),
        (start: DateTime.utc(2026, 4, 1), end: DateTime.utc(2026, 4, 1)),
      );
    });
  });

  group('the Period menu', () {
    test('menuValue names the year, the preset or the span', () {
      expect(const OverviewYearPeriod(2026).menuValue(en), '2026');
      expect(
        const OverviewRollingPeriod(
          OverviewRollingPreset.last12Months,
        ).menuValue(en),
        en.overviewPeriodLast12Months,
      );
      expect(
        const OverviewRollingPeriod(
          OverviewRollingPreset.last90Days,
        ).menuValue(en),
        en.overviewPeriodLast90Days,
      );
      expect(
        const OverviewRollingPeriod(
          OverviewRollingPreset.allTime,
        ).menuValue(en),
        en.overviewPeriodAllTime,
      );
      expect(
        OverviewCustomPeriod(
          DateTime.utc(2026, 3, 15),
          DateTime.utc(2026, 6, 20),
        ).menuValue(en),
        'Mar 15 – Jun 20, 2026',
      );
      expect(
        OverviewCustomPeriod(
          DateTime.utc(2025, 9, 25),
          DateTime.utc(2026, 1, 16),
        ).menuValue(en),
        'Sep 25, 2025 – Jan 16, 2026',
      );
    });

    test('menuChoice checks this year, the preset, or custom', () {
      expect(
        const OverviewYearPeriod(2026).menuChoice(today: today),
        OverviewPeriodChoice.thisYear,
      );
      expect(
        const OverviewYearPeriod(2024).menuChoice(today: today),
        OverviewPeriodChoice.custom,
      );
      expect(
        const OverviewRollingPeriod(
          OverviewRollingPreset.last90Days,
        ).menuChoice(today: today),
        OverviewPeriodChoice.last90Days,
      );
      expect(
        OverviewCustomPeriod(today, today).menuChoice(today: today),
        OverviewPeriodChoice.custom,
      );
    });

    test('fromChoice round-trips every preset row through menuChoice', () {
      for (final choice in OverviewPeriodChoice.values) {
        if (choice == OverviewPeriodChoice.custom) continue;
        final period = OverviewPeriod.fromChoice(
          choice,
          today: today,
          weekStart: monday,
        );
        expect(period.menuChoice(today: today), choice);
      }
      expect(
        OverviewPeriod.fromChoice(
          OverviewPeriodChoice.thisYear,
          today: today,
          weekStart: monday,
        ),
        const OverviewYearPeriod(2026),
      );
    });

    test('the custom row has no period of its own', () {
      expect(
        () => OverviewPeriod.fromChoice(
          OverviewPeriodChoice.custom,
          today: today,
          weekStart: monday,
        ),
        throwsArgumentError,
      );
    });
  });

  group('codec', () {
    test('this year and the presets are stored, the rest is not', () {
      expect(const OverviewYearPeriod(2026).encode(today: today), 'thisYear');
      expect(const OverviewYearPeriod(2025).encode(today: today), isNull);
      expect(
        const OverviewRollingPeriod(
          OverviewRollingPreset.last12Months,
        ).encode(today: today),
        'preset:last12Months',
      );
      expect(OverviewCustomPeriod(today, today).encode(today: today), isNull);
    });

    test('every stored value decodes back', () {
      for (final period in [
        const OverviewYearPeriod(2026),
        for (final preset in OverviewRollingPreset.values)
          OverviewRollingPeriod(preset),
      ]) {
        expect(
          OverviewPeriod.decode(
            period.encode(today: today),
            today: today,
            weekStart: monday,
          ),
          period,
        );
      }
    });

    test('absent, empty and unknown values fall back to this year', () {
      for (final value in [
        null,
        '',
        'preset:',
        'preset:nextDecade',
        'custom:2026-01-01',
        'garbage',
      ]) {
        expect(
          OverviewPeriod.decode(value, today: today, weekStart: monday),
          const OverviewYearPeriod(2026),
          reason: '$value',
        );
      }
    });
  });

  test('periods compare by value', () {
    expect(const OverviewYearPeriod(2026), const OverviewYearPeriod(2026));
    expect(
      const OverviewYearPeriod(2026),
      isNot(const OverviewYearPeriod(2025)),
    );
    expect(
      OverviewCustomPeriod(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 2, 1)),
      OverviewCustomPeriod(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 2, 1)),
    );
    expect(
      OverviewCustomPeriod(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 12, 31),
      ),
      isNot(const OverviewYearPeriod(2026)),
    );
  });

  test('across New Year This year moves on; a past year, a rolling and a '
      'custom span stay (review 11)', () {
    final before = DateTime.utc(2026, 12, 31);
    final today = DateTime.utc(2027, 1, 1);
    OverviewPeriod follow(OverviewPeriod period) =>
        period.followingToday(before: before, today: today);

    expect(
      follow(const OverviewYearPeriod(2026)),
      const OverviewYearPeriod(2027),
    );
    expect(
      follow(const OverviewYearPeriod(2024)),
      const OverviewYearPeriod(2024),
    );
    const rolling = OverviewRollingPeriod(OverviewRollingPreset.last90Days);
    expect(follow(rolling), rolling);
    final custom = OverviewCustomPeriod(
      DateTime.utc(2026, 3, 1),
      DateTime.utc(2026, 3, 31),
    );
    expect(follow(custom), custom);
    // Within one year nothing moves.
    expect(
      const OverviewYearPeriod(2026).followingToday(
        before: DateTime.utc(2026, 10, 11),
        today: DateTime.utc(2026, 10, 12),
      ),
      const OverviewYearPeriod(2026),
    );
  });

  group('stepped (D15a)', () {
    OverviewPeriod? step(
      OverviewPeriod period,
      int direction, {
      ({int first, int last}) yearBounds = bounds,
    }) => period.stepped(
      direction: direction,
      today: today,
      yearBounds: yearBounds,
    );

    test('a year steps to the neighbouring year', () {
      expect(
        step(const OverviewYearPeriod(2026), -1),
        isA<OverviewYearPeriod>(),
      );
      expect(
        step(const OverviewYearPeriod(2026), -1),
        const OverviewYearPeriod(2025),
      );
      expect(
        step(const OverviewYearPeriod(2026), 1),
        const OverviewYearPeriod(2027),
      );
    });

    test('a rolling preset becomes the span of its length beside it', () {
      const last90Days = OverviewRollingPeriod(
        OverviewRollingPreset.last90Days,
      );
      // Today's ninety days are July 14 – October 11.
      expect(
        step(last90Days, -1),
        OverviewCustomPeriod(
          DateTime.utc(2026, 4, 15),
          DateTime.utc(2026, 7, 13),
        ),
      );
      expect(
        step(last90Days, 1),
        OverviewCustomPeriod(
          DateTime.utc(2026, 10, 12),
          DateTime.utc(2027, 1, 9),
        ),
      );
      expect(
        step(
          const OverviewRollingPeriod(OverviewRollingPreset.last12Months),
          -1,
        ),
        OverviewCustomPeriod(
          DateTime.utc(2024, 10, 12),
          DateTime.utc(2025, 10, 11),
        ),
      );
    });

    test('a custom span shifts by its own width, and back again', () {
      final span = OverviewCustomPeriod(
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 3, 10),
      );
      final back = step(span, -1)!;
      expect(
        back,
        OverviewCustomPeriod(
          DateTime.utc(2026, 2, 19),
          DateTime.utc(2026, 2, 28),
        ),
      );
      expect(
        step(span, 1),
        OverviewCustomPeriod(
          DateTime.utc(2026, 3, 11),
          DateTime.utc(2026, 3, 20),
        ),
      );
      expect(step(back, 1), span);
    });

    test('All time does not step', () {
      const allTime = OverviewRollingPeriod(OverviewRollingPreset.allTime);
      expect(step(allTime, -1), isNull);
      expect(step(allTime, 1), isNull);
    });

    test('a step wholly outside the year bounds is none; one that still '
        'reaches into them is kept', () {
      expect(step(const OverviewYearPeriod(2019), -1), isNull);
      expect(step(const OverviewYearPeriod(2030), 1), isNull);
      expect(
        step(
          OverviewCustomPeriod(
            DateTime.utc(2019, 1, 1),
            DateTime.utc(2019, 1, 10),
          ),
          -1,
        ),
        isNull,
      );
      expect(
        step(
          OverviewCustomPeriod(
            DateTime.utc(2019, 1, 3),
            DateTime.utc(2019, 1, 12),
          ),
          -1,
        ),
        OverviewCustomPeriod(
          DateTime.utc(2018, 12, 24),
          DateTime.utc(2019, 1, 2),
        ),
      );
      expect(
        step(
          OverviewCustomPeriod(
            DateTime.utc(2030, 12, 22),
            DateTime.utc(2030, 12, 31),
          ),
          1,
        ),
        isNull,
      );
    });

    test('a step past the calendar bounds is none', () {
      const wide = (first: 1800, last: 2200);
      expect(
        step(
          OverviewCustomPeriod(
            CalendarBounds.earliest,
            DateTime.utc(1900, 1, 5),
          ),
          -1,
          yearBounds: wide,
        ),
        isNull,
      );
      expect(
        step(
          OverviewCustomPeriod(
            DateTime.utc(2100, 12, 27),
            CalendarBounds.latest,
          ),
          1,
          yearBounds: wide,
        ),
        isNull,
      );
    });
  });

  // October 11, 2026 is a Sunday.
  group('this week and this month (S0)', () {
    const sunday = CalendarWeekStart.sunday;
    const saturday = CalendarWeekStart.saturday;
    final thisWeek = OverviewWeekPeriod(DateTime.utc(2026, 10, 5));
    const october = OverviewMonthPeriod(2026, 10);

    OverviewPeriod? step(OverviewPeriod period, int direction) =>
        period.stepped(direction: direction, today: today, yearBounds: bounds);

    test('this week starts on the calendar week start', () {
      // A Sunday under a Monday start belongs to the Monday before it.
      expect(
        OverviewPeriod.thisWeek(today: today, weekStart: monday),
        thisWeek,
      );
      expect(
        OverviewPeriod.thisWeek(today: today, weekStart: sunday),
        OverviewWeekPeriod(DateTime.utc(2026, 10, 11)),
      );
      expect(
        OverviewPeriod.thisWeek(today: today, weekStart: saturday),
        OverviewWeekPeriod(DateTime.utc(2026, 10, 10)),
      );
      expect(
        OverviewPeriod.thisWeek(
          today: DateTime.utc(2026, 10, 12),
          weekStart: monday,
        ),
        OverviewWeekPeriod(DateTime.utc(2026, 10, 12)),
      );
      expect(
        OverviewPeriod.thisWeek(
          today: DateTime(2026, 10, 11, 23, 30),
          weekStart: monday,
        ),
        thisWeek,
      );
      expect(OverviewPeriod.thisMonth(today: today), october);
    });

    test('a week resolves to seven days, a month to its own length', () {
      expect(thisWeek.resolve(today: today, yearBounds: bounds), (
        start: DateTime.utc(2026, 10, 5),
        end: DateTime.utc(2026, 10, 11),
      ));
      expect(
        OverviewWeekPeriod(
          DateTime.utc(2026, 12, 28),
        ).resolve(today: today, yearBounds: bounds),
        (start: DateTime.utc(2026, 12, 28), end: DateTime.utc(2027, 1, 3)),
      );
      expect(october.resolve(today: today, yearBounds: bounds), (
        start: DateTime.utc(2026, 10, 1),
        end: DateTime.utc(2026, 10, 31),
      ));
      expect(
        const OverviewMonthPeriod(
          2028,
          2,
        ).resolve(today: today, yearBounds: bounds),
        (start: DateTime.utc(2028, 2, 1), end: DateTime.utc(2028, 2, 29)),
      );
      expect(
        const OverviewMonthPeriod(
          2026,
          2,
        ).resolve(today: today, yearBounds: bounds),
        (start: DateTime.utc(2026, 2, 1), end: DateTime.utc(2026, 2, 28)),
      );
    });

    test('a week across a DST change still ends on its seventh day', () {
      // Europe's clocks move on Sunday, March 29, 2026.
      final week = OverviewWeekPeriod(DateTime.utc(2026, 3, 23));
      expect(week.end, DateTime.utc(2026, 3, 29));
      expect(week.end.isUtc, isTrue);
      expect(step(week, 1), OverviewWeekPeriod(DateTime.utc(2026, 3, 30)));
    });

    test('a week steps by seven days, a month to its calendar neighbour', () {
      expect(step(thisWeek, -1), OverviewWeekPeriod(DateTime.utc(2026, 9, 28)));
      expect(step(thisWeek, 1), OverviewWeekPeriod(DateTime.utc(2026, 10, 12)));
      expect(
        step(OverviewWeekPeriod(DateTime.utc(2026, 12, 28)), 1),
        OverviewWeekPeriod(DateTime.utc(2027, 1, 4)),
      );
      expect(step(october, -1), const OverviewMonthPeriod(2026, 9));
      expect(step(october, 1), const OverviewMonthPeriod(2026, 11));
      expect(
        step(const OverviewMonthPeriod(2026, 12), 1),
        const OverviewMonthPeriod(2027, 1),
      );
      expect(
        step(const OverviewMonthPeriod(2027, 1), -1),
        const OverviewMonthPeriod(2026, 12),
      );
    });

    test('last month is the whole month before, never a length back', () {
      expect(step(october, -1)!.resolve(today: today, yearBounds: bounds), (
        start: DateTime.utc(2026, 9, 1),
        end: DateTime.utc(2026, 9, 30),
      ));
      expect(
        step(step(october, -1)!, -1)!.resolve(today: today, yearBounds: bounds),
        (start: DateTime.utc(2026, 8, 1), end: DateTime.utc(2026, 8, 31)),
      );
    });

    test('a week or month step wholly outside the year bounds is none', () {
      expect(step(const OverviewMonthPeriod(2019, 1), -1), isNull);
      expect(step(const OverviewMonthPeriod(2030, 12), 1), isNull);
      expect(step(OverviewWeekPeriod(DateTime.utc(2019, 1, 1)), -1), isNull);
      // December 23 + 7 still reaches into 2030.
      expect(
        step(OverviewWeekPeriod(DateTime.utc(2030, 12, 23)), 1),
        OverviewWeekPeriod(DateTime.utc(2030, 12, 30)),
      );
      expect(step(OverviewWeekPeriod(DateTime.utc(2030, 12, 30)), 1), isNull);
    });

    test('menuChoice checks This week or This month only for today', () {
      expect(thisWeek.menuChoice(today: today), OverviewPeriodChoice.thisWeek);
      expect(
        step(thisWeek, -1)!.menuChoice(today: today),
        OverviewPeriodChoice.custom,
      );
      expect(october.menuChoice(today: today), OverviewPeriodChoice.thisMonth);
      expect(
        const OverviewMonthPeriod(2026, 9).menuChoice(today: today),
        OverviewPeriodChoice.custom,
      );
      expect(
        const OverviewMonthPeriod(2025, 10).menuChoice(today: today),
        OverviewPeriodChoice.custom,
      );
    });

    test('menuValue names a week by its span and a month by its name', () {
      expect(thisWeek.menuValue(en), 'Oct 5 – Oct 11, 2026');
      expect(
        OverviewWeekPeriod(DateTime.utc(2026, 12, 28)).menuValue(en),
        'Dec 28, 2026 – Jan 3, 2027',
      );
      expect(october.menuValue(en), 'October 2026');
      expect(
        october.menuValue(lookupAppLocalizations(const Locale('de'))),
        'Oktober 2026',
      );
    });

    test('this week and this month are stored; a paged one is not', () {
      expect(thisWeek.encode(today: today), 'thisWeek');
      expect(october.encode(today: today), 'thisMonth');
      expect(step(thisWeek, 1)!.encode(today: today), isNull);
      expect(const OverviewMonthPeriod(2026, 9).encode(today: today), isNull);
      expect(const OverviewMonthPeriod(2025, 10).encode(today: today), isNull);
      expect(
        OverviewPeriod.decode('thisWeek', today: today, weekStart: monday),
        thisWeek,
      );
      expect(
        OverviewPeriod.decode('thisMonth', today: today, weekStart: monday),
        october,
      );
    });

    test('a stored this week starts on the week start read now', () {
      for (final weekStart in CalendarWeekStart.values) {
        final period = OverviewPeriod.thisWeek(
          today: today,
          weekStart: weekStart,
        );
        expect(
          OverviewPeriod.decode(
            period.encode(today: today),
            today: today,
            weekStart: weekStart,
          ),
          period,
          reason: weekStart.name,
        );
      }
      expect(
        OverviewPeriod.decode('thisWeek', today: today, weekStart: sunday),
        OverviewWeekPeriod(DateTime.utc(2026, 10, 11)),
      );
      expect(
        OverviewPeriod.decode('thisWeek', today: today, weekStart: saturday),
        OverviewWeekPeriod(DateTime.utc(2026, 10, 10)),
      );
    });

    test('fromChoice reads the week start for This week alone', () {
      expect(
        OverviewPeriod.fromChoice(
          OverviewPeriodChoice.thisWeek,
          today: today,
          weekStart: sunday,
        ),
        OverviewWeekPeriod(DateTime.utc(2026, 10, 11)),
      );
      expect(
        OverviewPeriod.fromChoice(
          OverviewPeriodChoice.thisMonth,
          today: today,
          weekStart: sunday,
        ),
        october,
      );
    });

    test('across midnight This week and This month move on; a paged one '
        'stays', () {
      // Sunday to Monday: the next week.
      expect(
        thisWeek.followingToday(
          before: today,
          today: DateTime.utc(2026, 10, 12),
        ),
        OverviewWeekPeriod(DateTime.utc(2026, 10, 12)),
      );
      // A page left open for sixteen days lands on the week holding today.
      expect(
        thisWeek.followingToday(
          before: today,
          today: DateTime.utc(2026, 10, 27),
        ),
        OverviewWeekPeriod(DateTime.utc(2026, 10, 26)),
      );
      // Within the week nothing moves.
      expect(
        thisWeek.followingToday(
          before: DateTime.utc(2026, 10, 6),
          today: DateTime.utc(2026, 10, 7),
        ),
        thisWeek,
      );
      final lastWeek = step(thisWeek, -1)!;
      expect(
        lastWeek.followingToday(
          before: today,
          today: DateTime.utc(2026, 10, 12),
        ),
        lastWeek,
      );
      expect(
        october.followingToday(
          before: DateTime.utc(2026, 10, 31),
          today: DateTime.utc(2026, 11, 1),
        ),
        const OverviewMonthPeriod(2026, 11),
      );
      expect(
        const OverviewMonthPeriod(2026, 12).followingToday(
          before: DateTime.utc(2026, 12, 31),
          today: DateTime.utc(2027, 1, 1),
        ),
        const OverviewMonthPeriod(2027, 1),
      );
      expect(
        const OverviewMonthPeriod(2026, 9).followingToday(
          before: DateTime.utc(2026, 10, 31),
          today: DateTime.utc(2026, 11, 1),
        ),
        const OverviewMonthPeriod(2026, 9),
      );
    });

    test('a week or month step past the calendar bounds is none', () {
      const wide = (first: 1800, last: 2200);
      OverviewPeriod? stepWide(OverviewPeriod period, int direction) =>
          period.stepped(direction: direction, today: today, yearBounds: wide);

      // January 1, 1900 is a Monday; December 27, 2100 is a Monday.
      expect(
        stepWide(OverviewWeekPeriod(DateTime.utc(1900, 1, 1)), -1),
        isNull,
      );
      expect(
        stepWide(OverviewWeekPeriod(DateTime.utc(1900, 1, 1)), 1),
        OverviewWeekPeriod(DateTime.utc(1900, 1, 8)),
      );
      expect(
        stepWide(OverviewWeekPeriod(DateTime.utc(2100, 12, 27)), 1),
        isNull,
      );
      expect(stepWide(const OverviewMonthPeriod(1900, 1), -1), isNull);
      expect(
        stepWide(const OverviewMonthPeriod(1900, 1), 1),
        const OverviewMonthPeriod(1900, 2),
      );
      expect(stepWide(const OverviewMonthPeriod(2100, 12), 1), isNull);
      // A Sunday-start week over New Year 1900 reaches into the calendar.
      expect(
        stepWide(OverviewWeekPeriod(DateTime.utc(1900, 1, 7)), -1),
        OverviewWeekPeriod(DateTime.utc(1899, 12, 31)),
      );
    });

    test('a week over the calendar bounds is titled by the days it lists', () {
      final first = OverviewWeekPeriod(DateTime.utc(1899, 12, 31));
      expect(first.resolve(today: today, yearBounds: bounds), (
        start: CalendarBounds.earliest,
        end: DateTime.utc(1900, 1, 6),
      ));
      expect(first.menuValue(en), 'Jan 1 – Jan 6, 1900');
      expect(
        OverviewWeekPeriod(DateTime.utc(2100, 12, 27)).menuValue(en),
        'Dec 27 – Dec 31, 2100',
      );
    });

    test('a clock moved back a day moves This week, This month and This year '
        'back with it', () {
      // From Monday, October 5 back to Sunday, October 4.
      expect(
        thisWeek.followingToday(
          before: DateTime.utc(2026, 10, 5),
          today: DateTime.utc(2026, 10, 4),
        ),
        OverviewWeekPeriod(DateTime.utc(2026, 9, 28)),
      );
      expect(
        october.followingToday(
          before: DateTime.utc(2026, 10, 1),
          today: DateTime.utc(2026, 9, 30),
        ),
        const OverviewMonthPeriod(2026, 9),
      );
      expect(
        const OverviewYearPeriod(2027).followingToday(
          before: DateTime.utc(2027, 1, 1),
          today: DateTime.utc(2026, 12, 31),
        ),
        const OverviewYearPeriod(2026),
      );
    });

    test('weeks and months compare by value', () {
      expect(
        OverviewWeekPeriod(DateTime.utc(2026, 10, 5)),
        OverviewWeekPeriod(DateTime.utc(2026, 10, 5)),
      );
      expect(october, isNot(const OverviewMonthPeriod(2025, 10)));
      expect(
        october,
        isNot(
          OverviewCustomPeriod(
            DateTime.utc(2026, 10, 1),
            DateTime.utc(2026, 10, 31),
          ),
        ),
      );
    });

    test('the model reads no wall clock', () {
      // Doc comments may name the wall clock; code may not read it.
      final code = File('lib/models/overview_period.dart')
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('///'))
          .join('\n');
      expect(code, isNot(contains('DateTime.now')));
    });
  });

  group('OverviewListOptions', () {
    test('the names parse forward-compatibly', () {
      for (final order in OverviewOrder.values) {
        expect(OverviewOrder.fromName(order.name), order);
      }
      for (final rows in OverviewRows.values) {
        expect(OverviewRows.fromName(rows.name), rows);
      }
      expect(OverviewOrder.fromName(null), OverviewOrder.oldestFirst);
      expect(OverviewOrder.fromName('byColour'), OverviewOrder.oldestFirst);
      expect(OverviewRows.fromName(''), OverviewRows.everyOccurrence);
      expect(OverviewRows.fromName('perWeek'), OverviewRows.everyOccurrence);
    });

    test('defaults are oldest first, every occurrence, missed off', () {
      expect(OverviewListOptions.defaults, const OverviewListOptions());
      expect(OverviewListOptions.defaults.order, OverviewOrder.oldestFirst);
      expect(OverviewListOptions.defaults.rows, OverviewRows.everyOccurrence);
      expect(OverviewListOptions.defaults.missedOnly, isFalse);
    });

    test('copyWith changes one field and compares by value', () {
      final next = OverviewListOptions.defaults.copyWith(missedOnly: true);
      expect(next.missedOnly, isTrue);
      expect(next.order, OverviewOrder.oldestFirst);
      expect(next, isNot(OverviewListOptions.defaults));
      expect(next.copyWith(missedOnly: false), OverviewListOptions.defaults);
    });
  });
}
