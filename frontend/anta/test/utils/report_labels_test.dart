import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/date_range.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/utils/report_labels.dart';

/// The report's words about its numbers (D36): durations under an hour,
/// what "against …" names, the composed empty caption, and the counts the
/// review re-worded in German and Romanian.
void main() {
  setUpAll(initializeDateFormatting);

  ReportLabels labelsIn(String locale) =>
      ReportLabels(lookupAppLocalizations(Locale(locale)));

  final september = (
    start: DateTime.utc(2026, 9, 1),
    end: DateTime.utc(2026, 9, 30),
  );

  CalendarReport report({
    required DateRange span,
    required DateTime today,
    DateRange? previousSpan,
    DateRange? previousCounted,
    List<ReportTileValue> tiles = const [],
    int aheadCount = 0,
  }) => CalendarReport(
    span: span,
    today: today,
    tense: CalendarReport.tenseOf(span: span, today: today),
    countedTo: CalendarReport.countedToOf(span: span, today: today),
    previousSpan: previousSpan,
    previousCounted: previousCounted,
    events: const {},
    tiles: tiles,
    skippedDays: 0,
    aheadCount: aheadCount,
    categories: const [],
    missed: const [],
    ahead: const [],
  );

  group('durations (D36.5)', () {
    late ReportLabels labels;
    setUp(() => labels = labelsIn('en'));

    test('under an hour in minutes, from an hour in decimal hours', () {
      expect(labels.hours(40), '40 min');
      expect(labels.hours(60), '1 h');
      expect(labels.hours(90), '1.5 h');
    });

    test('an hours delta under an hour reads in minutes', () {
      expect(
        labels.delta(
          const ReportTileValue(
            tile: ReportTile.hours,
            value: 45,
            previous: 40,
          ),
        ),
        '+5 min',
      );
      expect(
        labels.delta(
          const ReportTileValue(
            tile: ReportTile.hours,
            value: 30,
            previous: 42,
          ),
        ),
        '−12 min',
      );
      expect(
        labels.tileValue(
          const ReportTileValue(tile: ReportTile.hours, value: 40),
        ),
        '40 min',
      );
    });
  });

  group('the comparison (D36.3)', () {
    late ReportLabels labels;
    setUp(() => labels = labelsIn('en'));

    test('the whole previous period is named by its own name', () {
      final past = report(
        span: (
          start: DateTime.utc(2026, 10, 1),
          end: DateTime.utc(2026, 10, 31),
        ),
        today: DateTime.utc(2026, 11, 5),
        previousSpan: september,
        previousCounted: september,
      );
      expect(
        labels.comparisonName(
          past,
          previous: const OverviewMonthPeriod(2026, 9),
        ),
        'September 2026',
      );
    });

    test('a counted part is named by its span', () {
      final current = report(
        span: (
          start: DateTime.utc(2026, 10, 1),
          end: DateTime.utc(2026, 10, 31),
        ),
        today: DateTime.utc(2026, 10, 15),
        previousSpan: september,
        previousCounted: (
          start: DateTime.utc(2026, 9, 1),
          end: DateTime.utc(2026, 9, 15),
        ),
      );
      expect(
        labels.comparisonName(
          current,
          previous: const OverviewMonthPeriod(2026, 9),
        ),
        'Sep 1 – Sep 15, 2026',
      );
    });

    test('no previous period, no name', () {
      final first = report(
        span: (
          start: DateTime.utc(2026, 10, 1),
          end: DateTime.utc(2026, 10, 31),
        ),
        today: DateTime.utc(2026, 11, 5),
      );
      expect(labels.comparisonName(first), isNull);
    });
  });

  group('copy (D36.4, the review)', () {
    test('the empty caption is composed after the period\'s name', () {
      final empty = report(
        span: (start: DateTime.utc(2025, 6, 1), end: DateTime.utc(2025, 6, 30)),
        today: DateTime.utc(2026, 10, 30),
      );
      expect(
        labelsIn('en').caption(empty, periodName: 'June 2025'),
        'June 2025${ReportLabels.separator}Nothing happened',
      );
      expect(
        labelsIn('de').caption(empty, periodName: 'Juni 2025'),
        'Juni 2025${ReportLabels.separator}Nichts passiert',
      );
      expect(
        labelsIn('ro').caption(empty, periodName: 'iunie 2025'),
        'iunie 2025${ReportLabels.separator}Nu s-a întâmplat nimic',
      );
    });

    test('German counts events as Termine, Romanian what is ahead in the '
        'neuter', () {
      final past = report(
        span: (start: DateTime.utc(2026, 9, 1), end: DateTime.utc(2026, 9, 30)),
        today: DateTime.utc(2026, 10, 30),
        tiles: const [ReportTileValue(tile: ReportTile.events, value: 3)],
      );
      expect(labelsIn('de').subtitle(past), '3 Termine');

      final current = report(
        span: (
          start: DateTime.utc(2026, 10, 1),
          end: DateTime.utc(2026, 10, 31),
        ),
        today: DateTime.utc(2026, 10, 30),
        aheadCount: 1,
      );
      expect(
        labelsIn('ro').caption(current, periodName: 'octombrie 2026'),
        // The count is bound to its word with a no-break space.
        endsWith('1 rămas'),
      );
    });
  });
}
