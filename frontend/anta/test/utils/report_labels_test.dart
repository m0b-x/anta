import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/date_range.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/recurrence_rule.dart';
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

  group('spoken hours (the S3a review)', () {
    // 537 min draws "8.9 h", 123 "2 h", 1203 "20.1 h", 1202 "20 h": what is
    // heard is the figure drawn — the old tenths test said "9 hours" for
    // 537 — and a whole figure takes the plural grammar.
    for (final (locale, cases) in [
      (
        'en',
        {
          537: '8.9 hours',
          123: '2 hours',
          1203: '20.1 hours',
          1202: '20 hours',
          40: '40 minutes',
          60: '1 hour',
        },
      ),
      (
        'ro',
        {
          537: '8,9 ore',
          123: '2 ore',
          1203: '20,1 ore',
          1202: '20 de ore',
          40: '40 de minute',
          60: '1 oră',
        },
      ),
    ]) {
      test('$locale reads the figure it draws', () {
        final labels = labelsIn(locale);
        for (final MapEntry(key: minutes, value: spoken) in cases.entries) {
          expect(labels.hoursSpoken(minutes), spoken, reason: '$minutes min');
        }
      });
    }

    test('the drawn figures the spoken ones follow', () {
      final labels = labelsIn('en');
      expect(labels.hours(537), '8.9 h');
      expect(labels.hours(123), '2 h');
      expect(labels.hours(1203), '20.1 h');
      expect(labels.hours(1202), '20 h');
    });
  });

  group('group rows (the S3a review)', () {
    ReportRoutineRow routine(int attended, int total) => ReportRoutineRow(
      eventId: 'e',
      attended: attended,
      total: total,
      minutes: 0,
      latestDay: DateTime.utc(2026, 10, 8),
    );

    test('Romanian counts what was attended in its plural', () {
      final labels = labelsIn('ro');
      expect(labels.routineCaption(routine(5, 8)), '5 din 8 prezențe');
      expect(labels.routineCaption(routine(20, 25)), '20 din 25 de prezențe');
      expect(labels.routineCaption(routine(1, 1)), '1 din 1 prezență');
      expect(labelsIn('en').routineCaption(routine(8, 10)), '8 of 10 attended');
      expect(
        labelsIn('de').routineCaption(routine(8, 10)),
        '8 von 10 anwesend',
      );
    });

    final untimed = CalendarEvent(
      id: 'e',
      title: 'Groceries',
      categoryId: 'other',
      startDate: DateTime.utc(2026, 10, 8),
      rule: const OneTimeRecurrence(),
    );

    for (final (locale, day, dayMonth) in [
      ('en', 'Thu 8', 'Thu 8 Oct'),
      ('de', 'Do., 8.', 'Do., 8. Okt.'),
      ('ro', 'joi 8', 'joi 8 oct.'),
    ]) {
      test('$locale writes a row\'s day "$day", across months "$dayMonth"', () {
        final labels = labelsIn(locale);
        final row = ReportDatedRow(
          eventId: untimed.id,
          day: DateTime.utc(2026, 10, 8),
        );
        String subtitle({required bool spansMonths}) => labels.rowSubtitle(
          row,
          event: untimed,
          use24Hour: true,
          spansMonths: spansMonths,
        );
        expect(subtitle(spansMonths: false), day);
        expect(subtitle(spansMonths: true), dayMonth);
      });
    }

    test('a timed row\'s start follows the phone\'s clock', () {
      final timed = CalendarEvent(
        id: 'e',
        title: 'PT session',
        categoryId: 'gym',
        startDate: DateTime.utc(2026, 10, 8),
        rule: const OneTimeRecurrence(),
        time: const EventTime(startMinute: 17 * 60, durationMinutes: 40),
      );
      final row = ReportDatedRow(
        eventId: timed.id,
        day: DateTime.utc(2026, 10, 8),
      );
      final labels = labelsIn('en');
      expect(
        labels.rowSubtitle(
          row,
          event: timed,
          use24Hour: true,
          spansMonths: false,
        ),
        ['Thu 8', '17:00', '40 min'].join(ReportLabels.separator),
      );
      expect(
        labels.rowSubtitle(
          row,
          event: timed,
          use24Hour: false,
          spansMonths: false,
        ),
        allOf(contains('PM'), isNot(contains('17:00'))),
      );
    });
  });

  group('the design review (D44)', () {
    test('the Hours tile speaks hours, its value and its change', () {
      const grew = ReportTileValue(
        tile: ReportTile.hours,
        value: 45 * 60,
        previous: 42 * 60,
      );
      expect(
        labelsIn('en').tileSemantics(grew, against: 'September 2026'),
        'Hours, 45 hours, 3 hours more than September 2026',
      );
      expect(
        labelsIn('de').tileSemantics(grew, against: 'September 2026'),
        'Stunden, 45 Stunden, 3 Stunden mehr als September 2026',
      );
      const shrank = ReportTileValue(
        tile: ReportTile.hours,
        value: 90,
        previous: 120,
      );
      expect(
        labelsIn('en').tileSemantics(shrank, against: 'September 2026'),
        'Hours, 1.5 hours, 30 minutes less than September 2026',
      );
    });

    test('a count shrinks by "fewer", hours by "less"', () {
      final labels = labelsIn('en');
      for (final tile in [ReportTile.events, ReportTile.missed]) {
        expect(
          labels.tileSemantics(
            ReportTileValue(tile: tile, value: 4, previous: 10),
            against: 'September 2026',
          ),
          endsWith('6 fewer than September 2026'),
        );
      }
      expect(
        labels.tileSemantics(
          const ReportTileValue(
            tile: ReportTile.attended,
            value: 4,
            of: 5,
            previous: 10,
          ),
          against: 'September 2026',
        ),
        endsWith('6 fewer than September 2026'),
      );
      expect(
        labels.tileSemantics(
          const ReportTileValue(
            tile: ReportTile.tasks,
            value: 1,
            of: 3,
            previous: 3,
          ),
          against: 'September 2026',
        ),
        endsWith('2 fewer than September 2026'),
      );
    });

    test('de says "Termine" on the Events tile, as everywhere else', () {
      final labels = labelsIn('de');
      expect(labels.tileLabel(ReportTile.events), 'Termine');
      expect(labels.l10n.reportEventCount(2), '2 Termine');
    });

    test('a group whose facts are a bare count says its noun', () {
      const bare = ReportCategoryGroup(
        categoryId: 'other',
        count: 1,
        minutes: 0,
        missed: 0,
        rows: [],
      );
      expect(labelsIn('en').groupFacts(ReportCard.categories, bare), '1 event');
      expect(labelsIn('en').groupFacts(ReportCard.ahead, bare), '1 event');
      expect(labelsIn('de').groupFacts(ReportCard.ahead, bare), '1 Termin');
      const timed = ReportCategoryGroup(
        categoryId: 'gym',
        count: 14,
        minutes: 60,
        missed: 2,
        rows: [],
      );
      expect(
        labelsIn('en').groupFacts(ReportCard.categories, timed),
        ['14', '1 h', '2 missed'].join(ReportLabels.separator),
      );
    });
  });

  group('the S5a review (D46)', () {
    test('a tile and a group header group a count as the subtitle does', () {
      const events = ReportTileValue(tile: ReportTile.events, value: 1234);
      const attended = ReportTileValue(
        tile: ReportTile.attended,
        value: 1234,
        of: 2345,
      );
      const group = ReportCategoryGroup(
        categoryId: 'gym',
        count: 1234,
        minutes: 60,
        missed: 0,
        rows: [],
      );
      final en = labelsIn('en');
      expect(en.tileValue(events), '1,234');
      expect(en.tileValue(attended), '1,234 of 2,345');
      expect(en.tileValue(attended, ofInDetail: true), '1,234');
      expect(en.detail(attended, ofInDetail: true), startsWith('of 2,345'));
      expect(
        en.groupFacts(ReportCard.categories, group),
        ['1,234', '1 h'].join(ReportLabels.separator),
      );
      expect(
        en.subtitle(
          report(
            span: september,
            today: DateTime.utc(2026, 10, 30),
            tiles: const [events],
          ),
        ),
        startsWith('1,234 events'),
      );
      final de = labelsIn('de');
      expect(de.tileValue(events), '1.234');
      expect(
        de.groupFacts(ReportCard.categories, group),
        ['1.234', '1 Std.'].join(ReportLabels.separator),
      );
    });

    test('a count\'s change agrees with its number; hours keep the mass '
        'forms', () {
      String spoken(String locale, int value, int previous, ReportTile tile) =>
          labelsIn(locale).tileSemantics(
            ReportTileValue(tile: tile, value: value, previous: previous),
            against: 'X',
          );
      expect(spoken('en', 5, 4, ReportTile.events), endsWith('1 more than X'));
      expect(spoken('en', 6, 4, ReportTile.events), endsWith('2 more than X'));
      expect(spoken('en', 3, 4, ReportTile.missed), endsWith('1 fewer than X'));
      expect(spoken('en', 2, 4, ReportTile.missed), endsWith('2 fewer than X'));
      expect(
        spoken('ro', 5, 4, ReportTile.events),
        endsWith('cu 1 mai mult decât X'),
      );
      expect(
        spoken('ro', 6, 4, ReportTile.events),
        endsWith('cu 2 mai multe decât X'),
      );
      expect(
        spoken('ro', 3, 4, ReportTile.missed),
        endsWith('cu 1 mai puțin decât X'),
      );
      expect(
        spoken('ro', 2, 4, ReportTile.missed),
        endsWith('cu 2 mai puține decât X'),
      );
      expect(
        spoken('ro', 4, 24, ReportTile.missed),
        endsWith('cu 20 mai puține decât X'),
      );
      expect(
        spoken('ro', 120, 60, ReportTile.hours),
        endsWith('cu 1 oră mai mult decât X'),
      );
    });
  });
}
