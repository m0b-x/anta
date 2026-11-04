import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/category_kinds.dart';
import 'package:anta/constants/category_profiles.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/category_profile.dart';
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
  final days = [for (var i = 0; i < 366; i++) DateTime.utc(2026, 1, 1 + i)];
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

  test('every category profiled samples the same and adds one lookback per '
      'gap category (analytics R)', () {
    CategoryProfiles.updateCache({
      for (final (categoryId, kind) in [
        ('gym', CategoryKind.workout),
        ('cardio', CategoryKind.study),
        ('mobility', CategoryKind.chore),
        ('other', CategoryKind.appointment),
        ('friends', CategoryKind.social),
      ])
        categoryId: CategoryProfile(
          id: 'p-$categoryId',
          categoryId: categoryId,
          kind: kind,
        ),
    });
    addTearDown(CategoryProfiles.resetCache);
    final events = fixture();
    final input = CalendarReportService.sampleInput(asked(events));
    expect(input.samples, hasLength(expectedSamples()));
    // The repeats ran through 2025; the one-offs are all in the span.
    expect(input.lastSeenBefore, {'mobility': DateTime.utc(2025, 12, 31)});

    final service = CalendarReportService();
    final report = service.report(asked(events));
    expect(report.measures.keys, hasLength(5));
    // The span, the previous span, and one lookback each for Chore,
    // Appointment and Social — the three kinds that read Last seen.
    expect(service.scanCount, 5);
    // Profiled, the previous span is a compared fold (§6.11) over the scan
    // the totals fold took: two folds, no third scan.
    expect(service.foldCount, 2);
    expect(service.report(asked(events)), same(report));
    expect((service.foldCount, service.scanCount), (2, 5));
  });

  test('a 366-day span over fifty events, timed', () {
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
  }, tags: ['benchmark']);

  // The analytics cost bound (§8 "Cost"): every category profiled — a
  // target or a gap each, so one lookback each, a counts-as, tags in every
  // title — folds cold within 1.5× of the same fixture unprofiled, both
  // timed in the same run so the machine cancels out.
  test(
    'every category profiled folds within 1.75× of unprofiled, timed',
    () {
      final events = [
        for (final e in fixture())
          e.copyWith(title: '${e.title} #${e.categoryId} #week${e.id.length}'),
      ];
      ReportTarget per(TargetKind kind, int value, TargetPeriod period) =>
          ReportTarget(kind: kind, value: value, period: period);
      final profiles = {
        for (final (categoryId, kind, target, nominal) in [
          (
            'gym',
            CategoryKind.workout,
            per(TargetKind.atLeast, 3, TargetPeriod.week),
            null,
          ),
          (
            'cardio',
            CategoryKind.study,
            per(TargetKind.atMost, 600, TargetPeriod.week),
            null,
          ),
          (
            'mobility',
            CategoryKind.chore,
            const ReportTarget(kind: TargetKind.maxGap, value: 10),
            30,
          ),
          (
            'other',
            CategoryKind.appointment,
            per(TargetKind.atLeast, 2, TargetPeriod.month),
            60,
          ),
          (
            'friends',
            CategoryKind.social,
            const ReportTarget(kind: TargetKind.maxGap, value: 14),
            null,
          ),
        ])
          categoryId: CategoryProfile(
            id: 'p-$categoryId',
            categoryId: categoryId,
            kind: kind,
            nominalMinutes: nominal,
            target: target,
          ),
      };
      addTearDown(CategoryProfiles.resetCache);

      int coldFold() {
        final watch = Stopwatch()..start();
        final report = CalendarReportService().report(asked(events));
        watch.stop();
        expect(report.tags, isNotEmpty);
        return watch.elapsedMicroseconds;
      }

      // The fastest of many interleaved rounds: noise on a shared machine
      // only ever adds time, so the minimum is the fold's own cost, where a
      // median of a few rounds swung the ratio by ±0.1 run to run.
      int fastest(List<int> values) => (values..sort()).first;
      final plain = <int>[];
      final profiled = <int>[];
      // Three warm-up rounds so neither side pays the JIT alone; then twenty.
      for (var round = 0; round < 23; round++) {
        CategoryProfiles.resetCache();
        final p = coldFold();
        CategoryProfiles.updateCache(profiles);
        final q = coldFold();
        if (round < 3) continue;
        plain.add(p);
        profiled.add(q);
      }
      final ratio = fastest(profiled) / fastest(plain);
      debugPrint(
        '\n=== Calendar report, cold fold, profiled vs unprofiled ===\n'
        '  unprofiled ${fastest(plain) / 1000} ms (fastest of ${plain.length})\n'
        '  profiled   ${fastest(profiled) / 1000} ms\n'
        '  ratio      ${ratio.toStringAsFixed(2)}',
      );
      // 1.5 held while a profiled report was one fold (S2a: 1.40 here). Since
      // S2b-ii a profiled report also folds its compared period — the
      // measures T1 / T3 read — so the profiled path is two folds and sits
      // at 1.49 on an idle machine; the bound leaves room for the machine
      // and still fails a third fold or a per-sample lookup in the walk.
      expect(ratio, lessThanOrEqualTo(1.75));
    },
    tags: ['benchmark'],
  );
}
