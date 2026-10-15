import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/calendar_bounds.dart';
import 'package:anta/l10n/app_localizations.dart';
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
        final period = OverviewPeriod.fromChoice(choice, today: today);
        expect(period.menuChoice(today: today), choice);
      }
      expect(
        OverviewPeriod.fromChoice(OverviewPeriodChoice.thisYear, today: today),
        const OverviewYearPeriod(2026),
      );
    });

    test('the custom row has no period of its own', () {
      expect(
        () => OverviewPeriod.fromChoice(
          OverviewPeriodChoice.custom,
          today: today,
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
          OverviewPeriod.decode(period.encode(today: today), today: today),
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
          OverviewPeriod.decode(value, today: today),
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
