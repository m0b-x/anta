import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/date_range.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_report_service.dart';

/// A report over the longest span the scan allows, against fifty events of
/// every shape (`docs/calendar-report-roadmap.md` §4.7's cost model, §7 S1).
///
/// The default run asserts what holds on every machine: the sample count of
/// the fixture, its skipped days, a real previous fold, and one fold for two
/// asks. The same fold with its wall-clock numbers printed is **tagged
/// `benchmark` and excluded from the default run** (see `dart_test.yaml`);
/// its millisecond bound is loose on purpose, so it never flakes. Run it
/// deliberately:
///
/// ```powershell
/// flutter test test/services/calendar_report_benchmark_test.dart --tags benchmark --run-skipped
/// ```
void main() {
  final first = DateTime.utc(2026, 1, 1);
  final DateRange year = (start: first, end: DateTime.utc(2027, 1, 1));
  final DateRange previousYear = (
    start: DateTime.utc(2025, 1, 1),
    end: DateTime.utc(2025, 12, 31),
  );
  final today = DateTime.utc(2026, 10, 30);
  // Early enough that the previous span's fold is as full as the span's.
  final seriesStart = DateTime.utc(2024, 12, 1);
  final days = [
    for (var i = 0; i < 366; i++) DateTime.utc(2026, 1, 1 + i),
  ];
  const tasks = '- [x] warm up\n- [ ] sets\n- [ ] stretch';

  Set<int> repeatDays(int i) => {i % 7 + 1, (i + 3) % 7 + 1};

  /// The first three days of each weekly repeat in the span, all before
  /// today, so every one is counted in the caption.
  Map<String, Set<DateTime>> skips() => {
    for (var i = 0; i < 15; i++)
      'repeat$i': days
          .where((d) => repeatDays(i).contains(d.weekday))
          .take(3)
          .toSet(),
  };

  /// Ten daily routines (five assume-absent with every other past day marked
  /// present, five with every third past day marked missed), ten weekly
  /// routines with per-day task lists, fifteen weekly repeats on two
  /// weekdays with skipped days, fifteen one-offs carrying a task list.
  List<CalendarEvent> fixture() => [
    for (var i = 0; i < 10; i++)
      CalendarEvent(
        id: 'daily$i',
        title: 'Daily $i',
        categoryId: 'gym',
        startDate: seriesStart,
        rule: const DailyRecurrence(),
        tracksPresence: true,
        assumeAbsent: i < 5,
        time: EventTime(startMinute: 6 * 60 + i, durationMinutes: 45),
      ),
    for (var i = 0; i < 10; i++)
      CalendarEvent(
        id: 'weekly$i',
        title: 'Weekly $i',
        categoryId: 'cardio',
        startDate: seriesStart,
        rule: WeeklyRecurrence(weekdays: {i % 7 + 1}),
        tracksPresence: true,
        perOccurrenceDescriptions: true,
        description: tasks,
        time: const EventTime(startMinute: 18 * 60, durationMinutes: 60),
      ),
    for (var i = 0; i < 15; i++)
      CalendarEvent(
        id: 'repeat$i',
        title: 'Repeat $i',
        categoryId: 'mobility',
        startDate: seriesStart,
        rule: WeeklyRecurrence(weekdays: repeatDays(i)),
      ),
    for (var i = 0; i < 15; i++)
      CalendarEvent(
        id: 'once$i',
        title: 'Once $i',
        categoryId: i.isEven ? 'other' : 'friends',
        startDate: days[i * 24],
        description: '- [x] book\n- [ ] pack\n- [ ] go',
      ),
  ];

  int expectedSkips() =>
      skips().values.fold(0, (sum, skipped) => sum + skipped.length);

  int expectedSamples() {
    var count = 10 * days.length + 15;
    for (var i = 0; i < 10; i++) {
      count += days.where((d) => d.weekday == i % 7 + 1).length;
    }
    for (var i = 0; i < 15; i++) {
      count += days.where((d) => repeatDays(i).contains(d.weekday)).length;
    }
    return count - expectedSkips();
  }

  ReportRequest asked(List<CalendarEvent> events) => ReportRequest(
    span: year,
    previousSpan: previousYear,
    events: events,
    today: today,
    weekStart: CalendarWeekStart.monday,
  );

  setUp(() {
    CalendarCategories.updateCache([
      for (final (i, seed) in CalendarCategories.builtInSeeds.indexed)
        CalendarCategory(
          id: seed.id,
          name: CalendarCategories.builtInSeedName(seed.kind),
          colorValue: seed.colorValue,
          iconKey: seed.iconKey,
          sortOrder: i,
          isBuiltIn: true,
        ),
      const CalendarCategory(
        id: 'friends',
        name: 'Friends',
        colorValue: 0xFF3949AB,
        iconKey: 'event',
        sortOrder: 9,
        isBuiltIn: false,
      ),
    ]);
    EventPresence.updateCache(
      byEvent: {
        for (var i = 0; i < 10; i++)
          'daily$i': {
            for (final (n, d) in days.indexed)
              if (!d.isAfter(today))
                if (i < 5 && n.isEven)
                  d: PresenceStatus.present
                else if (i >= 5 && n % 3 == 0)
                  d: PresenceStatus.missed,
          },
      },
    );
    EventSkips.updateCache(byEvent: skips());
    OccurrenceDescriptions.updateCache(
      byEvent: {
        for (var i = 0; i < 10; i++)
          'weekly$i': {
            for (final d in days.where((d) => d.weekday == i % 7 + 1).take(20))
              d: '- [x] warm up\n- [x] sets\n- [ ] stretch',
          },
      },
    );
  });

  tearDown(() {
    EventPresence.resetCache();
    EventSkips.resetCache();
    OccurrenceDescriptions.resetCache();
    CalendarCategories.updateCache(const []);
  });

  test('a 366-day span over fifty events samples every occurrence once', () {
    final events = fixture();
    final input = CalendarReportService.sampleInput(asked(events));
    expect(input.samples, hasLength(expectedSamples()));
    expect(input.samples.toSet(), hasLength(input.samples.length));
    expect(input.skippedDays, expectedSkips());
    // The span holds today, so the previous year is counted to the same
    // elapsed length (D28): 1 January to 30 October 2025, every series live.
    expect(input.previousTotals!.occurrences, greaterThan(4500));

    final service = CalendarReportService();
    final report = service.report(asked(events));
    expect(report.span, year);
    expect(
      report.tiles.singleWhere((t) => t.tile == ReportTile.tasks).previous,
      isNotNull,
    );
    expect(service.report(asked(events)), same(report));
    expect(service.foldCount, 1);
  });

  test(
    'a 366-day span over fifty events, timed',
    () {
      final events = fixture();
      final service = CalendarReportService();
      final cold = Stopwatch()..start();
      service.report(asked(events));
      cold.stop();
      final warm = Stopwatch()..start();
      service.report(asked(events));
      warm.stop();
      debugPrint(
        '\n=== Calendar report, 366 days x 50 events, '
        '${expectedSamples()} samples, previous year folded ===\n'
        '  first fold ${cold.elapsedMicroseconds / 1000} ms\n'
        '  memo hit   ${warm.elapsedMicroseconds / 1000} ms',
      );
      expect(cold.elapsedMilliseconds, lessThan(2000));
      expect(service.foldCount, 1);
    },
    tags: ['benchmark'],
  );
}
