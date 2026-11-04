import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/analytics_metrics.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/category_kinds.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/category_profile.dart';
import 'package:anta/models/date_range.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/calendar_report_builder.dart';
import 'package:anta/utils/tag_extractor.dart';

/// The report's numbers exist in one place, so every risk is a counting
/// rule: what is counted to today and what is ahead, which tiles a selection
/// shows, how groups and rows order, and when the trend has enough to say.
/// The five worked periods of the design record (§4.4) are the fixtures; the
/// samples come from the events' real recurrence rules.
void main() {
  DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);
  DateRange span(DateTime start, DateTime end) => (start: start, end: end);
  EventTime at(int h, int m, [int? minutes]) =>
      EventTime(startMinute: h * 60 + m, durationMinutes: minutes);
  WeeklyRecurrence weekly(Set<int> weekdays) =>
      WeeklyRecurrence(weekdays: weekdays);
  SpecificDatesRecurrence dates(List<DateTime> days) =>
      SpecificDatesRecurrence(dates: days.toSet());
  const yearly = YearlyRecurrence();
  const daily = DailyRecurrence();

  CalendarEvent ev(
    String id,
    String categoryId,
    DateTime start, {
    RecurrenceRule rule = const OneTimeRecurrence(),
    DateTime? end,
    bool tracked = false,
    EventTime? time,
    String? description,
    bool perDay = false,
    int priority = kDefaultEventPriority,
  }) {
    return CalendarEvent(
      id: id,
      title: id,
      categoryId: categoryId,
      startDate: start,
      rule: rule,
      endDate: end,
      tracksPresence: tracked,
      time: time,
      description: description,
      perOccurrenceDescriptions: perDay,
      priority: priority,
    );
  }

  /// One sample per day each event occurs on, as the sampler probes them; a
  /// skipped day is left out, as `occursOnUtcDay` subtracts it.
  List<ReportSample> sampled(
    List<CalendarEvent> events,
    DateRange range, {
    Map<String, List<DateTime>> missed = const {},
    Map<String, List<DateTime>> skipped = const {},
    Map<String, List<DateTime>> pending = const {},
  }) {
    final samples = <ReportSample>[];
    for (
      var d = range.start;
      !d.isAfter(range.end);
      d = DateTime.utc(d.year, d.month, d.day + 1)
    ) {
      for (final event in events) {
        if (!event.occursOnUtcDay(d)) continue;
        if (skipped[event.id]?.contains(d) ?? false) continue;
        samples.add(
          ReportSample(
            eventId: event.id,
            day: d,
            missed: missed[event.id]?.contains(d) ?? false,
            pending: pending[event.id]?.contains(d) ?? false,
          ),
        );
      }
    }
    return samples;
  }

  ReportInput inputFor(
    List<CalendarEvent> events,
    DateRange range,
    DateTime today, {
    Map<String, List<DateTime>> missed = const {},
    Map<String, List<DateTime>> skipped = const {},
    Map<String, List<DateTime>> pending = const {},
    Map<String, Map<DateTime, String>> overrides = const {},
    CalendarWeekStart weekStart = CalendarWeekStart.monday,
    DateRange? previousSpan,
    ReportTotals? previousTotals,
  }) {
    return ReportInput(
      span: range,
      today: today,
      weekStart: weekStart,
      events: {for (final e in events) e.id: e},
      categoryOf: {
        for (final e in events)
          e.id: CalendarCategories.resolve(e.categoryId).id,
      },
      samples: sampled(
        events,
        range,
        missed: missed,
        skipped: skipped,
        pending: pending,
      ),
      overrides: overrides,
      skippedDays: skipped.values.fold(0, (n, days) => n + days.length),
      categoryOrder: [for (final c in CalendarCategories.all) c.id],
      previousSpan: previousSpan,
      previousTotals: previousTotals,
    );
  }

  CalendarReport fold(
    List<CalendarEvent> events,
    DateRange range,
    DateTime today, {
    Map<String, List<DateTime>> missed = const {},
    Map<String, List<DateTime>> skipped = const {},
    Map<String, List<DateTime>> pending = const {},
    Map<String, Map<DateTime, String>> overrides = const {},
    CalendarWeekStart weekStart = CalendarWeekStart.monday,
    DateRange? previousSpan,
    ReportTotals? previousTotals,
  }) {
    return CalendarReportBuilder.fold(
      inputFor(
        events,
        range,
        today,
        missed: missed,
        skipped: skipped,
        pending: pending,
        overrides: overrides,
        weekStart: weekStart,
        previousSpan: previousSpan,
        previousTotals: previousTotals,
      ),
    );
  }

  String tileText(ReportTileValue t) =>
      '${t.tile.name} ${t.value}${t.of == null ? '' : '/${t.of}'}';
  List<String> tilesOf(CalendarReport r) => [
    for (final t in r.tiles) tileText(t),
  ];
  List<ReportTile> kindsOf(CalendarReport r) => [
    for (final t in r.tiles) t.tile,
  ];
  String groupText(ReportCategoryGroup g) =>
      '${g.categoryId} ${g.count} ${g.minutes}m ${g.missed}x';
  List<String> groupsOf(List<ReportCategoryGroup> groups) => [
    for (final g in groups) groupText(g),
  ];
  String rowText(ReportRow row) => switch (row) {
    ReportRoutineRow(
      :final eventId,
      :final attended,
      :final total,
      :final minutes,
    ) =>
      '$eventId $attended/$total ${minutes}m',
    ReportDatedRow(:final eventId, :final day, :final missed, :final tasks) =>
      '$eventId ${day.month}-${day.day}'
          '${missed ? ' missed' : ''}'
          '${tasks == null ? '' : ' ${tasks.ticked}/${tasks.total}'}',
  };
  List<String> rowsOf(ReportCategoryGroup g) => [
    for (final r in g.rows) rowText(r),
  ];
  ReportTileValue tile(CalendarReport r, ReportTile kind) =>
      r.tiles.singleWhere((t) => t.tile == kind);

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
      const CalendarCategory(
        id: 'todo',
        name: 'To do',
        colorValue: 0xFF6D4C41,
        iconKey: 'event',
        sortOrder: 10,
        isBuiltIn: false,
      ),
    ]);
  });

  tearDown(() => CalendarCategories.updateCache(const []));

  const tasks44 = '- [x] forms\n- [x] receipts\n- [x] sign\n- [x] send';
  const tasks58 =
      '- [x] milk\n- [x] eggs\n- [x] bread\n- [x] rice\n- [x] apples\n'
      '- [ ] coffee\n- [ ] oil\n- [ ] salt';
  const tasks03 = '- [ ] tyres\n- [ ] oil\n- [ ] wipers';

  // Period 4 is also Period 5's previous span, so it is built once.
  final p4Span = span(day(2026, 10, 26), day(2026, 11, 1));
  final p4Today = day(2026, 11, 2);
  final p4Missed = {
    'gym': [day(2026, 10, 28)],
  };
  final p4Skipped = {
    'gym': [day(2026, 10, 30)],
  };
  List<CalendarEvent> p4Events() => [
    ev(
      'gym',
      'gym',
      day(2026, 10, 1),
      rule: weekly({1, 2, 3, 4, 5, 6}),
      tracked: true,
      time: at(18, 0, 60),
    ),
    ev('coffee', 'friends', day(2026, 10, 26), time: at(10, 0, 60)),
    ev('dinner', 'friends', day(2026, 10, 27), time: at(19, 30, 180)),
    ev('hike', 'friends', day(2026, 10, 31), time: at(9, 0, 130)),
    ev('groceries', 'todo', day(2026, 10, 30), description: tasks58),
    ev(
      'tax',
      'todo',
      day(2026, 11, 1),
      time: at(9, 0, 40),
      description: '- [x] file it',
    ),
    ev('ana', 'birthday', day(1994, 10, 29), rule: yearly),
  ];

  group('the worked periods (§4.4)', () {
    // The training month lands on the sketch's tiles and headers. Where it
    // cannot, the fixture asserts what the rules yield: Stretch is an
    // untracked set of dates, so its two days are dated rows (the sketch drew
    // one aggregate "Stretch 2 · 40 min"), and dated rows follow the
    // routines (the sketch put PT session between them), so Gym lists five
    // rows, not four and "2 more"; Rest and Mobility tie at 4 and keep the
    // catalogue's order, Rest first (the sketch drew Mobility first). The
    // two skipped days are a Gym Monday and a Legs Friday the rules would
    // otherwise have added.
    test('1 — October, a training month, viewed on 30 October', () {
      final events = [
        ev(
          'gym',
          'gym',
          day(2026, 10, 5),
          rule: weekly({1, 3, 6}),
          tracked: true,
          time: at(18, 0, 60),
        ),
        ev(
          'legs',
          'gym',
          day(2026, 10, 2),
          rule: weekly({5}),
          end: day(2026, 10, 23),
          tracked: true,
          time: at(7, 0, 70),
        ),
        ev('pt', 'gym', day(2026, 10, 8), time: at(17, 0, 60)),
        ev(
          'stretch',
          'gym',
          day(2026, 10, 6),
          rule: dates([day(2026, 10, 6), day(2026, 10, 20)]),
          time: at(20, 0, 20),
        ),
        ev(
          'run',
          'cardio',
          day(2026, 10, 15),
          rule: weekly({2, 4}),
          tracked: true,
          time: at(7, 0, 30),
        ),
        ev(
          'bike',
          'cardio',
          day(2026, 10, 11),
          rule: dates([day(2026, 10, 11), day(2026, 10, 25)]),
          tracked: true,
          time: at(9, 0, 40),
        ),
        ev(
          'mobility',
          'mobility',
          day(2026, 10, 1),
          rule: weekly({1}),
          tracked: true,
          time: at(7, 30, 30),
        ),
        ev('rest', 'rest', day(2026, 10, 1), rule: weekly({7})),
        ev(
          'weigh',
          'measurement',
          day(2026, 10, 1),
          rule: dates([day(2026, 10, 1), day(2026, 10, 15)]),
        ),
        ev('ana', 'birthday', day(1994, 10, 3), rule: yearly),
        ev('ioana', 'birthday', day(2019, 10, 31), rule: yearly),
      ];
      final report = fold(
        events,
        span(day(2026, 10, 1), day(2026, 10, 31)),
        day(2026, 10, 30),
        missed: {
          'gym': [day(2026, 10, 14), day(2026, 10, 26)],
          'run': [day(2026, 10, 20)],
        },
        skipped: {
          'gym': [day(2026, 10, 5)],
          'legs': [day(2026, 10, 2)],
        },
      );

      expect(report.tense, ReportTense.current);
      expect(tilesOf(report), [
        'events 31',
        'attended 21/24',
        'missed 3',
        'hours 1110',
      ]);
      expect(report.countedTo, day(2026, 10, 30));
      expect(report.skippedDays, 2);
      expect(report.aheadCount, 2);
      expect(groupsOf(report.categories), [
        'gym 14 790m 2x',
        'cardio 6 200m 1x',
        'rest 4 0m 0x',
        'mobility 4 120m 0x',
        'measurement 2 0m 0x',
        'birthday 1 0m 0x',
      ]);
      expect(rowsOf(report.categories[0]), [
        'gym 8/10 480m',
        'legs 3/3 210m',
        'stretch 10-6',
        'pt 10-8',
        'stretch 10-20',
      ]);
      expect(rowsOf(report.categories[1]), ['run 4/5 120m', 'bike 2/2 80m']);
      expect(rowsOf(report.categories[3]), ['mobility 4/4 120m']);

      final trend = report.trend!;
      expect(trend.unit, ReportTrendUnit.day);
      expect(trend.buckets, hasLength(31));
      expect(
        trend.buckets[13],
        ReportTrendBucket(start: day(2026, 10, 14), happened: 0, missed: 1),
      );
      expect(
        trend.buckets[30],
        ReportTrendBucket(start: day(2026, 10, 31), happened: 0, missed: 0),
      );

      expect(groupsOf(report.missed), ['gym 2 0m 2x', 'cardio 1 0m 1x']);
      expect(rowsOf(report.missed[0]), [
        'gym 10-14 missed',
        'gym 10-26 missed',
      ]);
      expect(groupsOf(report.ahead), ['gym 1 60m 0x', 'birthday 1 0m 0x']);
      expect(rowsOf(report.ahead[0]), ['gym 10-31']);
      expect(rowsOf(report.ahead[1]), ['ioana 10-31']);
    });

    // The three groups tie at 2 and keep the catalogue's order — Holiday,
    // Birthday, Friends — where the sketch drew Friends first. Six happened
    // occurrences reach the trend's threshold (Q: four), so the trend is
    // drawn, where the sketch left Over time out.
    test('2 — October, Birthday · Holiday · Friends, viewed on 30 October', () {
      final events = [
        ev('tudor', 'friends', day(2026, 10, 9), time: at(19, 30, 180)),
        ev('mara', 'friends', day(2026, 10, 25), time: at(11, 0, 150)),
        ev('ana', 'birthday', day(1994, 10, 3), rule: yearly),
        ev('mihai', 'birthday', day(1986, 10, 22), rule: yearly),
        ev(
          'sibiu',
          'holiday',
          day(2026, 10, 17),
          rule: dates([day(2026, 10, 17), day(2026, 10, 18)]),
        ),
        ev('ioana', 'birthday', day(2019, 10, 31), rule: yearly),
      ];
      const september = ReportTotals(
        occurrences: 4,
        kept: 4,
        missed: 0,
        attended: 0,
        tracked: 0,
        minutesKept: 150,
        minutesAll: 150,
        tasksTicked: 0,
        tasksTotal: 0,
      );
      final report = fold(
        events,
        span(day(2026, 10, 1), day(2026, 10, 31)),
        day(2026, 10, 30),
        previousSpan: span(day(2026, 9, 1), day(2026, 9, 30)),
        previousTotals: september,
      );

      expect(report.tense, ReportTense.current);
      expect(tilesOf(report), ['events 6', 'hours 330']);
      expect(tile(report, ReportTile.events).previous, 4);
      expect(tile(report, ReportTile.hours).previous, 150);
      expect(report.previousSpan, span(day(2026, 9, 1), day(2026, 9, 30)));
      expect(report.countedTo, day(2026, 10, 30));
      expect(report.skippedDays, 0);
      expect(report.aheadCount, 1);
      expect(groupsOf(report.categories), [
        'holiday 2 0m 0x',
        'birthday 2 0m 0x',
        'friends 2 330m 0x',
      ]);
      expect(rowsOf(report.categories[0]), ['sibiu 10-17', 'sibiu 10-18']);
      expect(rowsOf(report.categories[1]), ['ana 10-3', 'mihai 10-22']);
      expect(rowsOf(report.categories[2]), ['tudor 10-9', 'mara 10-25']);
      expect(report.trend, isNotNull);
      expect(report.missed, isEmpty);
      expect(groupsOf(report.ahead), ['birthday 1 0m 0x']);
      expect(rowsOf(report.ahead.single), ['ioana 10-31']);
    });

    test('3 — this week, To do, viewed on Wednesday 28 October', () {
      final events = [
        ev('tax', 'todo', day(2026, 10, 26), description: tasks44),
        ev('dentist', 'todo', day(2026, 10, 27)),
        ev('groceries', 'todo', day(2026, 10, 27), description: tasks58),
        ev('bank', 'todo', day(2026, 10, 29)),
        ev('garage', 'todo', day(2026, 10, 31), description: tasks03),
      ];
      final report = fold(
        events,
        span(day(2026, 10, 26), day(2026, 11, 1)),
        day(2026, 10, 28),
        previousTotals: const ReportTotals(
          occurrences: 4,
          kept: 4,
          missed: 0,
          attended: 0,
          tracked: 0,
          minutesKept: 0,
          minutesAll: 0,
          tasksTicked: 2,
          tasksTotal: 5,
        ),
      );

      expect(report.tense, ReportTense.current);
      expect(tilesOf(report), ['events 3', 'tasks 9/12']);
      expect(tile(report, ReportTile.events).previous, 4);
      expect(report.countedTo, day(2026, 10, 28));
      expect(report.aheadCount, 2);
      expect(groupsOf(report.categories), ['todo 3 0m 0x']);
      expect(rowsOf(report.categories.single), [
        'tax 10-26 4/4',
        'dentist 10-27',
        'groceries 10-27 5/8',
      ]);
      expect(report.trend, isNull);
      expect(report.missed, isEmpty);
      expect(groupsOf(report.ahead), ['todo 2 0m 0x']);
      expect(rowsOf(report.ahead.single), ['bank 10-29', 'garage 10-31 0/3']);
    });

    test('4 — last week, every category, viewed on Monday 2 November', () {
      final report = fold(
        p4Events(),
        p4Span,
        p4Today,
        missed: p4Missed,
        skipped: p4Skipped,
      );

      expect(report.tense, ReportTense.past);
      // D26: the missed Wednesday is its own number, so Events reads 10.
      expect(tilesOf(report), [
        'events 10',
        'attended 4/5',
        'missed 1',
        'hours 650',
        'tasks 6/9',
      ]);
      expect(report.countedTo, day(2026, 11, 1));
      expect(report.skippedDays, 1);
      expect(report.aheadCount, 0);
      expect(groupsOf(report.categories), [
        'gym 4 240m 1x',
        'friends 3 370m 0x',
        'todo 2 40m 0x',
        'birthday 1 0m 0x',
      ]);
      expect(rowsOf(report.categories[0]), ['gym 4/5 240m']);
      expect(rowsOf(report.categories[1]), [
        'coffee 10-26',
        'dinner 10-27',
        'hike 10-31',
      ]);
      expect(rowsOf(report.categories[2]), [
        'groceries 10-30 5/8',
        'tax 11-1 1/1',
      ]);
      expect(rowsOf(report.categories[3]), ['ana 10-29']);
      final trend = report.trend!;
      expect(trend.unit, ReportTrendUnit.day);
      expect(trend.buckets, hasLength(7));
      expect([for (final b in trend.buckets) b.missed], [0, 0, 1, 0, 0, 0, 0]);
      expect(trend.buckets[2].happened, 0);
      // A Missed header spends no minutes: nothing was spent on the day.
      expect(groupsOf(report.missed), ['gym 1 0m 1x']);
      expect(rowsOf(report.missed.single), ['gym 10-28 missed']);
      expect(report.ahead, isEmpty);
    });

    // D28 compares a plan with the previous span's every occurrence, so the
    // Hours delta is against 11 h 50 (10 h 50 kept plus the missed hour),
    // where the sketch's "−1 h 20" compared against the kept 10 h 50 only.
    // Cardio and Birthday tie at 1 and keep the catalogue's order, Cardio
    // first (the sketch drew Birthday first).
    test('5 — next week, every category, viewed on Sunday 1 November', () {
      final previousTotals = CalendarReportBuilder.foldTotals(
        counted: p4Span,
        events: {for (final e in p4Events()) e.id: e},
        samples: sampled(
          p4Events(),
          p4Span,
          missed: p4Missed,
          skipped: p4Skipped,
        ),
        overrides: const {},
      );
      final events = [
        ev(
          'gymWeek',
          'gym',
          day(2026, 10, 1),
          rule: weekly({1, 2, 4}),
          tracked: true,
          time: at(18, 0, 60),
        ),
        ev(
          'gymSat',
          'gym',
          day(2026, 10, 1),
          rule: weekly({6}),
          tracked: true,
          time: at(10, 0, 60),
        ),
        ev('tudor', 'friends', day(2026, 11, 6), time: at(19, 30, 180)),
        ev('brunch', 'friends', day(2026, 11, 8), time: at(11, 0, 120)),
        ev('bank', 'todo', day(2026, 11, 4)),
        ev('garage', 'todo', day(2026, 11, 7), description: tasks03),
        ev('mihai', 'birthday', day(1986, 11, 3), rule: yearly),
        ev('run', 'cardio', day(2026, 11, 6), time: at(7, 0, 30)),
      ];
      final report = fold(
        events,
        span(day(2026, 11, 2), day(2026, 11, 8)),
        day(2026, 11, 1),
        previousSpan: p4Span,
        previousTotals: previousTotals,
      );

      expect(report.tense, ReportTense.future);
      expect(tilesOf(report), ['planned 10', 'hours 570', 'tasks 0/3']);
      expect(tile(report, ReportTile.planned).previous, 11);
      expect(tile(report, ReportTile.hours).previous, 710);
      expect(tile(report, ReportTile.tasks).previous, 6);
      expect(tile(report, ReportTile.tasks).previousOf, 9);
      expect(report.countedTo, day(2026, 11, 8));
      expect(report.aheadCount, 0);
      expect(groupsOf(report.categories), [
        'gym 4 240m 0x',
        'friends 2 300m 0x',
        'todo 2 0m 0x',
        'cardio 1 30m 0x',
        'birthday 1 0m 0x',
      ]);
      expect(rowsOf(report.categories[0]), [
        'gymWeek 11-2',
        'gymWeek 11-3',
        'gymWeek 11-5',
        'gymSat 11-7',
      ]);
      expect(rowsOf(report.categories[1]), ['tudor 11-6', 'brunch 11-8']);
      expect(rowsOf(report.categories[2]), ['bank 11-4', 'garage 11-7 0/3']);
      expect(rowsOf(report.categories[3]), ['run 11-6']);
      expect(rowsOf(report.categories[4]), ['mihai 11-3']);
      expect(report.trend, isNull);
      expect(report.missed, isEmpty);
      expect(report.ahead, isEmpty);
    });
  });

  group('tense and the counted range', () {
    final october = span(day(2026, 10, 1), day(2026, 10, 31));

    test('tenseOf places a span against today', () {
      expect(
        CalendarReport.tenseOf(span: october, today: day(2026, 11, 1)),
        ReportTense.past,
      );
      expect(
        CalendarReport.tenseOf(span: october, today: day(2026, 10, 31)),
        ReportTense.current,
      );
      expect(
        CalendarReport.tenseOf(span: october, today: day(2026, 10, 1)),
        ReportTense.current,
      );
      expect(
        CalendarReport.tenseOf(span: october, today: day(2026, 9, 30)),
        ReportTense.future,
      );
    });

    test('countedToOf stops at today only in a current span', () {
      expect(
        CalendarReport.countedToOf(span: october, today: day(2026, 10, 30)),
        day(2026, 10, 30),
      );
      expect(
        CalendarReport.countedToOf(span: october, today: day(2026, 11, 5)),
        day(2026, 10, 31),
      );
      expect(
        CalendarReport.countedToOf(span: october, today: day(2026, 9, 1)),
        day(2026, 10, 31),
      );
    });

    test('a span crossing today counts to today and lists the rest ahead', () {
      final gym = ev(
        'gym',
        'gym',
        day(2026, 10, 1),
        rule: daily,
        tracked: true,
        time: at(18, 0, 60),
      );
      // The 1 November mark stands for an assume-absent default on a day
      // that has not come: it must never read as missed.
      final report = fold(
        [gym],
        span(day(2026, 10, 27), day(2026, 11, 2)),
        day(2026, 10, 30),
        missed: {
          'gym': [day(2026, 10, 29), day(2026, 11, 1)],
        },
      );

      expect(report.tense, ReportTense.current);
      expect(report.countedTo, day(2026, 10, 30));
      expect(report.aheadCount, 3);
      expect(tilesOf(report), [
        'events 3',
        'attended 3/4',
        'missed 1',
        'hours 180',
      ]);
      expect(groupsOf(report.categories), ['gym 3 180m 1x']);
      expect(rowsOf(report.categories.single), ['gym 3/4 180m']);
      expect(rowsOf(report.missed.single), ['gym 10-29 missed']);
      expect(rowsOf(report.ahead.single), [
        'gym 10-31',
        'gym 11-1',
        'gym 11-2',
      ]);
    });

    test('a wholly future span is a plan', () {
      final events = [
        ev(
          'gym',
          'gym',
          day(2026, 10, 1),
          rule: weekly({1, 3}),
          tracked: true,
          time: at(18, 0, 60),
        ),
        ev('dentist', 'other', day(2026, 11, 11), time: at(9, 0, 30)),
        ev('a', 'other', day(2026, 11, 12)),
        ev('b', 'other', day(2026, 11, 13)),
      ];
      final report = fold(
        events,
        span(day(2026, 11, 9), day(2026, 11, 15)),
        day(2026, 11, 1),
      );

      expect(report.tense, ReportTense.future);
      expect(kindsOf(report), [ReportTile.planned, ReportTile.hours]);
      expect(tile(report, ReportTile.planned).value, 5);
      expect(tile(report, ReportTile.hours).value, 150);
      expect(report.trend, isNull);
      expect(report.ahead, isEmpty);
      expect(report.aheadCount, 0);
      expect(report.missed, isEmpty);
      expect(
        rowsOf(report.categories.firstWhere((g) => g.categoryId == 'gym')),
        ['gym 11-9', 'gym 11-11'],
      );
    });

    test('a wholly past span is counted to its end, nothing ahead', () {
      final report = fold(
        [ev('run', 'cardio', day(2026, 9, 1), rule: daily)],
        span(day(2026, 9, 1), day(2026, 9, 30)),
        day(2026, 10, 30),
      );

      expect(report.tense, ReportTense.past);
      expect(report.countedTo, day(2026, 9, 30));
      expect(report.aheadCount, 0);
      expect(report.ahead, isEmpty);
      expect(tilesOf(report), ['events 30']);
      expect(report.isEmpty, isFalse);
    });

    test('a skipped day reaches the caption and never the samples', () {
      final input = inputFor(
        [ev('run', 'cardio', day(2026, 9, 1), rule: daily)],
        span(day(2026, 9, 7), day(2026, 9, 11)),
        day(2026, 10, 30),
        skipped: {
          'run': [day(2026, 9, 9)],
        },
      );
      final report = CalendarReportBuilder.fold(input);

      expect(input.samples.map((s) => s.day), isNot(contains(day(2026, 9, 9))));
      expect(report.skippedDays, 1);
      expect(tilesOf(report), ['events 4']);
      expect(report.trend!.buckets[2].happened, 0);
    });
  });

  group('tasks (D27)', () {
    test('a per-day event counts each day\'s own text', () {
      final event = ev(
        'shop',
        'todo',
        day(2026, 9, 1),
        rule: daily,
        description: '- [ ] list',
        perDay: true,
      );
      final report = fold(
        [event],
        span(day(2026, 9, 1), day(2026, 9, 3)),
        day(2026, 10, 30),
        overrides: {
          'shop': {
            day(2026, 9, 1): '- [x] milk\n- [ ] eggs',
            day(2026, 9, 2): '- [x] bread',
          },
        },
      );

      expect(tile(report, ReportTile.tasks).value, 2);
      expect(tile(report, ReportTile.tasks).of, 4);
      expect(rowsOf(report.categories.single), [
        'shop 9-1 1/2',
        'shop 9-2 1/1',
        'shop 9-3 0/1',
      ]);
    });

    test('a shared description counts once across its occurrences', () {
      final event = ev(
        'shop',
        'todo',
        day(2026, 9, 1),
        rule: daily,
        description: '- [x] milk\n- [ ] eggs',
      );
      final report = fold(
        [event],
        span(day(2026, 9, 1), day(2026, 9, 3)),
        day(2026, 10, 30),
        overrides: {
          'shop': {day(2026, 9, 2): '- [x] ignored'},
        },
      );

      expect(tileText(tile(report, ReportTile.tasks)), 'tasks 1/2');
      expect(rowsOf(report.categories.single), [
        'shop 9-1 1/2',
        'shop 9-2 1/2',
        'shop 9-3 1/2',
      ]);
    });

    test('custom states count as open', () {
      final report = fold(
        [
          ev(
            'list',
            'todo',
            day(2026, 9, 1),
            description: '- [-] cancelled\n- [>] moved\n- [x] done',
          ),
        ],
        span(day(2026, 9, 1), day(2026, 9, 7)),
        day(2026, 10, 30),
      );

      expect(tileText(tile(report, ReportTile.tasks)), 'tasks 1/3');
    });
  });

  group('the tile set follows the selection (D15)', () {
    test('a tracked event and an untracked timed one show every grade', () {
      final report = fold(
        [
          ev('gym', 'gym', day(2026, 9, 1), rule: daily, tracked: true),
          ev('run', 'cardio', day(2026, 9, 2), time: at(7, 0, 30)),
        ],
        span(day(2026, 9, 1), day(2026, 9, 7)),
        day(2026, 10, 30),
      );

      expect(kindsOf(report), [
        ReportTile.events,
        ReportTile.attended,
        ReportTile.missed,
        ReportTile.hours,
      ]);
    });

    test('no event with a duration shows no hours tile', () {
      final report = fold(
        [
          ev('gym', 'gym', day(2026, 9, 1), rule: daily, tracked: true),
          ev('run', 'cardio', day(2026, 9, 2), time: at(7, 0)),
        ],
        span(day(2026, 9, 1), day(2026, 9, 7)),
        day(2026, 10, 30),
      );

      expect(kindsOf(report), [
        ReportTile.events,
        ReportTile.attended,
        ReportTile.missed,
      ]);
    });

    test('a period with no occurrence keeps the same tiles', () {
      final events = [
        ev('gym', 'gym', day(2026, 9, 1), rule: weekly({1}), tracked: true),
        ev(
          'tax',
          'todo',
          day(2026, 9, 3),
          time: at(9, 0, 40),
          description: '- [ ] file',
        ),
      ];
      final busy = fold(
        events,
        span(day(2026, 9, 1), day(2026, 9, 7)),
        day(2026, 10, 30),
      );
      final empty = fold(
        events,
        span(day(2026, 8, 25), day(2026, 8, 30)),
        day(2026, 10, 30),
      );

      expect(kindsOf(empty), kindsOf(busy));
      expect(kindsOf(busy), [
        ReportTile.events,
        ReportTile.attended,
        ReportTile.missed,
        ReportTile.hours,
        ReportTile.tasks,
      ]);
      expect(empty.isEmpty, isTrue);
      expect(tilesOf(empty), [
        'events 0',
        'attended 0/0',
        'missed 0',
        'hours 0',
        'tasks 0/0',
      ]);
    });
  });

  group('the trend (D29)', () {
    final week = span(day(2026, 9, 7), day(2026, 9, 13));
    final today = day(2026, 10, 30);

    test('a tie on the busiest weekday names none', () {
      final tied = fold(
        [
          ev('a', 'other', day(2026, 9, 7)),
          ev('b', 'other', day(2026, 9, 7)),
          ev('c', 'other', day(2026, 9, 8)),
          ev('d', 'other', day(2026, 9, 8)),
        ],
        week,
        today,
      );
      final clear = fold(
        [
          ev('a', 'other', day(2026, 9, 7)),
          ev('b', 'other', day(2026, 9, 7)),
          ev('c', 'other', day(2026, 9, 8)),
          ev('d', 'other', day(2026, 9, 9)),
        ],
        week,
        today,
      );

      expect(tied.trend!.busiestWeekday, isNull);
      expect(clear.trend!.busiestWeekday, DateTime.monday);
    });

    test('three timed occurrences make a band, two do not', () {
      final withDurations = fold(
        [
          ev('a', 'other', day(2026, 9, 7), time: at(10, 0, 60)),
          ev('b', 'other', day(2026, 9, 8), time: at(9, 0, 30)),
          ev('c', 'other', day(2026, 9, 9), time: at(12, 0, 30)),
          ev('d', 'other', day(2026, 9, 10)),
        ],
        week,
        today,
      );
      final oneDuration = fold(
        [
          ev('a', 'other', day(2026, 9, 7), time: at(10, 0, 60)),
          ev('b', 'other', day(2026, 9, 8), time: at(9, 0)),
          ev('c', 'other', day(2026, 9, 9), time: at(12, 0)),
          ev('d', 'other', day(2026, 9, 10)),
        ],
        week,
        today,
      );
      final pastMidnight = fold(
        [
          ev('a', 'other', day(2026, 9, 7), time: at(23, 0, 120)),
          ev('b', 'other', day(2026, 9, 8), time: at(22, 0, 60)),
          ev('c', 'other', day(2026, 9, 9), time: at(23, 30, 90)),
          ev('d', 'other', day(2026, 9, 10)),
        ],
        week,
        today,
      );
      final two = fold(
        [
          ev('a', 'other', day(2026, 9, 7), time: at(10, 0, 60)),
          ev('b', 'other', day(2026, 9, 8), time: at(9, 0)),
          ev('c', 'other', day(2026, 9, 9)),
          ev('d', 'other', day(2026, 9, 10)),
        ],
        week,
        today,
      );
      final even = fold(
        [
          ev('a', 'other', day(2026, 9, 7), time: at(9, 0)),
          ev('b', 'other', day(2026, 9, 8), time: at(10, 0)),
          ev('c', 'other', day(2026, 9, 9), time: at(11, 0)),
          ev('d', 'other', day(2026, 9, 10), time: at(12, 0)),
        ],
        week,
        today,
      );

      // Ends 09:30, 11:00 and 12:30 over the same three starts.
      expect(withDurations.trend!.usualStartMinute, 600);
      expect(withDurations.trend!.usualEndMinute, 660);
      // One duration is too few for an end: the start alone, from all three.
      expect(oneDuration.trend!.usualStartMinute, 600);
      expect(oneDuration.trend!.usualEndMinute, isNull);
      // Ends 23:00, 01:00 and 01:00 the next day: a clock minute, not 1500.
      expect(pastMidnight.trend!.usualStartMinute, 23 * 60);
      expect(pastMidnight.trend!.usualEndMinute, 60);
      expect(two.trend!.usualStartMinute, isNull);
      expect(two.trend!.usualEndMinute, isNull);
      expect(even.trend!.usualStartMinute, 600);
      expect(even.trend!.usualEndMinute, isNull);
    });

    test('fewer than four happened occurrences draw no trend', () {
      final report = fold(
        [
          ev('a', 'other', day(2026, 9, 7)),
          ev('b', 'other', day(2026, 9, 8)),
          ev('c', 'other', day(2026, 9, 9)),
        ],
        week,
        today,
      );
      expect(report.trend, isNull);
    });

    test('the unit changes at 31 / 32 and 182 / 183 days', () {
      ReportTrend trendOver(DateRange range) => fold(
        [
          ev(
            'run',
            'cardio',
            range.start,
            rule: daily,
            end: day(range.start.year, range.start.month, range.start.day + 6),
          ),
        ],
        range,
        day(2027, 1, 1),
      ).trend!;

      final days31 = trendOver(span(day(2026, 10, 1), day(2026, 10, 31)));
      final days32 = trendOver(span(day(2026, 10, 1), day(2026, 11, 1)));
      final days182 = trendOver(span(day(2026, 1, 1), day(2026, 7, 1)));
      final days183 = trendOver(span(day(2026, 1, 1), day(2026, 7, 2)));

      expect(days31.unit, ReportTrendUnit.day);
      expect(days31.buckets, hasLength(31));
      expect(days32.unit, ReportTrendUnit.week);
      expect(days182.unit, ReportTrendUnit.week);
      expect(days183.unit, ReportTrendUnit.month);
      expect(
        [for (final b in days183.buckets) b.start],
        [for (var m = 1; m <= 7; m++) day(2026, m, 1)],
      );
      expect(days183.buckets.first.happened, 7);
    });

    test('week columns align to a Sunday week start', () {
      final report = fold(
        [ev('run', 'cardio', day(2026, 10, 1), rule: daily)],
        span(day(2026, 10, 1), day(2026, 11, 15)),
        day(2026, 11, 30),
        weekStart: CalendarWeekStart.sunday,
      );
      final buckets = report.trend!.buckets;

      expect(
        [for (final b in buckets) b.start],
        [
          day(2026, 10, 1),
          day(2026, 10, 4),
          day(2026, 10, 11),
          day(2026, 10, 18),
          day(2026, 10, 25),
          day(2026, 11, 1),
          day(2026, 11, 8),
          day(2026, 11, 15),
        ],
      );
      expect([for (final b in buckets) b.happened], [3, 7, 7, 7, 7, 7, 7, 1]);
    });

    test('columns after today stay at zero', () {
      final report = fold(
        [ev('run', 'cardio', day(2026, 10, 1), rule: daily)],
        span(day(2026, 10, 1), day(2026, 10, 31)),
        day(2026, 10, 10),
      );
      final happened = [for (final b in report.trend!.buckets) b.happened];

      expect(happened.take(10), everyElement(1));
      expect(happened.skip(10), everyElement(0));
      expect(happened, hasLength(31));
    });
  });

  group('deltas (D28)', () {
    const previous = ReportTotals(
      occurrences: 9,
      kept: 7,
      missed: 2,
      attended: 7,
      tracked: 9,
      minutesKept: 420,
      minutesAll: 540,
      tasksTicked: 1,
      tasksTotal: 3,
    );
    List<CalendarEvent> selection() => [
      ev(
        'gym',
        'gym',
        day(2026, 9, 1),
        rule: daily,
        tracked: true,
        time: at(18, 0, 60),
        description: '- [ ] warm up',
      ),
    ];

    test('a past or current span carries the previous totals as passed', () {
      for (final today in [day(2026, 10, 30), day(2026, 10, 4)]) {
        final report = fold(
          selection(),
          span(day(2026, 10, 1), day(2026, 10, 7)),
          today,
          previousTotals: previous,
        );
        expect(tile(report, ReportTile.events).previous, 7);
        expect(tile(report, ReportTile.attended).previous, 7);
        expect(tile(report, ReportTile.attended).previousOf, 9);
        expect(tile(report, ReportTile.missed).previous, 2);
        expect(tile(report, ReportTile.hours).previous, 420);
        expect(tile(report, ReportTile.tasks).previous, 1);
        expect(tile(report, ReportTile.tasks).previousOf, 3);
      }
    });

    test('a plan compares with every previous occurrence', () {
      final report = fold(
        selection(),
        span(day(2026, 11, 2), day(2026, 11, 8)),
        day(2026, 11, 1),
        previousTotals: previous,
      );
      expect(tile(report, ReportTile.planned).previous, 9);
      expect(tile(report, ReportTile.hours).previous, 540);
    });

    test('no previous totals leave every delta null', () {
      final report = fold(
        selection(),
        span(day(2026, 10, 1), day(2026, 10, 7)),
        day(2026, 10, 30),
      );
      for (final t in report.tiles) {
        expect(t.previous, isNull);
        expect(t.previousOf, isNull);
      }
    });
  });

  group('groups and rows', () {
    test('larger counts first, the catalogue breaking ties', () {
      final report = fold(
        [
          ev('f1', 'friends', day(2026, 9, 7)),
          ev('c1', 'cardio', day(2026, 9, 8)),
          ev('t1', 'todo', day(2026, 9, 7)),
          ev('t2', 'todo', day(2026, 9, 8)),
          ev('lost', 'deleted-category', day(2026, 9, 9)),
        ],
        span(day(2026, 9, 7), day(2026, 9, 13)),
        day(2026, 10, 30),
      );

      expect(
        [for (final g in report.categories) g.categoryId],
        ['todo', 'cardio', 'other', 'friends'],
      );
    });

    test(
      'routines lead, dated rows follow oldest first, a day in its order',
      () {
        final report = fold(
          [
            ev('routine', 'gym', day(2026, 9, 9), rule: daily, tracked: true),
            ev('morning', 'gym', day(2026, 9, 8), time: at(8, 0)),
            ev('allDay', 'gym', day(2026, 9, 8)),
            ev('urgent', 'gym', day(2026, 9, 8), time: at(20, 0), priority: 1),
            ev('earlier', 'gym', day(2026, 9, 7), time: at(23, 0)),
          ],
          span(day(2026, 9, 7), day(2026, 9, 10)),
          day(2026, 10, 30),
        );

        expect(rowsOf(report.categories.single), [
          'routine 2/2 0m',
          'earlier 9-7',
          'urgent 9-8',
          'allDay 9-8',
          'morning 9-8',
        ]);
      },
    );

    test('routines order by occurrences, then by title', () {
      final report = fold(
        [
          ev('b', 'gym', day(2026, 9, 7), rule: daily, tracked: true),
          ev('a', 'gym', day(2026, 9, 8), rule: daily, tracked: true),
          ev('c', 'gym', day(2026, 9, 8), rule: daily, tracked: true),
        ],
        span(day(2026, 9, 7), day(2026, 9, 10)),
        day(2026, 10, 30),
      );

      expect(rowsOf(report.categories.single), [
        'b 4/4 0m',
        'a 3/3 0m',
        'c 3/3 0m',
      ]);
    });
  });

  group('the review cases', () {
    CalendarEvent gymDaily() => ev(
      'gym',
      'gym',
      day(2026, 9, 1),
      rule: daily,
      tracked: true,
      time: at(18, 0, 60),
    );

    test('today on the span\'s first day counts one day', () {
      final report = fold(
        [gymDaily()],
        span(day(2026, 10, 1), day(2026, 10, 7)),
        day(2026, 10, 1),
      );
      expect(report.tense, ReportTense.current);
      expect(report.countedTo, day(2026, 10, 1));
      expect(tile(report, ReportTile.events).value, 1);
      expect(report.aheadCount, 6);
    });

    test('today on the span\'s last day leaves nothing ahead', () {
      final report = fold(
        [gymDaily()],
        span(day(2026, 10, 1), day(2026, 10, 7)),
        day(2026, 10, 7),
      );
      expect(report.tense, ReportTense.current);
      expect(report.countedTo, day(2026, 10, 7));
      expect(tile(report, ReportTile.events).value, 7);
      expect(report.aheadCount, 0);
      expect(report.ahead, isEmpty);
    });

    test('a one-day span is counted on its day', () {
      final report = fold(
        [gymDaily()],
        span(day(2026, 10, 5), day(2026, 10, 5)),
        day(2026, 10, 5),
      );
      expect(report.tense, ReportTense.current);
      expect(tilesOf(report), [
        'events 1',
        'attended 1/1',
        'missed 0',
        'hours 60',
      ]);
      expect(report.aheadCount, 0);
      expect(report.trend, isNull);
    });

    test('a routine missed every day reads 0 of n and sorts last', () {
      final report = fold(
        [gymDaily(), ev('nap', 'rest', day(2026, 9, 8))],
        span(day(2026, 9, 7), day(2026, 9, 10)),
        day(2026, 10, 30),
        missed: {
          'gym': [
            day(2026, 9, 7),
            day(2026, 9, 8),
            day(2026, 9, 9),
            day(2026, 9, 10),
          ],
        },
      );
      expect(tileText(tile(report, ReportTile.attended)), 'attended 0/4');
      expect(groupsOf(report.categories), ['rest 1 0m 0x', 'gym 0 0m 4x']);
      expect(rowsOf(report.categories.last), ['gym 0/4 0m']);
    });

    test('a routine aggregate opens on its latest attended day, else on its '
        'latest counted day', () {
      final report = fold(
        [
          gymDaily(),
          ev('yoga', 'mobility', day(2026, 9, 1), rule: daily, tracked: true),
        ],
        span(day(2026, 9, 1), day(2026, 9, 5)),
        day(2026, 10, 30),
        missed: {
          'gym': [day(2026, 9, 2), day(2026, 9, 4), day(2026, 9, 5)],
          'yoga': [for (var d = 1; d <= 5; d++) day(2026, 9, d)],
        },
      );
      ReportRoutineRow routineOf(String id) => report.categories
          .expand((g) => g.rows)
          .whereType<ReportRoutineRow>()
          .singleWhere((r) => r.eventId == id);
      expect(routineOf('gym').latestDay, day(2026, 9, 3));
      expect(
        routineOf('yoga').latestDay,
        day(2026, 9, 5),
        reason: 'every day missed: the latest counted one',
      );

      final sparse = fold(
        [
          ev(
            'gym',
            'gym',
            day(2026, 9, 1),
            rule: weekly({1, 3, 5}),
            tracked: true,
          ),
        ],
        span(day(2026, 9, 7), day(2026, 9, 11)),
        day(2026, 10, 30),
        missed: {
          'gym': [day(2026, 9, 9), day(2026, 9, 11)],
        },
      );
      final row = sparse.categories.single.rows.single as ReportRoutineRow;
      expect(row.latestDay, day(2026, 9, 7), reason: 'days 9 and 11 missed');
    });

    test('an empty override blanks its day\'s tasks', () {
      final report = fold(
        [
          ev(
            'shop',
            'todo',
            day(2026, 9, 1),
            rule: daily,
            description: '- [ ] list',
            perDay: true,
          ),
        ],
        span(day(2026, 9, 1), day(2026, 9, 3)),
        day(2026, 10, 30),
        overrides: {
          'shop': {day(2026, 9, 2): ''},
        },
      );
      expect(tileText(tile(report, ReportTile.tasks)), 'tasks 0/2');
      expect(rowsOf(report.categories.single), [
        'shop 9-1 0/1',
        'shop 9-2',
        'shop 9-3 0/1',
      ]);
    });

    test('an override outside the span still decides the tasks tile', () {
      final report = fold(
        [ev('shop', 'todo', day(2026, 9, 1), rule: daily, perDay: true)],
        span(day(2026, 9, 1), day(2026, 9, 3)),
        day(2026, 10, 30),
        overrides: {
          'shop': {day(2026, 8, 20): '- [ ] list'},
        },
      );
      expect(tileText(tile(report, ReportTile.tasks)), 'tasks 0/0');
      expect(rowsOf(report.categories.single), [
        'shop 9-1',
        'shop 9-2',
        'shop 9-3',
      ]);
    });

    test('an untracked occurrence flagged missed is kept', () {
      final report = fold(
        [ev('run', 'cardio', day(2026, 9, 8))],
        span(day(2026, 9, 7), day(2026, 9, 13)),
        day(2026, 10, 30),
        missed: {
          'run': [day(2026, 9, 8)],
        },
      );
      expect(tilesOf(report), ['events 1']);
      expect(groupsOf(report.categories), ['cardio 1 0m 0x']);
      expect(rowsOf(report.categories.single), ['run 9-8']);
      expect(report.missed, isEmpty);
    });

    test('month columns cross a year boundary', () {
      final report = fold(
        [
          ev(
            'run',
            'cardio',
            day(2026, 12, 28),
            rule: daily,
            end: day(2027, 1, 3),
          ),
        ],
        span(day(2026, 9, 1), day(2027, 3, 31)),
        day(2027, 4, 15),
      );
      final buckets = report.trend!.buckets;
      expect(report.trend!.unit, ReportTrendUnit.month);
      expect(
        [for (final b in buckets) b.start],
        [
          day(2026, 9, 1),
          day(2026, 10, 1),
          day(2026, 11, 1),
          day(2026, 12, 1),
          day(2027, 1, 1),
          day(2027, 2, 1),
          day(2027, 3, 1),
        ],
      );
      expect([for (final b in buckets) b.happened], [0, 0, 0, 4, 3, 0, 0]);
    });

    test('week columns align to a Saturday week start', () {
      final report = fold(
        [ev('run', 'cardio', day(2026, 10, 1), rule: daily)],
        span(day(2026, 10, 1), day(2026, 11, 1)),
        day(2026, 11, 30),
        weekStart: CalendarWeekStart.saturday,
      );
      final buckets = report.trend!.buckets;
      expect(
        [for (final b in buckets) b.start],
        [
          day(2026, 10, 1),
          day(2026, 10, 3),
          day(2026, 10, 10),
          day(2026, 10, 17),
          day(2026, 10, 24),
          day(2026, 10, 31),
        ],
      );
      expect([for (final b in buckets) b.happened], [2, 7, 7, 7, 7, 2]);
    });

    test('a 365-day span has 13 month columns', () {
      final report = fold(
        [ev('run', 'cardio', day(2026, 10, 1), rule: daily)],
        span(day(2025, 10, 31), day(2026, 10, 30)),
        day(2026, 10, 30),
      );
      expect(report.trend!.unit, ReportTrendUnit.month);
      expect(report.trend!.buckets, hasLength(13));
      expect(report.trend!.buckets.first.start, day(2025, 10, 31));
      expect(report.trend!.buckets.last.start, day(2026, 10, 1));
    });

    test('a pending session today is ahead, not counted (D31)', () {
      // Marked missed as well: an assume-absent default reads today as a
      // past day, and the pending flag is what keeps it out of the grade.
      final report = fold(
        [gymDaily()],
        span(day(2026, 10, 27), day(2026, 11, 2)),
        day(2026, 10, 30),
        missed: {
          'gym': [day(2026, 10, 30)],
        },
        pending: {
          'gym': [day(2026, 10, 30)],
        },
      );
      expect(tilesOf(report), [
        'events 3',
        'attended 3/3',
        'missed 0',
        'hours 180',
      ]);
      expect(groupsOf(report.categories), ['gym 3 180m 0x']);
      expect(rowsOf(report.categories.single), ['gym 3/3 180m']);
      expect(report.missed, isEmpty);
      expect(report.aheadCount, 4);
      expect(groupsOf(report.ahead), ['gym 4 240m 0x']);
      expect(rowsOf(report.ahead.single), [
        'gym 10-30',
        'gym 10-31',
        'gym 11-1',
        'gym 11-2',
      ]);
    });

    test('a pending session on the span\'s last day is still ahead', () {
      final report = fold(
        [gymDaily()],
        span(day(2026, 10, 24), day(2026, 10, 30)),
        day(2026, 10, 30),
        pending: {
          'gym': [day(2026, 10, 30)],
        },
      );
      expect(tile(report, ReportTile.events).value, 6);
      expect(report.aheadCount, 1);
      expect(rowsOf(report.ahead.single), ['gym 10-30']);
    });

    test('a plan ignores the pending flag', () {
      final base = inputFor(
        [gymDaily()],
        span(day(2026, 11, 2), day(2026, 11, 8)),
        day(2026, 11, 1),
      );
      final withPending = ReportInput(
        span: base.span,
        today: base.today,
        weekStart: base.weekStart,
        events: base.events,
        categoryOf: base.categoryOf,
        samples: [
          ReportSample(eventId: 'gym', day: day(2026, 11, 1), pending: true),
          ...base.samples,
        ],
        categoryOrder: base.categoryOrder,
      );
      final plain = CalendarReportBuilder.fold(base);
      final report = CalendarReportBuilder.fold(withPending);
      expect(report.tense, ReportTense.future);
      expect(tilesOf(report), tilesOf(plain));
      expect(tilesOf(report), ['planned 7', 'hours 420']);
      expect(report.aheadCount, 0);
      expect(report.categories, plain.categories);
    });

    test('the report\'s collections cannot be changed', () {
      final report = fold(
        [gymDaily()],
        span(day(2026, 10, 1), day(2026, 10, 7)),
        day(2026, 10, 30),
      );
      expect(() => report.tiles.clear(), throwsUnsupportedError);
      expect(() => report.categories.clear(), throwsUnsupportedError);
      expect(() => report.events.clear(), throwsUnsupportedError);
      expect(() => report.trend!.buckets.clear(), throwsUnsupportedError);
    });

    test('a day that is not date-only UTC is refused in debug', () {
      final valid = inputFor(
        [gymDaily()],
        span(day(2026, 10, 1), day(2026, 10, 7)),
        day(2026, 10, 30),
      );
      ReportInput withToday(DateTime today, {List<ReportSample>? samples}) =>
          ReportInput(
            span: valid.span,
            today: today,
            weekStart: valid.weekStart,
            events: valid.events,
            categoryOf: valid.categoryOf,
            samples: samples ?? valid.samples,
            categoryOrder: valid.categoryOrder,
          );

      expect(
        () => CalendarReportBuilder.fold(withToday(DateTime(2026, 10, 30))),
        throwsAssertionError,
      );
      expect(
        () => CalendarReportBuilder.fold(
          withToday(
            day(2026, 10, 30),
            samples: [ReportSample(eventId: 'gym', day: DateTime(2026, 10, 2))],
          ),
        ),
        throwsAssertionError,
      );
      expect(
        () => CalendarReportBuilder.fold(
          withToday(
            day(2026, 10, 30),
            samples: [
              ReportSample(
                eventId: 'gym',
                day: day(2026, 10, 2),
                pending: true,
              ),
            ],
          ),
        ),
        throwsAssertionError,
      );
    });
  });

  // The analytics measures (S2a-i): each one fires on its fixture and stays
  // quiet on its twin, from the same samples the groups fold.
  EffectiveProfile kindOf(
    CategoryKind kind, {
    ReportMeasure? measure,
    int? nominal,
    bool? countsHours,
  }) => CategoryProfile(
    id: 'p',
    categoryId: 'c',
    kind: kind,
    measure: measure,
    nominalMinutes: nominal,
    countsHours: countsHours,
  ).effective;

  CalendarReport foldFacts(
    List<CalendarEvent> events,
    DateRange range,
    DateTime today, {
    Map<String, List<DateTime>> missed = const {},
    Map<String, List<DateTime>> skipped = const {},
    Map<String, List<DateTime>> pending = const {},
    Map<String, Map<DateTime, String>> overrides = const {},
    CalendarWeekStart weekStart = CalendarWeekStart.monday,
    Map<String, EffectiveProfile> profiles = const {},
    Map<String, int> money = const {},
    Map<String, DateTime> lastSeenBefore = const {},
    Map<String, List<ReportSample>> lookback = const {},
    Map<String, List<ReportSample>> lookahead = const {},
    List<ReportSample> billsAhead = const [],
  }) {
    final base = inputFor(
      events,
      range,
      today,
      missed: missed,
      skipped: skipped,
      pending: pending,
      overrides: overrides,
      weekStart: weekStart,
    );
    return CalendarReportBuilder.fold(
      ReportInput(
        span: base.span,
        today: base.today,
        weekStart: base.weekStart,
        events: base.events,
        categoryOf: base.categoryOf,
        samples: base.samples,
        overrides: base.overrides,
        skippedDays: base.skippedDays,
        categoryOrder: base.categoryOrder,
        profiles: profiles,
        cancelled: [
          for (final MapEntry(:key, :value) in skipped.entries)
            for (final d in value) ReportSample(eventId: key, day: d),
        ],
        money: money,
        lastSeenBefore: lastSeenBefore,
        lookback: lookback,
        lookahead: lookahead,
        billsAhead: billsAhead,
      ),
    );
  }

  /// What the sampler's bills-ahead scan hands over: [events]' samples from
  /// [today] to today + `AnalyticsMetrics.billsAheadDays`.
  List<ReportSample> billsAheadOf(List<CalendarEvent> events, DateTime today) =>
      sampled(
        events,
        span(
          today,
          day(
            today.year,
            today.month,
            today.day + AnalyticsMetrics.billsAheadDays,
          ),
        ),
      );

  group('measures (analytics H, §6.3)', () {
    final september = span(day(2026, 9, 1), day(2026, 9, 30));
    final firstThree = span(day(2026, 9, 1), day(2026, 9, 3));
    final later = day(2026, 10, 30);

    test('count is kept days, events the distinct events kept', () {
      final report = foldFacts(
        [
          ev('gym', 'gym', day(2026, 9, 1), rule: daily, tracked: true),
          ev('swim', 'gym', day(2026, 9, 2)),
          ev('yoga', 'gym', day(2026, 9, 1), rule: daily, tracked: true),
          ev('later', 'cardio', day(2026, 10, 5)),
        ],
        firstThree,
        later,
        missed: {
          'gym': [day(2026, 9, 2)],
          'yoga': [day(2026, 9, 1), day(2026, 9, 2), day(2026, 9, 3)],
        },
      );
      final gym = report.measures['gym']!;
      expect((gym.count, gym.events), (3, 2), reason: 'yoga kept nothing');
      final cardio = report.measures['cardio']!;
      expect((cardio.count, cardio.events), (0, 0));
      expect(report.measures.keys, unorderedEquals(['gym', 'cardio']));
    });

    test('hours sum the kept timed days, no counts-as without a profile', () {
      final report = foldFacts(
        [
          ev(
            'gym',
            'gym',
            day(2026, 9, 1),
            rule: daily,
            tracked: true,
            time: at(6, 0, 45),
          ),
          ev('stretch', 'mobility', day(2026, 9, 1), rule: daily),
        ],
        firstThree,
        later,
        missed: {
          'gym': [day(2026, 9, 2)],
        },
      );
      expect(report.measures['gym']!.minutes, 90);
      expect(report.measures['gym']!.nominalMinutes, 0);
      expect(report.measures['mobility']!.minutes, 0);
      expect(tile(report, ReportTile.hours).value, 90);
      expect(report.nominalMinutes, 0);
    });

    test('a confirmed counts-as fills a routine\'s untimed day', () {
      final events = [
        ev('stretch', 'mobility', day(2026, 9, 1), rule: daily, tracked: true),
      ];
      final report = foldFacts(
        events,
        firstThree,
        later,
        profiles: {'mobility': kindOf(CategoryKind.custom, nominal: 30)},
      );
      final mobility = report.measures['mobility']!;
      expect((mobility.minutes, mobility.nominalMinutes), (90, 90));
      expect(tile(report, ReportTile.hours).value, 90);
      expect(report.nominalMinutes, 90);

      final bare = foldFacts(events, firstThree, later);
      expect(bare.measures['mobility']!.minutes, 0);
      expect(kindsOf(bare), isNot(contains(ReportTile.hours)));
    });

    test('a counts-as fills a one-off, never a repeat', () {
      final report = foldFacts(
        [
          ev('walk', 'mobility', day(2026, 9, 1), rule: daily),
          ev('call', 'mobility', day(2026, 9, 2)),
        ],
        firstThree,
        later,
        profiles: {'mobility': kindOf(CategoryKind.custom, nominal: 30)},
      );
      final mobility = report.measures['mobility']!;
      expect((mobility.minutes, mobility.nominalMinutes), (30, 30));
      expect(tile(report, ReportTile.hours).value, 30);
    });

    test('a category whose hours do not count stays out of the tile', () {
      final report = foldFacts(
        [
          ev(
            'gym',
            'gym',
            day(2026, 9, 1),
            rule: daily,
            tracked: true,
            time: at(6, 0, 45),
          ),
          ev('run', 'cardio', day(2026, 9, 2), time: at(7, 0, 30)),
        ],
        firstThree,
        later,
        profiles: {'gym': kindOf(CategoryKind.custom, countsHours: false)},
      );
      expect(tile(report, ReportTile.hours).value, 30);
      expect(report.measures['gym']!.minutes, 135, reason: 'still measured');
    });

    test('a tracked one-off missed counts against attendance (AM)', () {
      final events = [
        ev('gym', 'gym', day(2026, 9, 1), rule: weekly({1}), tracked: true),
        ev('dentist', 'other', day(2026, 9, 10), tracked: true),
      ];
      final week = span(day(2026, 9, 7), day(2026, 9, 13));
      final kept = foldFacts(events, week, later);
      final lost = foldFacts(
        events,
        week,
        later,
        missed: {
          'dentist': [day(2026, 9, 10)],
        },
      );
      expect(tileText(tile(kept, ReportTile.attended)), 'attended 2/2');
      expect(tile(kept, ReportTile.missed).value, 0);
      expect(tileText(tile(lost, ReportTile.attended)), 'attended 1/2');
      expect(tile(lost, ReportTile.missed).value, 1);
      expect(tile(lost, ReportTile.events).value, 1);
      final other = lost.measures['other']!;
      expect((other.attended, other.tracked), (0, 1));
      expect(groupsOf(lost.missed), ['other 1 0m 1x']);
      expect(rowsOf(lost.missed.single), ['dentist 9-10 missed']);
    });

    test('today\'s pending day is out of attendance and is the next', () {
      final report = foldFacts(
        [ev('gym', 'gym', day(2026, 9, 1), rule: daily, tracked: true)],
        september,
        day(2026, 9, 3),
        pending: {
          'gym': [day(2026, 9, 3)],
        },
      );
      final gym = report.measures['gym']!;
      expect((gym.attended, gym.tracked), (2, 2));
      expect(
        (gym.nextDay, gym.daysUntil),
        (day(2026, 9, 3), 0),
        reason: 'still to come today, so the next occurrence',
      );
    });

    test('cancelled days count of the planned ones', () {
      final events = [
        ev('gym', 'gym', day(2026, 9, 1), rule: daily, tracked: true),
      ];
      final five = span(day(2026, 9, 1), day(2026, 9, 5));
      final cancelled = foldFacts(
        events,
        five,
        later,
        skipped: {
          'gym': [day(2026, 9, 3)],
        },
      ).measures['gym']!;
      expect((cancelled.cancelled, cancelled.planned), (1, 5));
      expect(cancelled.count, 4);
      final none = foldFacts(events, five, later).measures['gym']!;
      expect((none.cancelled, none.planned), (0, 5));
    });

    test('tasks lead a Task category until it holds no box', () {
      final profiles = {'todo': kindOf(CategoryKind.task)};
      final boxed = foldFacts(
        [ev('list', 'todo', day(2026, 9, 2), description: '- [x] a\n- [ ] b')],
        firstThree,
        later,
        profiles: profiles,
      ).measures['todo']!;
      expect(
        (boxed.primary, boxed.fallbackApplied),
        (ReportMeasure.tasks, false),
      );
      expect((boxed.tasksTicked, boxed.tasksTotal), (1, 2));
      final bare = foldFacts(
        [ev('list', 'todo', day(2026, 9, 2))],
        firstThree,
        later,
        profiles: profiles,
      ).measures['todo']!;
      expect((bare.primary, bare.fallbackApplied), (ReportMeasure.count, true));
    });

    test('money is read once per event starting in the span', () {
      final report = foldFacts(
        [
          ev(
            'rent',
            'other',
            day(2026, 9, 1),
            rule: weekly({1}),
          ).copyWith(noteId: 'n1'),
          ev('pay', 'other', day(2026, 9, 15)).copyWith(noteId: 'n2'),
          ev(
            'old',
            'other',
            day(2026, 8, 1),
            rule: weekly({2}),
          ).copyWith(noteId: 'n3'),
          ev('dues', 'friends', day(2026, 9, 3)),
        ],
        september,
        later,
        profiles: {
          'other': kindOf(CategoryKind.bill),
          'friends': kindOf(CategoryKind.bill),
        },
        money: {'rent': -1250, 'pay': 500, 'old': -999},
      );
      final other = report.measures['other']!;
      expect((other.spentCents, other.receivedCents), (1250, 500));
      expect((other.hasMoney, other.primary), (true, ReportMeasure.money));
      final friends = report.measures['friends']!;
      expect((friends.hasMoney, friends.spentCents), (false, 0));
      expect(
        (friends.primary, friends.fallbackApplied),
        (ReportMeasure.count, true),
      );
    });

    test('last seen reads the span first, then the lookback', () {
      final inSpan = foldFacts(
        [ev('service', 'other', day(2026, 9, 10))],
        september,
        later,
        lastSeenBefore: {'other': day(2026, 8, 20)},
      ).measures['other']!;
      expect((inSpan.lastSeenDay, inSpan.lastSeenDays), (day(2026, 9, 10), 50));

      final before = foldFacts(
        [ev('service', 'other', day(2026, 8, 20))],
        september,
        later,
        lastSeenBefore: {'other': day(2026, 8, 20)},
      ).measures['other']!;
      expect((before.lastSeenDay, before.lastSeenDays), (day(2026, 8, 20), 71));

      final never = foldFacts(
        [ev('service', 'other', day(2026, 8, 20))],
        september,
        later,
      ).measures['other']!;
      expect((never.lastSeenDay, never.lastSeenDays), (null, null));
    });

    test('lead time is the lower median over the one-offs that know it', () {
      CalendarEvent booked(String id, DateTime on, DateTime? created) =>
          ev(id, 'other', on).copyWith(createdAt: created);
      final three = [
        booked('a', day(2026, 9, 10), DateTime(2026, 9, 1, 15, 30)),
        booked('b', day(2026, 9, 12), DateTime(2026, 9, 10, 8)),
        booked('c', day(2026, 9, 20), DateTime(2026, 9, 15, 23, 59)),
        booked('d', day(2026, 9, 25), null),
      ];
      expect(
        foldFacts(three, september, later).measures['other']!.leadTimeDays,
        5,
        reason: '2, 5 and 9 days; d carries no creation day',
      );
      expect(
        foldFacts(
          [three[0], three[1]],
          september,
          later,
        ).measures['other']!.leadTimeDays,
        2,
      );
      expect(
        foldFacts([three[3]], september, later).measures['other']!.leadTimeDays,
        isNull,
      );
    });

    test('timing: the median start and the late evenings', () {
      final other = foldFacts(
        [
          ev('a', 'other', day(2026, 9, 1), time: at(6, 0, 30)),
          ev('b', 'other', day(2026, 9, 2), time: at(7, 0, 30)),
          ev('c', 'other', day(2026, 9, 3), time: at(18, 0, 90)),
          ev('d', 'other', day(2026, 9, 4), time: at(17, 0, 120)),
          ev('e', 'other', day(2026, 9, 5)),
        ],
        september,
        later,
      ).measures['other']!;
      expect(other.medianStartMinute, 7 * 60);
      expect(other.lateDays, 1, reason: '19:30 is late, 19:00 is not');

      final untimed = foldFacts(
        [ev('e', 'other', day(2026, 9, 5))],
        september,
        later,
      ).measures['other']!;
      expect((untimed.medianStartMinute, untimed.lateDays), (null, 0));
    });

    test('the weekday histogram starts at the week start', () {
      final mondays = [
        ev('gym', 'gym', day(2026, 9, 1), rule: weekly({DateTime.monday})),
      ];
      expect(
        foldFacts(mondays, september, later).measures['gym']!.weekdayHistogram,
        [4, 0, 0, 0, 0, 0, 0],
      );
      expect(
        foldFacts(
          mondays,
          september,
          later,
          weekStart: CalendarWeekStart.saturday,
        ).measures['gym']!.weekdayHistogram,
        [0, 0, 4, 0, 0, 0, 0],
      );
    });

    test('days until reads the first occurrence after today', () {
      final report = foldFacts(
        [
          ev('a', 'other', day(2026, 9, 20)),
          ev('b', 'cardio', day(2026, 9, 10)),
        ],
        september,
        day(2026, 9, 15),
      );
      final other = report.measures['other']!;
      expect((other.nextDay, other.daysUntil), (day(2026, 9, 20), 5));
      final cardio = report.measures['cardio']!;
      expect((cardio.nextDay, cardio.daysUntil), (null, null));
    });

    test('Auto picks by the first rule that holds (§6.2)', () {
      final report = foldFacts(
        [
          ev('gym', 'gym', day(2026, 9, 2), rule: daily, tracked: true),
          ev('run', 'cardio', day(2026, 9, 2), time: at(7, 0, 30)),
          ev('list', 'todo', day(2026, 9, 2), description: '- [ ] x'),
          ev('walk', 'mobility', day(2026, 9, 2), rule: daily),
          ev('misc', 'other', day(2026, 9, 2)),
          ev('call', 'friends', day(2026, 9, 2)),
        ],
        september,
        later,
        profiles: {'friends': kindOf(CategoryKind.custom, nominal: 60)},
      );
      ReportMeasure primary(String id) => report.measures[id]!.primary;
      expect(primary('gym'), ReportMeasure.attendance);
      expect(primary('cardio'), ReportMeasure.hours);
      expect(primary('todo'), ReportMeasure.tasks);
      expect(primary('mobility'), ReportMeasure.count);
      expect(primary('other'), ReportMeasure.count);
      expect(primary('friends'), ReportMeasure.hours, reason: 'a counts-as');
      expect(report.measures.values.where((m) => m.fallbackApplied), isEmpty);
    });

    test('a profile\'s primary outranks Auto', () {
      final gym = foldFacts(
        [ev('gym', 'gym', day(2026, 9, 2), rule: daily, tracked: true)],
        september,
        later,
        profiles: {
          'gym': kindOf(CategoryKind.custom, measure: ReportMeasure.count),
        },
      ).measures['gym']!;
      expect(gym.primary, ReportMeasure.count);
    });

    test('the DST month counts every day once', () {
      // The last Sunday of March 2026 is the 29th.
      final march = span(day(2026, 3, 1), day(2026, 3, 31));
      final report = foldFacts(
        [
          ev(
            'run',
            'cardio',
            day(2026, 3, 1),
            rule: daily,
          ).copyWith(title: 'Run #run'),
        ],
        march,
        day(2026, 4, 30),
      );
      final cardio = report.measures['cardio']!;
      expect(cardio.count, 31);
      expect(cardio.weekdayHistogram.fold(0, (a, b) => a + b), 31);
      final rows = report.tags.single.rows.cast<ReportDatedRow>();
      expect({for (final r in rows) r.day}, hasLength(31));
      expect(
        (rows.first.day, rows.last.day),
        (day(2026, 3, 1), day(2026, 3, 31)),
      );
    });
  });

  group('tags (Y, §6.9)', () {
    final firstThree = span(day(2026, 9, 1), day(2026, 9, 3));
    final later = day(2026, 10, 30);

    test('the grammar is the editor\'s', () {
      expect(extractTags('Dinner with #ana'), ['ana']);
      expect(extractTags('#golf/service done'), ['golf/service']);
      expect(extractTags('#2024 recap'), isEmpty, reason: 'no letter');
      expect(extractTags('a#b'), isEmpty, reason: 'no word boundary');
      expect(extractTags('(#ana) and #ana again, #Ana'), ['ana', 'Ana']);
      expect(extractTags('#ana/'), ['ana']);
      expect(extractTags(null), isEmpty);
    });

    test('a title tag folds with its event', () {
      final tag = foldFacts(
        [
          ev(
            'dinner',
            'friends',
            day(2026, 9, 2),
            time: at(19, 0, 120),
          ).copyWith(title: 'Dinner with #ana'),
        ],
        firstThree,
        later,
        money: {'dinner': -4200},
      ).tags.single;
      expect((tag.key, tag.label, tag.events, tag.count), ('ana', 'ana', 1, 1));
      expect((tag.minutes, tag.spentCents), (120, 4200));
      expect(tag.lastSeenDay, day(2026, 9, 2));
      expect(tag.categoryIds, ['friends']);
      expect(tag.rows.map(rowText), ['dinner 9-2']);
    });

    test('#Ana and #ana are one key under the first spelling', () {
      final tags = foldFacts(
        [
          ev('lunch', 'friends', day(2026, 9, 1)).copyWith(title: 'Lunch #Ana'),
          ev('dinner', 'other', day(2026, 9, 2)).copyWith(title: 'Dinner #ana'),
        ],
        firstThree,
        later,
      ).tags;
      expect(tags, hasLength(1));
      final tag = tags.single;
      expect((tag.key, tag.label, tag.events, tag.count), ('ana', 'Ana', 2, 2));
      expect(tag.categoryIds, ['friends', 'other']);
    });

    test('a day counts a tag once, a missed day never', () {
      final tag = foldFacts(
        [
          ev(
            'gym',
            'gym',
            day(2026, 9, 1),
            rule: daily,
            tracked: true,
            description: 'with #coach',
          ).copyWith(title: 'Gym #coach'),
        ],
        firstThree,
        later,
        missed: {
          'gym': [day(2026, 9, 2)],
        },
      ).tags.single;
      expect((tag.events, tag.count), (1, 2));
      expect(tag.rows.map(rowText), ['gym 9-1', 'gym 9-3']);
    });

    test('a per-day text tags its own day only', () {
      final tag = foldFacts(
        [ev('walk', 'mobility', day(2026, 9, 1), rule: daily, perDay: true)],
        firstThree,
        later,
        overrides: {
          'walk': {day(2026, 9, 2): 'with #ana'},
        },
      ).tags.single;
      expect((tag.key, tag.count), ('ana', 1));
      expect(tag.rows.map(rowText), ['walk 9-2']);
    });

    test('money counts once per tagged event', () {
      final tag = foldFacts(
        [
          ev(
            'rent',
            'other',
            day(2026, 9, 1),
            rule: daily,
          ).copyWith(title: 'Rent #flat', noteId: 'n'),
        ],
        firstThree,
        later,
        money: {'rent': -1000},
      ).tags.single;
      expect((tag.count, tag.spentCents), (3, 1000));
    });

    test('every tag by events, then days, then key, uncapped', () {
      final report = foldFacts(
        [
          for (var i = 0; i < 10; i++)
            ev('t$i', 'other', day(2026, 9, 1)).copyWith(title: 'T #t$i'),
          ev('pair', 'other', day(2026, 9, 2)).copyWith(title: 'Pair #t9'),
          ev(
            'z',
            'other',
            day(2026, 9, 1),
            rule: daily,
          ).copyWith(title: 'Daily #z'),
        ],
        firstThree,
        later,
      );
      expect(
        report.tags,
        hasLength(greaterThan(AnalyticsMetrics.tagRows)),
        reason: 'R1 reads the rarely seen tag a cap would drop; the card caps',
      );
      expect(report.tags.map((t) => t.key), [
        't9',
        'z',
        't0',
        't1',
        't2',
        't3',
        't4',
        't5',
        't6',
        't7',
        't8',
      ]);
    });

    test('a span with no tag lists none', () {
      expect(
        foldFacts([ev('gym', 'gym', day(2026, 9, 1))], firstThree, later).tags,
        isEmpty,
      );
    });
  });

  // The goals, Due soon, Balance and When (S2a-ii): each state on its own
  // fixture, from the samples the measures fold and the lookback before.
  EffectiveProfile targeted(
    CategoryKind kind,
    ReportTarget target, {
    ReportMeasure? measure,
  }) => CategoryProfile(
    id: 'p',
    categoryId: 'c',
    kind: kind,
    measure: measure,
    target: target,
  ).effective;
  ReportTarget perPeriod(TargetKind kind, int value, TargetPeriod period) =>
      ReportTarget(kind: kind, value: value, period: period);
  ReportTarget maxGap(int days) =>
      ReportTarget(kind: TargetKind.maxGap, value: days);

  /// What the sampler's lookback hands over: [events]' samples of the
  /// lookback's days before [range], never past [today].
  Map<String, List<ReportSample>> lookbackFor(
    String categoryId,
    List<CalendarEvent> events,
    DateRange range,
    DateTime today, {
    Map<String, List<DateTime>> missed = const {},
  }) {
    final start = range.start;
    final before = day(start.year, start.month, start.day - 1);
    return {
      categoryId: sampled(
        events,
        span(
          day(
            start.year,
            start.month,
            start.day - AnalyticsMetrics.lookbackDays,
          ),
          before.isAfter(today) ? today : before,
        ),
        missed: missed,
      ),
    };
  }

  /// What the sampler's lookahead hands over after a past [range]: [events]'
  /// samples from the day after its end to [today].
  Map<String, List<ReportSample>> lookaheadFor(
    String categoryId,
    List<CalendarEvent> events,
    DateRange range,
    DateTime today, {
    Map<String, List<DateTime>> missed = const {},
  }) {
    final end = range.end;
    return {
      categoryId: sampled(
        events,
        span(day(end.year, end.month, end.day + 1), today),
        missed: missed,
      ),
    };
  }

  ReportGoal goalOf(CalendarReport report, String categoryId) =>
      report.goals.singleWhere((g) => g.categoryId == categoryId);
  String periodText(ReportGoalPeriod p) =>
      '${p.start.month}-${p.start.day}..${p.end.month}-${p.end.day} '
      '${p.value}/${p.expected} ${p.state.name}';
  List<String> periodsOf(CalendarReport report, String categoryId) => [
    for (final p in goalOf(report, categoryId).periods) periodText(p),
  ];
  String dueText(ReportDueRow row) =>
      '${row.eventId} ${row.state.name} ${row.kind.name} ${row.days}';

  group('goals (J, K, §6.6)', () {
    for (final (weekStart, w0) in [
      (CalendarWeekStart.monday, day(2026, 11, 2)),
      (CalendarWeekStart.saturday, day(2026, 10, 31)),
    ]) {
      DateTime d(int n) => day(w0.year, w0.month, w0.day + n);
      final week = span(w0, d(6));
      // A far pad day keeps the category in the selection on an empty week.
      CalendarEvent on(String id, List<int> days) => ev(
        id,
        'gym',
        d(-20),
        rule: dates([d(-20), for (final n in days) d(n)]),
      );

      String atLeastOn(
        List<int> days, {
        int today = 2,
        DateRange? over,
        TargetKind kind = TargetKind.atLeast,
        List<int>? twin,
      }) {
        final report = foldFacts(
          [on('gym', days), if (twin != null) on('gym2', twin)],
          over ?? week,
          d(today),
          weekStart: weekStart,
          profiles: {
            'gym': targeted(
              CategoryKind.custom,
              perPeriod(kind, 3, TargetPeriod.week),
              measure: ReportMeasure.count,
            ),
          },
        );
        return periodsOf(report, 'gym').single;
      }

      final range = '${w0.month}-${w0.day}..${d(6).month}-${d(6).day}';
      final next = '${d(7).month}-${d(7).day}..${d(13).month}-${d(13).day}';
      final last = '${d(-7).month}-${d(-7).day}..${d(-1).month}-${d(-1).day}';

      test('at least 3 a week, each state (${weekStart.name})', () {
        // The third day of the week: expected ceil(3 × 3 / 7) = 2.
        expect(atLeastOn([0, 1, 2]), '$range 3/2 met');
        expect(atLeastOn([0, 1]), '$range 2/2 onPace');
        expect(atLeastOn([0]), '$range 1/2 behind');
        expect(atLeastOn([], today: 0), '$range 0/1 notDue');
        expect(atLeastOn([0], today: 0), '$range 1/1 onPace');
        expect(
          atLeastOn([7, 8], over: span(d(7), d(13))),
          '$next 2/0 future',
          reason: 'a future period counts what is planned in it',
        );
        expect(
          atLeastOn([-7, -6, -5], over: span(d(-7), d(-1))),
          '$last 3/3 met',
        );
        expect(
          atLeastOn([-7, -6], over: span(d(-7), d(-1))),
          '$last 2/3 missed',
        );
      });

      test('at most 3 a week, each state (${weekStart.name})', () {
        const atMost = TargetKind.atMost;
        expect(atLeastOn([0], kind: atMost), '$range 1/2 onPace');
        expect(atLeastOn([0, 1, 2], kind: atMost), '$range 3/2 behind');
        expect(
          atLeastOn([0, 1], twin: [0, 1], kind: atMost),
          '$range 4/2 over',
        );
        expect(
          atLeastOn([-7, -6, -5], over: span(d(-7), d(-1)), kind: atMost),
          '$last 3/3 met',
        );
        expect(
          atLeastOn(
            [-7, -6],
            twin: [-7, -6],
            over: span(d(-7), d(-1)),
            kind: atMost,
          ),
          '$last 4/3 over',
        );
      });
    }

    test('a budget reads the spent cents of the month', () {
      String rentOn(DateTime start, int net, DateRange month, DateTime today) {
        final report = foldFacts(
          [ev('rent', 'birthday', start).copyWith(noteId: 'n1')],
          month,
          today,
          profiles: {
            'birthday': targeted(
              CategoryKind.bill,
              const ReportTarget(
                kind: TargetKind.budget,
                value: 10000,
                period: TargetPeriod.month,
              ),
            ),
          },
          money: {'rent': net},
        );
        expect(goalOf(report, 'birthday').measure, ReportMeasure.money);
        return periodsOf(report, 'birthday').single;
      }

      final october = span(day(2026, 10, 1), day(2026, 10, 31));
      final november = span(day(2026, 11, 1), day(2026, 11, 30));
      final today = day(2026, 11, 4);
      expect(
        rentOn(day(2026, 10, 1), -8000, october, today),
        '10-1..10-31 8000/10000 met',
      );
      expect(
        rentOn(day(2026, 10, 1), -12000, october, today),
        '10-1..10-31 12000/10000 over',
      );
      expect(
        rentOn(day(2026, 11, 1), -12000, november, today),
        '11-1..11-30 12000/1334 over',
      );
      expect(
        rentOn(day(2026, 11, 1), -800, november, today),
        '11-1..11-30 800/1334 onPace',
      );
      expect(
        rentOn(day(2026, 11, 1), 5000, november, today),
        '11-1..11-30 0/1334 onPace',
        reason: 'money received spends nothing of a budget',
      );
    });

    test('a gap reads within, due in its last fifth, overdue past it', () {
      final november = span(day(2026, 11, 1), day(2026, 11, 30));
      final today = day(2026, 11, 15);
      ReportGoal gapAfter(DateTime oil, {bool missed = false}) {
        final report = foldFacts(
          [ev('oil', 'cardio', oil, tracked: missed)],
          november,
          today,
          missed: {
            if (missed) 'oil': [oil],
          },
          profiles: {'cardio': targeted(CategoryKind.maintenance, maxGap(10))},
        );
        return goalOf(report, 'cardio');
      }

      ({int? since, GapState state}) read(ReportGoal goal) =>
          (since: goal.gap!.daysSince, state: goal.gap!.state);
      expect(read(gapAfter(day(2026, 11, 10))), (
        since: 5,
        state: GapState.within,
      ));
      expect(read(gapAfter(day(2026, 11, 8))), (
        since: 7,
        state: GapState.within,
      ));
      expect(read(gapAfter(day(2026, 11, 7))), (since: 8, state: GapState.due));
      expect(read(gapAfter(day(2026, 11, 5))), (
        since: 10,
        state: GapState.due,
      ));
      expect(read(gapAfter(day(2026, 11, 4))), (
        since: 11,
        state: GapState.overdue,
      ));
      final unkept = gapAfter(day(2026, 11, 4), missed: true).gap!;
      expect(
        (unkept.daysSince, unkept.state, unkept.beyondLookback),
        (AnalyticsMetrics.lookbackDays, GapState.overdue, true),
        reason: 'it occurred with no kept day anywhere: over a year',
      );
      final goal = gapAfter(day(2026, 11, 4));
      expect(goal.periods, isEmpty);
      expect((goal.streak, goal.gap!.limit), (0, 10));
      expect(goal.measure, ReportMeasure.lastSeen);
    });

    test('periods land on their days across the DST month', () {
      final march = span(day(2026, 3, 1), day(2026, 3, 31));
      final today = day(2026, 4, 15);
      final events = [ev('gym', 'gym', day(2026, 2, 1), rule: daily)];
      List<String> weeksOf(CalendarWeekStart weekStart, TargetPeriod period) {
        final report = foldFacts(
          events,
          march,
          today,
          weekStart: weekStart,
          profiles: {
            'gym': targeted(
              CategoryKind.custom,
              perPeriod(TargetKind.atLeast, 1, period),
              measure: ReportMeasure.count,
            ),
          },
          lookback: lookbackFor('gym', events, march, today),
        );
        return periodsOf(report, 'gym');
      }

      // 29 March is the EU's spring-forward Sunday.
      expect(weeksOf(CalendarWeekStart.monday, TargetPeriod.week), [
        '2-23..3-1 7/1 met',
        '3-2..3-8 7/1 met',
        '3-9..3-15 7/1 met',
        '3-16..3-22 7/1 met',
        '3-23..3-29 7/1 met',
        '3-30..4-5 2/1 met',
      ]);
      expect(weeksOf(CalendarWeekStart.saturday, TargetPeriod.week), [
        '2-28..3-6 7/1 met',
        '3-7..3-13 7/1 met',
        '3-14..3-20 7/1 met',
        '3-21..3-27 7/1 met',
        '3-28..4-3 4/1 met',
      ]);
      expect(weeksOf(CalendarWeekStart.monday, TargetPeriod.month), [
        '3-1..3-31 31/1 met',
      ]);
      expect(weeksOf(CalendarWeekStart.monday, TargetPeriod.day).take(2), [
        '3-1..3-1 1/1 met',
        '3-2..3-2 1/1 met',
      ]);
    });

    test('a streak counts the closed weeks met, back from the last', () {
      final thisWeek = span(day(2026, 11, 2), day(2026, 11, 8));
      final today = day(2026, 11, 4);
      final events = [
        ev('gym', 'gym', day(2026, 10, 5), rule: daily, tracked: true),
      ];
      ReportGoal streakWith(List<DateTime> missed) {
        final report = foldFacts(
          events,
          thisWeek,
          today,
          profiles: {
            'gym': targeted(
              CategoryKind.workout,
              perPeriod(TargetKind.atLeast, 3, TargetPeriod.week),
            ),
          },
          lookback: lookbackFor(
            'gym',
            events,
            thisWeek,
            today,
            missed: {'gym': missed},
          ),
        );
        return goalOf(report, 'gym');
      }

      List<DateTime> days(DateTime from, int count) => [
        for (var i = 0; i < count; i++)
          day(from.year, from.month, from.day + i),
      ];

      final kept = streakWith(const []);
      expect(kept.measure, ReportMeasure.attendance);
      expect(
        kept.streak,
        4,
        reason: 'the four weeks since the first event, none before it',
      );
      expect(
        [for (final p in kept.periods) periodText(p)],
        ['11-2..11-8 3/2 met'],
      );
      expect(
        streakWith(days(day(2026, 10, 26), 5)).streak,
        0,
        reason: 'the last closed week kept two',
      );
      expect(streakWith(days(day(2026, 10, 12), 5)).streak, 2);
      expect(
        foldFacts(
          events,
          thisWeek,
          today,
          profiles: {
            'gym': targeted(
              CategoryKind.workout,
              perPeriod(TargetKind.atLeast, 3, TargetPeriod.week),
            ),
          },
        ).goals.single.streak,
        0,
        reason: 'without a lookback no closed week was kept',
      );
    });

    test('a past span\'s last week past its end is valued from the '
        'lookahead and judged for the streak', () {
      final october = span(day(2026, 10, 1), day(2026, 10, 31));
      final today = day(2026, 11, 20);
      final events = [ev('gym', 'gym', day(2026, 9, 1), rule: daily)];
      final report = foldFacts(
        events,
        october,
        today,
        profiles: {
          'gym': targeted(
            CategoryKind.custom,
            perPeriod(TargetKind.atLeast, 3, TargetPeriod.week),
            measure: ReportMeasure.count,
          ),
        },
        lookback: lookbackFor('gym', events, october, today),
        lookahead: lookaheadFor('gym', events, october, today),
      );
      expect(periodsOf(report, 'gym').last, '10-26..11-1 7/3 met');
      // From the week of 31 August to that of 26 October.
      expect(goalOf(report, 'gym').streak, 9);
    });

    test('a monthly target seen from a week is valued over the month', () {
      final week = span(day(2026, 11, 9), day(2026, 11, 15));
      final today = day(2026, 11, 11);
      final events = [ev('gym', 'gym', day(2026, 11, 1), rule: daily)];
      final profiles = {
        'gym': targeted(
          CategoryKind.custom,
          perPeriod(TargetKind.atLeast, 10, TargetPeriod.month),
          measure: ReportMeasure.count,
        ),
      };
      final whole = foldFacts(
        events,
        week,
        today,
        profiles: profiles,
        lookback: lookbackFor('gym', events, week, today),
      );
      expect(periodsOf(whole, 'gym'), ['11-1..11-30 11/4 met']);
      final spanOnly = foldFacts(events, week, today, profiles: profiles);
      expect(periodsOf(spanOnly, 'gym'), ['11-1..11-30 3/4 behind']);
    });

    test('each primary values its period in its own unit', () {
      final week = span(day(2026, 11, 2), day(2026, 11, 8));
      final today = day(2026, 11, 4);
      final events = [
        ev('desk', 'cardio', day(2026, 11, 2), rule: daily, time: at(9, 0, 60)),
        ev(
          'calls',
          'cardio',
          day(2026, 11, 3),
          description: '- [x] a\n- [x] b\n- [ ] c',
        ),
      ];
      int valueOf(ReportMeasure measure) => goalOf(
        foldFacts(
          events,
          week,
          today,
          profiles: {
            'cardio': targeted(
              CategoryKind.work,
              perPeriod(TargetKind.atMost, 600, TargetPeriod.week),
              measure: measure,
            ),
          },
        ),
        'cardio',
      ).periods.single.value;

      expect(valueOf(ReportMeasure.hours), 180);
      expect(valueOf(ReportMeasure.count), 4);
      expect(valueOf(ReportMeasure.events), 2);
      expect(valueOf(ReportMeasure.tasks), 2);
      expect(valueOf(ReportMeasure.timing), 4, reason: 'counts kept days');
    });

    test('goals follow the catalogue order, one per targeted category', () {
      final week = span(day(2026, 11, 2), day(2026, 11, 8));
      final report = foldFacts(
        [
          ev('a', 'friends', day(2026, 11, 2)),
          ev('b', 'gym', day(2026, 11, 2)),
          ev('c', 'cardio', day(2026, 11, 2)),
        ],
        week,
        day(2026, 11, 4),
        profiles: {
          'friends': targeted(CategoryKind.social, maxGap(14)),
          'gym': targeted(
            CategoryKind.custom,
            perPeriod(TargetKind.atLeast, 1, TargetPeriod.week),
          ),
          'cardio': kindOf(CategoryKind.workout),
        },
      );
      expect([for (final g in report.goals) g.categoryId], ['gym', 'friends']);
    });
  });

  group('due soon (O, §6.8)', () {
    final november = span(day(2026, 11, 1), day(2026, 11, 30));
    final today = day(2026, 11, 15);
    final profiles = {
      'cardio': targeted(CategoryKind.maintenance, maxGap(10)),
      'rest': targeted(CategoryKind.maintenance, maxGap(10)),
      'holiday': kindOf(CategoryKind.expiry),
      'birthday': kindOf(CategoryKind.bill),
      'competition': kindOf(CategoryKind.deadline),
    };
    List<CalendarEvent> fixture() => [
      ev('oil', 'cardio', day(2026, 10, 20)),
      ev('floss', 'rest', day(2026, 11, 6)),
      ev('passport', 'holiday', day(2026, 12, 27)),
      ev('visa', 'holiday', day(2026, 11, 20)),
      ev('licence', 'holiday', day(2027, 1, 30)),
      ev('card', 'holiday', day(2026, 11, 10), tracked: true),
      ev('rent', 'birthday', day(2026, 11, 1), tracked: true),
      ev('tax', 'competition', day(2026, 11, 12), tracked: true),
    ];
    final missed = {
      'card': [day(2026, 11, 10)],
      'rent': [day(2026, 11, 1)],
      'tax': [day(2026, 11, 12)],
    };
    CalendarReport dueOf(List<CalendarEvent> events) => foldFacts(
      events,
      november,
      today,
      missed: missed,
      profiles: profiles,
      lastSeenBefore: {'cardio': day(2026, 10, 20)},
      lookback: {
        'cardio': [ReportSample(eventId: 'oil', day: day(2026, 10, 20))],
      },
    );

    test('overdue, due, unmarked, upcoming, each by days, every row', () {
      final report = dueOf(fixture());
      expect(
        [for (final r in report.dueSoon) dueText(r)],
        [
          'oil overdue gap 16',
          'card overdue expiry 5',
          'floss due gap 1',
          'tax unmarked unmarked 3',
          'rent unmarked unmarked 14',
          'visa upcoming expiry 5',
          'passport upcoming expiry 42',
        ],
        reason: 'uncapped: the page shows AnalyticsMetrics.dueSoonRows',
      );
      expect(report.dueSoon.length, greaterThan(AnalyticsMetrics.dueSoonRows));
      final oil = report.dueSoon[0];
      expect((oil.categoryId, oil.day), ('cardio', day(2026, 10, 30)));
      expect(report.dueSoon[2].day, day(2026, 11, 16));
    });

    test('an Expiry past the span inside 60 days still reads, one beyond '
        'it never', () {
      final report = dueOf([
        for (final e in fixture())
          if (e.id != 'card' && e.id != 'tax') e,
      ]);
      expect(
        [for (final r in report.dueSoon) dueText(r)],
        [
          'oil overdue gap 16',
          'floss due gap 1',
          'rent unmarked unmarked 14',
          'visa upcoming expiry 5',
          'passport upcoming expiry 42',
        ],
      );
    });

    test('a plan lists only the span\'s Expiries and Bills, as upcoming', () {
      final december = span(day(2026, 12, 1), day(2026, 12, 31));
      final report = foldFacts(
        [
          ev('oil', 'cardio', day(2026, 10, 20)),
          ev('passport', 'holiday', day(2026, 12, 27)),
          ev('rent', 'birthday', day(2026, 12, 1), tracked: true),
          ev('tax', 'competition', day(2026, 12, 5), tracked: true),
        ],
        december,
        today,
        profiles: profiles,
        lastSeenBefore: {'cardio': day(2026, 10, 20)},
      );
      expect(
        [for (final r in report.dueSoon) dueText(r)],
        ['rent upcoming upcoming 16', 'passport upcoming expiry 42'],
      );
      expect(
        goalOf(report, 'cardio').gap!.state,
        GapState.overdue,
        reason: 'the goal still reads; only the card leaves it out',
      );
    });
  });

  group('balance and when (M, T, §6.10)', () {
    final week = span(day(2026, 11, 2), day(2026, 11, 8));
    final later = day(2026, 11, 20);

    test('balance sums minutes per area, Sleep out, counts-as in', () {
      final report = foldFacts(
        [
          ev(
            'gym',
            'gym',
            day(2026, 11, 2),
            rule: weekly({1, 3}),
            time: at(18, 0, 60),
          ),
          ev(
            'night',
            'rest',
            day(2026, 11, 2),
            rule: daily,
            time: at(23, 0, 480),
          ),
          ev('stretch', 'mobility', day(2026, 11, 3)),
          ev('desk', 'cardio', day(2026, 11, 4), time: at(9, 0, 120)),
        ],
        week,
        later,
        profiles: {
          'gym': kindOf(CategoryKind.workout),
          'rest': kindOf(CategoryKind.sleep),
          'mobility': kindOf(CategoryKind.custom, nominal: 30),
          'cardio': kindOf(CategoryKind.work),
        },
      );
      expect(report.balance, {
        LifeArea.health: 120,
        LifeArea.work: 120,
        LifeArea.other: 30,
      });
      expect(report.balance.keys, [
        LifeArea.health,
        LifeArea.work,
        LifeArea.other,
      ]);
    });

    test('balance is empty with no hours', () {
      final report = foldFacts(
        [ev('walk', 'gym', day(2026, 11, 3))],
        week,
        later,
      );
      expect(report.balance, isEmpty);
    });

    test('when fills each hour an occurrence covers, past midnight onto the '
        'next row', () {
      final events = [
        ev('gym', 'gym', day(2026, 11, 2), time: at(18, 30, 60)),
        ev('late', 'gym', day(2026, 11, 8), time: at(23, 30, 90)),
        ev('pill', 'gym', day(2026, 11, 4), time: at(8, 0)),
      ];
      final monday = foldFacts(events, week, later).when!;
      expect(monday.cells.length, ReportWhen.cellCount);
      expect(
        (monday.cells[18], monday.cells[19], monday.cells[6 * 24 + 23]),
        (30, 30, 30),
      );
      expect(monday.cells[0], 60, reason: 'Sunday night wraps to Monday');
      expect(monday.cells.fold(0, (a, b) => a + b), 150);
      expect(
        monday.timedDays,
        2,
        reason: 'a time with no duration covers none',
      );
      expect((monday.busiestWeekday, monday.busiestHour), (null, null));

      final saturday = foldFacts(
        events,
        week,
        later,
        weekStart: CalendarWeekStart.saturday,
      ).when!;
      expect(
        (
          saturday.cells[2 * 24 + 18],
          saturday.cells[24 + 23],
          saturday.cells[2 * 24],
        ),
        (30, 30, 60),
        reason: 'rows run from the week start',
      );
    });

    test('when names the busiest row and hour from ten timed days', () {
      final events = [
        ev('gym', 'gym', day(2026, 11, 2), rule: daily, time: at(18, 30, 60)),
        ev('run', 'gym', day(2026, 11, 5), time: at(7, 0, 120)),
      ];
      final report = foldFacts(
        events,
        span(day(2026, 11, 2), day(2026, 11, 15)),
        later,
      ).when!;
      expect(report.timedDays, 15);
      expect((report.busiestWeekday, report.busiestHour), (3, 18));

      final short = foldFacts(
        [events.first],
        span(day(2026, 11, 2), day(2026, 11, 10)),
        later,
      ).when!;
      expect(short.timedDays, 9);
      expect((short.busiestWeekday, short.busiestHour), (null, null));
    });

    test('a missed day fills no cell', () {
      final report = foldFacts(
        [ev('gym', 'gym', day(2026, 11, 2), tracked: true, time: at(6, 0, 60))],
        week,
        later,
        missed: {
          'gym': [day(2026, 11, 2)],
        },
      ).when!;
      expect((report.timedDays, report.cells[6]), (0, 0));
    });
  });

  group('the unprofiled golden (§13)', () {
    test('no profile, no goal and no Due soon row; When and Balance exist', () {
      final report = fold(p4Events(), p4Span, p4Today, missed: p4Missed);
      expect(report.goals, isEmpty);
      expect(report.dueSoon, isEmpty);
      expect(report.insights, isEmpty);
      expect(report.when, isNotNull);
      expect(report.balance.keys, everyElement(LifeArea.other));
      expect(
        report.balance[LifeArea.other],
        report.measures.values.fold(0, (n, m) => n + m.minutes),
      );
    });
  });

  // The S2a fix pass: the days after a past span, a gap beyond the
  // lookback, the Due soon order, money from the ledger, today's next day,
  // and the tags walk.
  group('the fix pass', () {
    final october = span(day(2026, 10, 1), day(2026, 10, 31));
    final november = span(day(2026, 11, 1), day(2026, 11, 30));
    final novemberToday = day(2026, 11, 15);

    test('a Maintenance kept after a past span reads its last day from the '
        'lookahead', () {
      final today = day(2026, 11, 20);
      final events = [
        ev('oil', 'cardio', day(2026, 10, 1)),
        ev('tyres', 'cardio', day(2026, 11, 15)),
      ];
      final profiles = {
        'cardio': targeted(CategoryKind.maintenance, maxGap(10)),
      };
      final report = foldFacts(
        events,
        october,
        today,
        profiles: profiles,
        lookahead: lookaheadFor('cardio', events, october, today),
      );
      final cardio = report.measures['cardio']!;
      expect((cardio.lastSeenDay, cardio.lastSeenDays), (day(2026, 11, 15), 5));
      final gap = goalOf(report, 'cardio').gap!;
      expect((gap.daysSince, gap.state), (5, GapState.within));
      expect(report.dueSoon, isEmpty);

      final blind = foldFacts(events, october, today, profiles: profiles);
      expect(
        blind.measures['cardio']!.lastSeenDays,
        50,
        reason: 'without the lookahead the month is all it knows',
      );
    });

    test('a past span\'s trailing week is exact from the lookahead', () {
      final today = day(2026, 11, 20);
      final events = [ev('gym', 'gym', day(2026, 9, 1), rule: daily)];
      List<String> weeksWith({required bool lookahead}) => periodsOf(
        foldFacts(
          events,
          october,
          today,
          profiles: {
            'gym': targeted(
              CategoryKind.custom,
              perPeriod(TargetKind.atLeast, 7, TargetPeriod.week),
              measure: ReportMeasure.count,
            ),
          },
          lookahead: lookahead
              ? lookaheadFor('gym', events, october, today)
              : const {},
        ),
        'gym',
      );
      expect(weeksWith(lookahead: true).last, '10-26..11-1 7/7 met');
      expect(weeksWith(lookahead: false).last, '10-26..11-1 6/7 missed');
    });

    test('a monthly target seen from last week is current, paced against '
        'today', () {
      final lastWeek = span(day(2026, 11, 9), day(2026, 11, 15));
      final today = day(2026, 11, 20);
      final events = [ev('gym', 'gym', day(2026, 11, 1), rule: daily)];
      final report = foldFacts(
        events,
        lastWeek,
        today,
        profiles: {
          'gym': targeted(
            CategoryKind.custom,
            perPeriod(TargetKind.atLeast, 30, TargetPeriod.month),
            measure: ReportMeasure.count,
          ),
        },
        lookback: lookbackFor('gym', events, lastWeek, today),
        lookahead: lookaheadFor('gym', events, lastWeek, today),
      );
      // 1–20 November kept; expected ceil(30 × 20 / 30).
      expect(periodsOf(report, 'gym'), ['11-1..11-30 20/20 onPace']);
    });

    test('a yearly target on a past month reads the year to today', () {
      final today = day(2026, 11, 20);
      final events = [ev('gym', 'gym', day(2026, 1, 1), rule: daily)];
      final report = foldFacts(
        events,
        october,
        today,
        profiles: {
          'gym': targeted(
            CategoryKind.custom,
            perPeriod(TargetKind.atLeast, 365, TargetPeriod.year),
            measure: ReportMeasure.count,
          ),
        },
        lookback: lookbackFor('gym', events, october, today),
        lookahead: lookaheadFor('gym', events, october, today),
      );
      // 273 days to September, October's 31, 20 of November; 324 of 365
      // elapsed, so expected 324.
      expect(periodsOf(report, 'gym'), ['1-1..12-31 324/324 onPace']);
      expect(goalOf(report, 'gym').streak, 0, reason: 'no closed year');
    });

    test('a gap with nothing up to today reads no gap and no row', () {
      final report = foldFacts(
        [ev('oil', 'cardio', day(2026, 12, 20))],
        november,
        novemberToday,
        profiles: {'cardio': targeted(CategoryKind.maintenance, maxGap(10))},
      );
      expect(goalOf(report, 'cardio').gap, isNull);
      expect(report.dueSoon, isEmpty);
    });

    test('a gap that occurred with no kept day in a year is over a year', () {
      final events = [
        ev('service', 'cardio', day(2025, 11, 1), rule: yearly, tracked: true),
      ];
      final missed = {
        'service': [day(2025, 11, 1), day(2026, 11, 1)],
      };
      ReportGoal gapOf(int limit) => goalOf(
        foldFacts(
          events,
          november,
          novemberToday,
          missed: missed,
          profiles: {
            'cardio': targeted(CategoryKind.maintenance, maxGap(limit)),
          },
          lookback: lookbackFor(
            'cardio',
            events,
            november,
            novemberToday,
            missed: missed,
          ),
        ),
        'cardio',
      );
      final overdue = gapOf(365).gap!;
      expect(
        (overdue.daysSince, overdue.state, overdue.beyondLookback),
        (AnalyticsMetrics.lookbackDays, GapState.overdue, true),
      );
      final report = foldFacts(
        events,
        november,
        novemberToday,
        missed: missed,
        profiles: {'cardio': targeted(CategoryKind.maintenance, maxGap(365))},
      );
      final row = report.dueSoon.single;
      expect(
        (dueText(row), row.beyondLookback),
        ('service overdue gap 1', true),
        reason: 'lookbackDays − limit',
      );
      // A limit past the lookback is never overdue: the floor is a year.
      final due = gapOf(400).gap!;
      expect((due.state, due.beyondLookback), (GapState.due, true));
    });

    test('Due soon: overdue the longest past first, the rest the soonest', () {
      final today = day(2026, 11, 15);
      final report = foldFacts(
        [
          ev('a', 'holiday', day(2026, 11, 12), tracked: true),
          ev('b', 'holiday', day(2026, 11, 2), tracked: true),
          ev('c', 'holiday', day(2026, 11, 30)),
          ev('d', 'holiday', day(2026, 11, 20)),
        ],
        november,
        today,
        missed: {
          'a': [day(2026, 11, 12)],
          'b': [day(2026, 11, 2)],
        },
        profiles: {'holiday': kindOf(CategoryKind.expiry)},
      );
      expect(
        [for (final r in report.dueSoon) dueText(r)],
        [
          'b overdue expiry 13',
          'a overdue expiry 3',
          'd upcoming expiry 5',
          'c upcoming expiry 15',
        ],
      );
    });

    test('money is a measure only where the ledger holds the note', () {
      ReportMeasures billOf(Map<String, int> money) => foldFacts(
        [ev('rent', 'other', day(2026, 11, 1)).copyWith(noteId: 'n1')],
        november,
        novemberToday,
        profiles: {'other': kindOf(CategoryKind.bill)},
        money: money,
      ).measures['other']!;
      final off = billOf(const {});
      expect(
        (off.hasMoney, off.primary, off.fallbackApplied),
        (false, ReportMeasure.count, true),
        reason: 'money off: a linked note alone shows no Money',
      );
      final on = billOf({'rent': -1200});
      expect(
        (on.hasMoney, on.primary, on.spentCents),
        (true, ReportMeasure.money, 1200),
      );
      expect(billOf({'rent': 0}).hasMoney, isTrue, reason: 'cached, net 0');
    });

    test('an Expiry due today is 0 days away', () {
      final report = foldFacts(
        [ev('visa', 'holiday', novemberToday, tracked: true)],
        november,
        novemberToday,
        pending: {
          'visa': [novemberToday],
        },
        profiles: {'holiday': kindOf(CategoryKind.expiry)},
      );
      final holiday = report.measures['holiday']!;
      expect((holiday.nextDay, holiday.daysUntil), (novemberToday, 0));
      expect(
        [for (final r in report.dueSoon) dueText(r)],
        ['visa upcoming expiry 0'],
      );
    });

    test('an untagged text never reaches the cache or a tally', () {
      expect(extractTags('no tag here'), same(const <String>[]));
      final events = [
        ev('gym', 'gym', day(2026, 11, 1), rule: daily, perDay: true),
      ];
      final plain = foldFacts(events, november, novemberToday);
      final texted = foldFacts(
        events,
        november,
        novemberToday,
        overrides: {
          'gym': {day(2026, 11, 3): 'legs, no tag'},
        },
      );
      expect(plain.tags, isEmpty);
      expect(texted.tags, isEmpty);
      expect(texted.measures, plain.measures);
    });

    test('a day\'s own tags join the event\'s once per key', () {
      final tags = foldFacts(
        [
          ev(
            'walk',
            'mobility',
            day(2026, 11, 1),
            rule: daily,
            perDay: true,
          ).copyWith(title: 'Walk #Ana'),
        ],
        span(day(2026, 11, 1), day(2026, 11, 3)),
        novemberToday,
        overrides: {
          'walk': {day(2026, 11, 2): 'with #ana and #park'},
        },
      ).tags;
      expect(
        [for (final t in tags) '${t.label} ${t.count}'],
        ['Ana 3', 'park 1'],
      );
    });

    test('a code span\'s # is no tag, as the grammar binds it first', () {
      expect(extractTags('see `#foo` and #bar'), ['bar']);
      expect(extractTags('``#a ` #b`` #c'), ['c']);
      expect(extractTags('an open ` #foo'), ['foo'], reason: 'unclosed');
    });

    test('a bare URL\'s # is no tag, as the grammar binds it first', () {
      expect(extractTags('https://a.b/#frag and #bar'), ['bar']);
      expect(extractTags('(www.a.b/#y) #z'), ['z']);
      expect(extractTags('#http'), ['http']);
    });
  });

  // The insight library (S2b-i): each rule fires on its fixture with its
  // slots, and stays quiet just under its threshold.
  group('insights (L, §6.7)', () {
    final week = span(day(2026, 11, 2), day(2026, 11, 8));
    final november = span(day(2026, 11, 1), day(2026, 11, 30));
    final mid = day(2026, 11, 15);
    final later = day(2026, 11, 20);
    List<ReportInsight> fired(CalendarReport r, InsightRule rule) => [
      for (final i in r.insights)
        if (i.rule == rule) i,
    ];
    ReportInsight one(CalendarReport r, InsightRule rule) =>
        fired(r, rule).single;
    ReportTarget perWeek(TargetKind kind, int value) =>
        perPeriod(kind, value, TargetPeriod.week);

    test('G1: an at-least goal behind past half its period', () {
      CalendarReport on(DateTime today) => foldFacts(
        [ev('lift', 'gym', day(2026, 11, 2))],
        week,
        today,
        profiles: {
          'gym': targeted(CategoryKind.custom, perWeek(TargetKind.atLeast, 3)),
        },
      );
      final g1 = one(on(day(2026, 11, 5)), InsightRule.g1);
      expect(
        (g1.severity, g1.categoryId, g1.target, g1.n1, g1.n2, g1.n3),
        (3, 'gym', InsightTarget.categoryGroup, 1, 3, 2),
      );
      expect((g1.day, g1.dayEnd), (day(2026, 11, 2), day(2026, 11, 8)));
      expect(
        fired(on(day(2026, 11, 4)), InsightRule.g1),
        isEmpty,
        reason: 'three days of seven is not past half',
      );
    });

    test('G2: an at-most goal over in its current period', () {
      CalendarReport on(int kept) => foldFacts(
        [
          ev(
            'desk',
            'gym',
            day(2026, 11, 2),
            rule: daily,
            end: day(2026, 11, 1 + kept),
          ),
        ],
        week,
        day(2026, 11, 5),
        profiles: {
          'gym': targeted(CategoryKind.custom, perWeek(TargetKind.atMost, 2)),
        },
      );
      final g2 = one(on(3), InsightRule.g2);
      expect((g2.severity, g2.n1, g2.n2, g2.n3), (2, 3, 2, 1));
      expect(fired(on(2), InsightRule.g2), isEmpty, reason: 'at the cap');
    });

    test('G3: a goal met before its period ends', () {
      CalendarReport on(int kept) => foldFacts(
        [
          ev(
            'run',
            'gym',
            day(2026, 11, 2),
            rule: daily,
            end: day(2026, 11, 1 + kept),
          ),
        ],
        week,
        day(2026, 11, 5),
        profiles: {
          'gym': targeted(CategoryKind.custom, perWeek(TargetKind.atLeast, 2)),
        },
      );
      final g3 = one(on(2), InsightRule.g3);
      expect((g3.severity, g3.n1, g3.n2), (1, 2, 2));
      expect(fired(on(1), InsightRule.g3), isEmpty);
    });

    test('G4: a streak at a multiple of four', () {
      final today = day(2026, 11, 5);
      CalendarReport from(DateTime first) {
        final events = [
          ev('lift', 'gym', first, rule: weekly({1})),
        ];
        return foldFacts(
          events,
          week,
          today,
          profiles: {
            'gym': targeted(
              CategoryKind.custom,
              perWeek(TargetKind.atLeast, 1),
            ),
          },
          lookback: lookbackFor('gym', events, week, today),
        );
      }

      final four = from(day(2026, 10, 5));
      expect(goalOf(four, 'gym').streak, 4);
      final g4 = one(four, InsightRule.g4);
      expect((g4.severity, g4.n1, g4.alternate), (2, 4, false));
      expect(fired(from(day(2026, 10, 12)), InsightRule.g4), isEmpty);
    });

    test('G4: a streak the last closed period broke', () {
      final today = day(2026, 11, 5);
      CalendarReport on(List<DateTime> days) {
        final events = [ev('lift', 'gym', days.first, rule: dates(days))];
        return foldFacts(
          events,
          week,
          today,
          profiles: {
            'gym': targeted(
              CategoryKind.custom,
              perWeek(TargetKind.atLeast, 1),
            ),
          },
          lookback: lookbackFor('gym', events, week, today),
        );
      }

      final broke = on([
        day(2026, 10, 5),
        day(2026, 10, 12),
        day(2026, 10, 19),
        day(2026, 11, 2),
      ]);
      expect(
        (goalOf(broke, 'gym').streak, goalOf(broke, 'gym').brokenStreak),
        (0, 3),
      );
      final g4 = one(broke, InsightRule.g4);
      expect((g4.severity, g4.n1, g4.alternate), (1, 3, true));
      final long = on([day(2026, 10, 5), day(2026, 11, 2)]);
      expect(
        goalOf(long, 'gym').brokenStreak,
        0,
        reason: 'the streak broke three weeks before the last closed one',
      );
      expect(fired(long, InsightRule.g4), isEmpty);
    });

    final year = span(day(2026, 1, 1), day(2026, 12, 31));
    CalendarReport leaveOf(int days, DateTime today) => foldFacts(
      [
        ev(
          'summer',
          'holiday',
          day(2026, 7, 1),
          rule: daily,
          end: day(2026, 7, days),
        ),
      ],
      year,
      today,
      profiles: {
        'holiday': targeted(
          CategoryKind.leave,
          perPeriod(TargetKind.atMost, 25, TargetPeriod.year),
        ),
      },
    );

    test('G5: a Leave allowance nearly spent with a quarter of the year '
        'ahead', () {
      final g5 = one(leaveOf(21, day(2026, 8, 15)), InsightRule.g5);
      expect(
        (g5.severity, g5.n1, g5.n2, g5.n3, g5.alternate),
        (1, 4, 25, 4, false),
      );
      expect((g5.day, g5.dayEnd), (year.start, year.end));
      expect(
        fired(leaveOf(19, day(2026, 8, 15)), InsightRule.g5),
        isEmpty,
        reason: 'six of 25 is over a fifth',
      );
    });

    test('G5: Leave days unused with a month left', () {
      final g5 = one(leaveOf(20, day(2026, 12, 5)), InsightRule.g5);
      expect((g5.n1, g5.n2, g5.n3, g5.alternate), (5, 25, 26, true));
      expect(
        fired(leaveOf(20, day(2026, 11, 30)), InsightRule.g5),
        isEmpty,
        reason: '31 days left',
      );
    });

    test('G5: both boundaries are strict, one step apart', () {
      expect(
        fired(leaveOf(20, day(2026, 8, 15)), InsightRule.g5),
        isEmpty,
        reason: 'five of 25 is a fifth, not under it',
      );
      expect(one(leaveOf(21, day(2026, 8, 15)), InsightRule.g5).n1, 4);
      expect(
        fired(leaveOf(20, day(2026, 12, 1)), InsightRule.g5),
        isEmpty,
        reason: '30 days left is a month, not under it',
      );
      final g5 = one(leaveOf(20, day(2026, 12, 2)), InsightRule.g5);
      expect((g5.n1, g5.n3, g5.alternate), (5, 29, true));
    });

    CalendarReport gapOf(DateTime kept) => foldFacts(
      [ev('oil', 'cardio', kept)],
      november,
      mid,
      profiles: {'cardio': targeted(CategoryKind.maintenance, maxGap(10))},
    );

    test('D1: a gap target overdue', () {
      final d1 = one(gapOf(day(2026, 11, 1)), InsightRule.d1);
      expect(
        (d1.severity, d1.target, d1.n1, d1.n2),
        (3, InsightTarget.dueSoon, 14, 10),
      );
      expect(
        fired(gapOf(day(2026, 11, 5)), InsightRule.d1),
        isEmpty,
        reason: 'ten days is the limit itself',
      );
    });

    test('D2: a gap target due', () {
      final d2 = one(gapOf(day(2026, 11, 6)), InsightRule.d2);
      expect((d2.severity, d2.n1, d2.n2), (2, 1, 10));
      expect(fired(gapOf(day(2026, 11, 8)), InsightRule.d2), isEmpty);
    });

    test('D3: an Expiry inside sixty days', () {
      CalendarReport on(DateTime expires) => foldFacts(
        [ev('visa', 'holiday', expires)],
        span(day(2026, 11, 1), day(2027, 1, 31)),
        mid,
        profiles: {'holiday': kindOf(CategoryKind.expiry)},
      );
      final d3 = one(on(day(2027, 1, 14)), InsightRule.d3);
      expect(
        (d3.severity, d3.n1, d3.day, d3.alternate, d3.target),
        (3, 60, day(2027, 1, 14), false, InsightTarget.dueSoon),
      );
      expect(fired(on(day(2027, 1, 15)), InsightRule.d3), isEmpty);
    });

    test('D3: an Expiry passed unmarked', () {
      CalendarReport on({required bool missed}) => foldFacts(
        [ev('card', 'holiday', day(2026, 11, 10), tracked: true)],
        november,
        mid,
        missed: {
          if (missed) 'card': [day(2026, 11, 10)],
        },
        profiles: {'holiday': kindOf(CategoryKind.expiry)},
      );
      final d3 = one(on(missed: true), InsightRule.d3);
      expect(
        (d3.severity, d3.eventId, d3.day, d3.n1, d3.alternate),
        (2, 'card', day(2026, 11, 10), 5, true),
      );
      expect(fired(on(missed: false), InsightRule.d3), isEmpty);
    });

    test('D3: reads the Due soon rows — a one-off past the span\'s end', () {
      CalendarReport on(List<CalendarEvent> events) => foldFacts(
        events,
        november,
        mid,
        profiles: {'holiday': kindOf(CategoryKind.expiry)},
      );
      final passport = ev('passport', 'holiday', day(2026, 12, 10));
      final report = on([passport]);
      expect(report.dueSoon.map(dueText), ['passport upcoming expiry 25']);
      final d3 = one(report, InsightRule.d3);
      expect(
        (d3.severity, d3.eventId, d3.day, d3.n1, d3.alternate),
        (3, 'passport', day(2026, 12, 10), 25, false),
      );
      final two = on([passport, ev('id', 'holiday', day(2026, 12, 20))]);
      expect(
        [
          for (final i in fired(two, InsightRule.d3))
            (i.categoryId, i.eventId, i.n1),
        ],
        [('holiday', 'passport', 25), ('holiday', 'id', 35)],
        reason: 'one insight per document, not per category',
      );
    });

    test('D4: a Bill day passed unmarked', () {
      CalendarReport on({required bool missed}) => foldFacts(
        [ev('rent', 'birthday', day(2026, 11, 1), tracked: true)],
        november,
        mid,
        missed: {
          if (missed) 'rent': [day(2026, 11, 1)],
        },
        profiles: {'birthday': kindOf(CategoryKind.bill)},
      );
      final d4 = one(on(missed: true), InsightRule.d4);
      expect(
        (d4.severity, d4.eventId, d4.day, d4.n1, d4.n2, d4.target),
        (3, 'rent', day(2026, 11, 1), 1, 14, InsightTarget.dueSoon),
      );
      expect(fired(on(missed: false), InsightRule.d4), isEmpty);
    });

    test('D4: once per event — the latest unmarked day and the count', () {
      final report = foldFacts(
        [
          ev(
            'rent',
            'birthday',
            day(2026, 1, 1),
            rule: const MonthlyRecurrence(),
            tracked: true,
          ),
        ],
        year,
        mid,
        missed: {
          'rent': [day(2026, 8, 1), day(2026, 9, 1), day(2026, 10, 1)],
        },
        profiles: {'birthday': kindOf(CategoryKind.bill)},
      );
      expect(
        report.dueSoon.where((r) => r.state == ReportDueState.unmarked),
        hasLength(3),
        reason: 'the card still lists each day',
      );
      final d4 = one(report, InsightRule.d4);
      expect(
        (d4.eventId, d4.day, d4.n1, d4.n2),
        ('rent', day(2026, 10, 1), 3, 45),
      );
    });

    test('D5: a regular Episode expected within a week', () {
      final events = [
        ev('m1', 'measurement', day(2026, 10, 6)),
        ev(
          'm2',
          'measurement',
          day(2026, 10, 16),
          rule: daily,
          end: day(2026, 10, 17),
        ),
        ev('m3', 'measurement', day(2026, 10, 26)),
        ev('m4', 'measurement', day(2026, 11, 5)),
      ];
      CalendarReport on(DateTime today) => foldFacts(
        events,
        span(day(2026, 10, 1), day(2026, 11, 30)),
        today,
        profiles: {'measurement': kindOf(CategoryKind.episode)},
      );
      final report = on(day(2026, 11, 8));
      final m = report.measures['measurement']!;
      expect(
        (m.episodes, m.lastEpisodeDay, m.episodeGapMean, m.episodeGapCv),
        (4, day(2026, 11, 5), 10.0, 0.0),
        reason: 'the 16–17 run is one episode',
      );
      final d5 = one(report, InsightRule.d5);
      expect(
        (d5.severity, d5.day, d5.n1, d5.n2, d5.n3, d5.target),
        (1, day(2026, 11, 15), 4, 10, 7, InsightTarget.categoryGroup),
      );
      expect(
        fired(on(day(2026, 11, 7)), InsightRule.d5),
        isEmpty,
        reason: 'eight days out',
      );
    });

    test('D5: an Episode lookback joins the span', () {
      final events = [
        ev('m1', 'measurement', day(2026, 10, 6)),
        ev('m2', 'measurement', day(2026, 10, 16)),
        ev('m3', 'measurement', day(2026, 10, 26)),
        ev('m4', 'measurement', day(2026, 11, 5)),
      ];
      final today = day(2026, 11, 8);
      final report = foldFacts(
        events,
        november,
        today,
        profiles: {'measurement': targeted(CategoryKind.episode, maxGap(30))},
        lookback: lookbackFor('measurement', events, november, today),
      );
      expect(report.measures['measurement']!.episodes, 4);
      expect(one(report, InsightRule.d5).day, day(2026, 11, 15));
    });

    test('D5: overlapping events join one episode', () {
      final report = foldFacts(
        [
          ev(
            'a',
            'measurement',
            day(2026, 10, 6),
            rule: daily,
            end: day(2026, 10, 8),
          ),
          ev('b', 'measurement', day(2026, 10, 7)),
          ev('c', 'measurement', day(2026, 10, 16)),
          ev('d', 'measurement', day(2026, 10, 26)),
        ],
        span(day(2026, 10, 1), day(2026, 10, 31)),
        day(2026, 10, 30),
        profiles: {'measurement': kindOf(CategoryKind.episode)},
      );
      final m = report.measures['measurement']!;
      expect(
        (m.episodes, m.lastEpisodeDay, m.episodeGapMean, m.episodeGapCv),
        (3, day(2026, 10, 26), 10.0, 0.0),
        reason: 'a 6–8 and b on the 7th are one run',
      );
      final d5 = one(report, InsightRule.d5);
      expect((d5.day, d5.n1, d5.n2, d5.n3), (day(2026, 11, 5), 3, 10, 6));
    });

    test('P1: a routine\'s weekdays fifty points apart', () {
      final fridays = [day(2026, 10, 9), day(2026, 10, 16)];
      CalendarReport on(int missed) => foldFacts(
        [
          ev(
            'gym',
            'gym',
            day(2026, 10, 5),
            rule: weekly({2, 5}),
            tracked: true,
          ),
        ],
        span(day(2026, 10, 5), day(2026, 11, 1)),
        later,
        missed: {'gym': fridays.take(missed).toList()},
        profiles: {'gym': kindOf(CategoryKind.routine)},
      );
      final p1 = one(on(2), InsightRule.p1);
      expect(
        (p1.severity, p1.n1, p1.n2, p1.n3, p1.n4),
        (1, 100, 50, 1, 4),
        reason: 'Tuesdays 4 of 4, Fridays 2 of 4',
      );
      expect(fired(on(1), InsightRule.p1), isEmpty, reason: '100 vs 75');
    });

    test('P2: three late Work evenings in one week', () {
      CalendarReport on(Set<int> weekdays) => foldFacts(
        [
          ev(
            'desk',
            'cardio',
            day(2026, 11, 2),
            rule: weekly(weekdays),
            time: at(10, 0, 600),
          ),
        ],
        week,
        later,
        profiles: {'cardio': kindOf(CategoryKind.work)},
      );
      final p2 = one(on({1, 2, 3}), InsightRule.p2);
      expect((p2.severity, p2.n1, p2.minutes, p2.alternate), (1, 3, 0, false));
      expect(fired(on({1, 2}), InsightRule.p2), isEmpty);
    });

    test('P2: Work on the weekend', () {
      CalendarReport on(DateTime d) => foldFacts(
        [ev('desk', 'cardio', d, time: at(10, 0, 120))],
        week,
        later,
        profiles: {'cardio': kindOf(CategoryKind.work)},
      );
      final p2 = one(on(day(2026, 11, 7)), InsightRule.p2);
      expect((p2.n1, p2.minutes, p2.alternate), (0, 120, true));
      expect(fired(on(day(2026, 11, 6)), InsightRule.p2), isEmpty);
    });

    test('P3: three short nights in one week', () {
      CalendarReport on(int short) => foldFacts(
        [
          for (var i = 0; i < 4; i++)
            ev(
              'n$i',
              'rest',
              day(2026, 11, 2 + i),
              time: at(23, 0, i < short ? 400 : 480),
            ),
        ],
        week,
        later,
        profiles: {'rest': kindOf(CategoryKind.sleep)},
      );
      final p3 = one(on(3), InsightRule.p3);
      expect((p3.severity, p3.n1, p3.n2, p3.alternate), (1, 3, 0, false));
      expect(fired(on(2), InsightRule.p3), isEmpty);
    });

    test('P3: bedtimes spread past ninety minutes', () {
      CalendarReport on(int minute) => foldFacts(
        [
          ev('early', 'rest', day(2026, 11, 2), time: at(22, 0, 480)),
          ev('late', 'rest', day(2026, 11, 3), time: at(23, minute, 480)),
        ],
        week,
        later,
        profiles: {'rest': kindOf(CategoryKind.sleep)},
      );
      final p3 = one(on(31), InsightRule.p3);
      expect((p3.n1, p3.n2, p3.alternate), (0, 91, true));
      expect(fired(on(30), InsightRule.p3), isEmpty);
    });

    test('P4: Meetings half of the Work + Meeting hours', () {
      CalendarReport on(int meeting) => foldFacts(
        [
          ev('desk', 'cardio', day(2026, 11, 2), time: at(9, 0, 120)),
          ev('sync', 'competition', day(2026, 11, 3), time: at(9, 0, meeting)),
        ],
        week,
        later,
        profiles: {
          'cardio': kindOf(CategoryKind.work),
          'competition': kindOf(CategoryKind.meeting),
        },
      );
      final p4 = one(on(120), InsightRule.p4);
      expect(
        (p4.categoryId, p4.ratio, p4.minutes, p4.n1),
        ('competition', 0.5, 120, 240),
      );
      expect(fired(on(119), InsightRule.p4), isEmpty);
    });

    test('P4: no Work hours, no share', () {
      CalendarReport on({required bool work}) => foldFacts(
        [
          ev('sync', 'competition', day(2026, 11, 3), time: at(9, 0, 120)),
          if (work) ev('desk', 'cardio', day(2026, 11, 2), time: at(9, 0, 60)),
        ],
        week,
        later,
        profiles: {
          'cardio': kindOf(CategoryKind.work),
          'competition': kindOf(CategoryKind.meeting),
        },
      );
      expect(
        fired(on(work: false), InsightRule.p4),
        isEmpty,
        reason: 'not "100 % of your work hours"',
      );
      expect(one(on(work: true), InsightRule.p4).n1, 180);
    });

    test('P5: three of eight planned days cancelled', () {
      CalendarReport on(DateRange range, int cancelled) => foldFacts(
        [ev('pt', 'gym', day(2026, 11, 2), rule: daily)],
        range,
        later,
        skipped: {
          'pt': [
            day(2026, 11, 3),
            day(2026, 11, 4),
            day(2026, 11, 5),
          ].take(cancelled).toList(),
        },
        profiles: {'gym': kindOf(CategoryKind.workout)},
      );
      final p5 = one(
        on(span(day(2026, 11, 2), day(2026, 11, 9)), 3),
        InsightRule.p5,
      );
      expect((p5.severity, p5.n1, p5.n2, p5.ratio), (2, 3, 8, 0.375));
      expect(
        fired(on(week, 2), InsightRule.p5),
        isEmpty,
        reason: 'two of seven',
      );
    });

    test('P6: a Workout rested ten days', () {
      CalendarReport on(DateTime second) => foldFacts(
        [ev('run', 'gym', day(2026, 11, 1)), ev('run2', 'gym', second)],
        november,
        day(2026, 12, 1),
        profiles: {'gym': kindOf(CategoryKind.workout)},
      );
      final p6 = one(on(day(2026, 11, 12)), InsightRule.p6);
      expect((p6.severity, p6.n1), (1, 10));
      expect(fired(on(day(2026, 11, 11)), InsightRule.p6), isEmpty);
    });

    test('P6: in a current span the rest still running counts', () {
      CalendarReport on(DateTime today) => foldFacts(
        [ev('run', 'gym', day(2026, 11, 1))],
        november,
        today,
        profiles: {'gym': kindOf(CategoryKind.workout)},
      );
      final report = on(day(2026, 11, 25));
      expect(
        report.measures['gym']!.longestGapDays,
        0,
        reason: 'the measure holds closed gaps only',
      );
      expect(one(report, InsightRule.p6).n1, 23, reason: '2 to 24 November');
      expect(one(on(day(2026, 11, 12)), InsightRule.p6).n1, 10);
      expect(fired(on(day(2026, 11, 11)), InsightRule.p6), isEmpty);
    });

    test('M1: Bills due in the next thirty days', () {
      final twoMonths = span(day(2026, 11, 1), day(2026, 12, 31));
      CalendarReport on(DateTime due, {bool tax = true}) {
        final events = [
          ev('rent', 'birthday', due),
          if (tax) ev('tax', 'birthday', day(2026, 11, 20)),
        ];
        return foldFacts(
          events,
          twoMonths,
          mid,
          profiles: {'birthday': kindOf(CategoryKind.bill)},
          money: {'rent': -1200, 'tax': -800},
          billsAhead: billsAheadOf(events, mid),
        );
      }

      final m1 = one(on(day(2026, 12, 15)), InsightRule.m1);
      expect(
        (m1.severity, m1.cents, m1.n1, m1.target),
        (0, 2000, 2, InsightTarget.overviewDays),
      );
      expect((m1.day, m1.dayEnd), (mid, day(2026, 12, 15)));
      expect(
        fired(on(day(2026, 12, 16), tax: false), InsightRule.m1),
        isEmpty,
        reason: '31 days out',
      );
    });

    test('M1: a monthly Rent that began last year counts, once', () {
      final rent = ev(
        'rent',
        'birthday',
        day(2025, 1, 3),
        rule: const MonthlyRecurrence(),
      ).copyWith(noteId: 'n');
      final report = foldFacts(
        [rent],
        november,
        mid,
        profiles: {'birthday': kindOf(CategoryKind.bill)},
        money: {'rent': -1200},
        billsAhead: billsAheadOf([rent], mid),
      );
      expect(report.billsAhead, {
        'birthday': ['rent'],
      });
      final m1 = one(report, InsightRule.m1);
      expect((m1.cents, m1.n1), (1200, 1));
    });

    test('M1: a month report on the 25th sees a Bill on the 3rd of next '
        'month, in every tense', () {
      final bill = ev('water', 'birthday', day(2026, 12, 3));
      CalendarReport on(DateTime today) => foldFacts(
        [bill],
        november,
        today,
        profiles: {'birthday': kindOf(CategoryKind.bill)},
        money: {'water': -300},
        billsAhead: billsAheadOf([bill], today),
      );
      final current = one(on(day(2026, 11, 25)), InsightRule.m1);
      expect(
        (current.cents, current.day, current.dayEnd),
        (300, day(2026, 11, 25), day(2026, 12, 25)),
      );
      final digest = on(day(2026, 12, 1));
      expect(digest.tense, ReportTense.past);
      expect(one(digest, InsightRule.m1).cents, 300, reason: 'the ended month');
    });

    test('M2: a whole year\'s recurring Bills', () {
      CalendarReport on(DateRange range) => foldFacts(
        [
          ev('stream', 'birthday', day(2025, 3, 1), rule: yearly),
          ev('fine', 'birthday', day(2026, 5, 1)),
        ],
        range,
        mid,
        profiles: {'birthday': kindOf(CategoryKind.bill)},
        money: {'stream': -1428, 'fine': -300},
      );
      final m2 = one(on(year), InsightRule.m2);
      expect(
        (m2.severity, m2.cents, m2.n1, m2.target),
        (0, 1428, 1, InsightTarget.categoryGroup),
        reason: 'the one-off fine is no recurring Bill',
      );
      expect(
        fired(on(span(year.start, day(2026, 12, 30))), InsightRule.m2),
        isEmpty,
      );
    });

    test('M2: a tracked recurring Bill counts — the Bill kind marks', () {
      final stream = ev(
        'stream',
        'birthday',
        day(2025, 3, 1),
        rule: yearly,
        tracked: true,
      );
      expect(shapeOf(stream), ReportShape.routine);
      final m2 = one(
        foldFacts(
          [stream],
          year,
          mid,
          profiles: {'birthday': kindOf(CategoryKind.bill)},
          money: {'stream': -1428},
        ),
        InsightRule.m2,
      );
      expect((m2.cents, m2.n1), (1428, 1));
    });

    test('R1: a tag unseen past three of its median gaps, or past the '
        'gap limit', () {
      CalendarReport on(DateTime today, [EffectiveProfile? profile]) =>
          foldFacts(
            [
              ev(
                'dinner',
                'friends',
                day(2026, 10, 1),
                rule: dates([
                  day(2026, 10, 1),
                  day(2026, 10, 8),
                  day(2026, 10, 15),
                ]),
              ).copyWith(title: 'Dinner #ana'),
            ],
            span(day(2026, 10, 1), day(2026, 11, 30)),
            today,
            profiles: {'friends': profile ?? kindOf(CategoryKind.social)},
          );
      final report = on(day(2026, 11, 6));
      expect(report.tags.single.medianGapDays, 7);
      final r1 = one(report, InsightRule.r1);
      expect(
        (r1.severity, r1.tagKey, r1.categoryId, r1.n1, r1.n2, r1.alternate),
        (2, 'ana', 'friends', 22, 21, true),
      );
      expect(r1.target, InsightTarget.tagRows);
      expect(fired(on(day(2026, 11, 5)), InsightRule.r1), isEmpty);
      final limited = one(
        on(day(2026, 11, 5), targeted(CategoryKind.social, maxGap(20))),
        InsightRule.r1,
      );
      expect((limited.n1, limited.n2, limited.alternate), (21, 20, false));
    });

    test('R1: a past span carries none; the current span measures to '
        'today', () {
      final dinner = ev(
        'dinner',
        'friends',
        day(2026, 10, 1),
        rule: dates([
          day(2026, 10, 1),
          day(2026, 10, 8),
          day(2026, 10, 15),
          day(2026, 11, 3),
        ]),
      ).copyWith(title: 'Dinner #ana');
      CalendarReport on(DateRange range, DateTime today) => foldFacts(
        [dinner],
        range,
        today,
        profiles: {'friends': kindOf(CategoryKind.social)},
      );
      final october = on(
        span(day(2026, 10, 1), day(2026, 10, 31)),
        day(2026, 11, 6),
      );
      expect(october.tags.single.lastSeenDay, day(2026, 10, 15));
      expect(
        fired(october, InsightRule.r1),
        isEmpty,
        reason: 'seen 3 days ago, not 22: the span cannot know',
      );
      final current = one(
        on(span(day(2026, 10, 1), day(2026, 11, 30)), day(2026, 11, 30)),
        InsightRule.r1,
      );
      expect((current.n1, current.n2), (27, 21));
    });

    test('R2: the most-seen tag in a People category', () {
      CalendarReport on(EffectiveProfile profile) => foldFacts(
        [
          ev('a1', 'friends', day(2026, 11, 2)).copyWith(title: 'Lunch #ana'),
          ev('a2', 'friends', day(2026, 11, 3)).copyWith(title: 'Tea #ana'),
          ev('m1', 'friends', day(2026, 11, 4)).copyWith(title: 'Run #mihai'),
          ev('m2', 'friends', day(2026, 11, 5)).copyWith(title: '#mihai film'),
          ev('m3', 'friends', day(2026, 11, 6)).copyWith(title: '#mihai walk'),
        ],
        week,
        later,
        profiles: {'friends': profile},
      );
      final r2 = one(on(kindOf(CategoryKind.social)), InsightRule.r2);
      expect(
        (r2.severity, r2.tagKey, r2.categoryId, r2.n1),
        (0, 'mihai', 'friends', 3),
      );
      expect(
        fired(on(kindOf(CategoryKind.trip)), InsightRule.r2),
        isEmpty,
        reason: 'a Trip is no People category',
      );
    });

    test('R2: picks by days, not events', () {
      final report = foldFacts(
        [
          ev(
            'dinner',
            'friends',
            day(2026, 11, 2),
            rule: weekly({1}),
            end: day(2026, 11, 23),
          ).copyWith(title: 'Dinner #ana'),
          ev('m1', 'friends', day(2026, 11, 4)).copyWith(title: 'Run #mihai'),
          ev('m2', 'friends', day(2026, 11, 5)).copyWith(title: '#mihai film'),
        ],
        november,
        day(2026, 11, 30),
        profiles: {'friends': kindOf(CategoryKind.social)},
      );
      expect(
        [for (final t in report.tags) (t.key, t.events, t.count)],
        [('mihai', 2, 2), ('ana', 1, 4)],
      );
      final r2 = one(report, InsightRule.r2);
      expect((r2.tagKey, r2.n1), ('ana', 4), reason: 'most evenings (4)');
    });

    test('L1: Appointments booked a day ahead', () {
      CalendarEvent booked(String id, DateTime d) => ev(
        id,
        'other',
        d,
      ).copyWith(createdAt: d.subtract(const Duration(days: 1)));
      CalendarReport on(int n) => foldFacts(
        [for (var i = 0; i < n; i++) booked('a$i', day(2026, 11, 2 + i))],
        week,
        later,
        profiles: {'other': kindOf(CategoryKind.appointment)},
      );
      final report = on(4);
      expect(report.measures['other']!.leadTimeEvents, 4);
      final l1 = one(report, InsightRule.l1);
      expect((l1.severity, l1.n1, l1.n2), (0, 1, 4));
      expect(fired(on(3), InsightRule.l1), isEmpty);
    });

    test('L2: three Deadlines open past their day', () {
      CalendarReport on(int open) => foldFacts(
        [
          for (var i = 0; i < 3; i++)
            ev('d$i', 'competition', day(2026, 11, 2 + i), tracked: true),
        ],
        week,
        later,
        missed: {
          for (var i = 0; i < open; i++) 'd$i': [day(2026, 11, 2 + i)],
        },
        profiles: {'competition': kindOf(CategoryKind.deadline)},
      );
      final l2 = one(on(3), InsightRule.l2);
      expect(
        (l2.severity, l2.n1, l2.target),
        (2, 3, InsightTarget.categoryGroup),
      );
      expect(fired(on(2), InsightRule.l2), isEmpty);
    });

    test('A1: Anniversaries ahead in the span', () {
      CalendarReport on(DateTime today) => foldFacts(
        [
          ev('ana', 'birthday', day(1990, 11, 20), rule: yearly),
          ev('ion', 'birthday', day(1985, 11, 25), rule: yearly),
        ],
        november,
        today,
        profiles: {'birthday': kindOf(CategoryKind.anniversary)},
      );
      final a1 = one(on(mid), InsightRule.a1);
      expect(
        (a1.severity, a1.n1, a1.day, a1.dayEnd, a1.target),
        (0, 2, mid, november.end, InsightTarget.overviewDays),
      );
      expect(fired(on(day(2026, 11, 26)), InsightRule.a1), isEmpty);
    });

    test('A2: the next Trip ahead', () {
      CalendarReport on(DateTime today) => foldFacts(
        [
          ev('sibiu', 'holiday', day(2026, 11, 25)),
          ev('brasov', 'holiday', day(2026, 11, 20)),
        ],
        november,
        today,
        profiles: {'holiday': kindOf(CategoryKind.trip)},
      );
      final a2 = one(on(mid), InsightRule.a2);
      expect(
        (a2.categoryId, a2.eventId, a2.day, a2.dayEnd, a2.n1),
        ('holiday', 'brasov', day(2026, 11, 20), day(2026, 11, 20), 5),
        reason: 'a one-day trip ends on its day',
      );
      expect(fired(on(day(2026, 11, 26)), InsightRule.a2), isEmpty);
    });

    test('A2: a trip ends on its last day; one under way is no next trip', () {
      CalendarReport on(DateTime today) => foldFacts(
        [
          ev(
            'sibiu',
            'holiday',
            day(2026, 11, 14),
            rule: daily,
            end: day(2026, 11, 17),
          ),
          ev(
            'cluj',
            'holiday',
            day(2026, 11, 22),
            rule: daily,
            end: day(2026, 11, 24),
          ),
          ev(
            'brasov',
            'holiday',
            day(2026, 11, 29),
            rule: daily,
            end: day(2026, 12, 2),
          ),
        ],
        november,
        today,
        profiles: {'holiday': kindOf(CategoryKind.trip)},
      );
      final a2 = one(on(mid), InsightRule.a2);
      expect(
        (a2.eventId, a2.day, a2.dayEnd, a2.n1),
        ('cluj', day(2026, 11, 22), day(2026, 11, 24), 7),
        reason: 'Sibiu began on the 14th: under way, not ahead',
      );
      expect(
        one(on(day(2026, 11, 13)), InsightRule.a2).eventId,
        'sibiu',
        reason: 'the day before, Sibiu is the next trip',
      );
      final starting = one(on(day(2026, 11, 22)), InsightRule.a2);
      expect(
        (starting.eventId, starting.dayEnd, starting.n1),
        ('brasov', november.end, 7),
        reason:
            'Cluj begins today, never "in 0 days"; Brasov runs past the '
            'span, so its range ends with it',
      );
      expect(fired(on(day(2026, 11, 29)), InsightRule.a2), isEmpty);
    });

    test('A1: a tracked routine counts its occurrences ahead', () {
      final report = foldFacts(
        [
          ev(
            'ana',
            'birthday',
            day(2026, 11, 10),
            rule: daily,
            end: day(2026, 11, 18),
            tracked: true,
          ),
          ev('ion', 'birthday', day(1985, 11, 25), rule: yearly),
        ],
        november,
        mid,
        profiles: {'birthday': kindOf(CategoryKind.anniversary)},
      );
      expect(
        report.categories.single.rows.whereType<ReportRoutineRow>().length,
        1,
        reason: 'the counted days are one aggregate row',
      );
      expect(
        one(report, InsightRule.a1).n1,
        4,
        reason: 'the 16th, 17th and 18th, and the 25th',
      );
    });

    test('G4: a plan carries no streak insight', () {
      final today = day(2026, 11, 5);
      final plan = span(day(2026, 11, 9), day(2026, 11, 15));
      final events = [
        ev('lift', 'gym', day(2026, 10, 5), rule: weekly({1})),
      ];
      final report = foldFacts(
        events,
        plan,
        today,
        profiles: {
          'gym': targeted(CategoryKind.custom, perWeek(TargetKind.atLeast, 1)),
        },
        lookback: lookbackFor('gym', events, plan, today),
      );
      expect(report.tense, ReportTense.future);
      final goal = goalOf(report, 'gym');
      expect(
        goal.streak + goal.brokenStreak,
        greaterThan(0),
        reason: 'the lookback gives the plan a streak to read',
      );
      expect(fired(report, InsightRule.g4), isEmpty);
    });

    test('D1: a gap past the lookback carries the floor', () {
      final events = [
        ev('service', 'cardio', day(2025, 11, 1), rule: yearly, tracked: true),
      ];
      final missed = {
        'service': [day(2025, 11, 1), day(2026, 11, 1)],
      };
      final report = foldFacts(
        events,
        november,
        mid,
        missed: missed,
        profiles: {'cardio': targeted(CategoryKind.maintenance, maxGap(30))},
        lookback: lookbackFor('cardio', events, november, mid, missed: missed),
      );
      final d1 = one(report, InsightRule.d1);
      expect(
        (d1.n1, d1.n2, d1.beyondLookback),
        (AnalyticsMetrics.lookbackDays, 30, true),
      );
      expect(
        one(gapOf(day(2026, 11, 1)), InsightRule.d1).beyondLookback,
        isFalse,
      );
    });

    test('P1: exact shares decide, one step apart; the slots round', () {
      CalendarReport on(int missedFridays) {
        final tuesdays = [day(2026, 8, 4), day(2026, 8, 11), day(2026, 8, 18)];
        final fridays = [
          for (var i = 0; i < missedFridays; i++) day(2026, 8, 7 + 7 * i),
        ];
        return foldFacts(
          [
            ev(
              'tue',
              'gym',
              day(2026, 8, 4),
              rule: weekly({2}),
              end: day(2026, 9, 22),
              tracked: true,
            ),
            ev('fri', 'gym', day(2026, 8, 7), rule: weekly({5}), tracked: true),
          ],
          span(day(2026, 8, 3), day(2026, 11, 1)),
          later,
          missed: {'tue': tuesdays, 'fri': fridays},
          profiles: {'gym': kindOf(CategoryKind.routine)},
        );
      }

      expect(
        fired(on(10), InsightRule.p1),
        isEmpty,
        reason:
            'Tuesdays 5 of 8, Fridays 3 of 13: 39.4 points, though the '
            'rounded 63 and 23 are forty apart',
      );
      final p1 = one(on(11), InsightRule.p1);
      expect(
        (p1.n1, p1.n2, p1.n3, p1.n4),
        (63, 15, 1, 4),
        reason: 'Fridays 2 of 13: 47.1 points',
      );
    });

    test('P1: each compared weekday needs four tracked days', () {
      CalendarReport on(int fridays) => foldFacts(
        [
          ev('tue', 'gym', day(2026, 10, 6), rule: weekly({2}), tracked: true),
          ev(
            'fri',
            'gym',
            day(2026, 10, 9),
            rule: weekly({5}),
            end: day(2026, 10, 9 + 7 * (fridays - 1)),
            tracked: true,
          ),
        ],
        span(day(2026, 10, 5), day(2026, 11, 1)),
        later,
        missed: {
          'fri': [for (var i = 0; i < fridays; i++) day(2026, 10, 9 + 7 * i)],
        },
        profiles: {'gym': kindOf(CategoryKind.routine)},
      );
      final p1 = one(on(4), InsightRule.p1);
      expect((p1.n1, p1.n2, p1.n3, p1.n4), (100, 0, 1, 4));
      expect(
        fired(on(3), InsightRule.p1),
        isEmpty,
        reason: 'three Fridays are not "Fridays"',
      );
    });

    test('P5: the cancelled share and the planned floor, one step apart', () {
      CalendarReport on(DateTime end, int cancelled) => foldFacts(
        [ev('pt', 'gym', day(2026, 11, 2), rule: daily)],
        span(day(2026, 11, 2), end),
        later,
        skipped: {
          'pt': [for (var i = 0; i < cancelled; i++) day(2026, 11, 2 + i)],
        },
        profiles: {'gym': kindOf(CategoryKind.workout)},
      );
      final atShare = one(on(day(2026, 11, 11), 3), InsightRule.p5);
      expect((atShare.n1, atShare.n2, atShare.ratio), (3, 10, 0.3));
      expect(
        fired(on(day(2026, 11, 12), 3), InsightRule.p5),
        isEmpty,
        reason: 'three of eleven is under the share',
      );
      final atFloor = one(on(day(2026, 11, 5), 3), InsightRule.p5);
      expect((atFloor.n1, atFloor.n2), (3, 4));
      expect(
        fired(on(day(2026, 11, 4), 3), InsightRule.p5),
        isEmpty,
        reason: 'three planned days are under the floor, all cancelled',
      );
    });

    test('L1: a median lead of two days is not short notice', () {
      CalendarReport on(int lead) => foldFacts(
        [
          for (var i = 0; i < 4; i++)
            ev(
              'a$i',
              'other',
              day(2026, 11, 2 + i),
            ).copyWith(createdAt: day(2026, 11, 2 + i - lead)),
        ],
        week,
        later,
        profiles: {'other': kindOf(CategoryKind.appointment)},
      );
      expect(one(on(1), InsightRule.l1).n1, 1);
      expect(fired(on(2), InsightRule.l1), isEmpty);
    });

    test('D5: a CV of 0.25 is no pattern, one step under is', () {
      CalendarReport on(DateTime third) => foldFacts(
        [
          ev('m1', 'measurement', day(2026, 10, 1)),
          ev('m2', 'measurement', day(2026, 10, 16)),
          ev('m3', 'measurement', third),
        ],
        span(day(2026, 10, 1), day(2026, 11, 30)),
        day(2026, 11, 3),
        profiles: {'measurement': kindOf(CategoryKind.episode)},
      );
      final at = on(day(2026, 10, 25));
      expect(
        at.measures['measurement']!.episodeGapCv,
        AnalyticsMetrics.episodeRegularCv,
        reason: 'gaps 15 and 9',
      );
      expect(fired(at, InsightRule.d5), isEmpty);
      final under = on(day(2026, 10, 26));
      expect(
        under.measures['measurement']!.episodeGapCv,
        lessThan(AnalyticsMetrics.episodeRegularCv),
        reason: 'gaps 15 and 10',
      );
      final d5 = one(under, InsightRule.d5);
      expect((d5.day, d5.n1, d5.n2, d5.n3), (day(2026, 11, 8), 3, 13, 5));
    });

    test('D5: two episodes are no pattern, three are', () {
      CalendarReport on(int count) => foldFacts(
        [
          for (var i = 3 - count; i < 3; i++)
            ev('m$i', 'measurement', day(2026, 10, 6 + 10 * i)),
        ],
        span(day(2026, 10, 1), day(2026, 11, 30)),
        day(2026, 11, 1),
        profiles: {'measurement': kindOf(CategoryKind.episode)},
      );
      expect(
        fired(on(2), InsightRule.d5),
        isEmpty,
        reason: 'one gap, perfectly regular, is still no pattern',
      );
      final d5 = one(on(3), InsightRule.d5);
      expect((d5.day, d5.n1, d5.n2, d5.n3), (day(2026, 11, 5), 3, 10, 4));
    });

    test('ranking: severity, then the primary value, then rule order; no '
        'profile, no insight', () {
      final events = [
        ev('lift', 'gym', day(2026, 11, 2)),
        ev('rent', 'birthday', day(2026, 11, 2), tracked: true),
        ev(
          'desk',
          'cardio',
          day(2026, 11, 2),
          rule: daily,
          end: day(2026, 11, 3),
        ),
        ev(
          'stretch',
          'mobility',
          day(2026, 11, 2),
          rule: daily,
          end: day(2026, 11, 5),
          tracked: true,
        ),
        ev('sibiu', 'holiday', day(2026, 11, 7)),
      ];
      CalendarReport on(Map<String, EffectiveProfile> profiles) => foldFacts(
        events,
        week,
        day(2026, 11, 5),
        missed: {
          'rent': [day(2026, 11, 2)],
        },
        skipped: {
          'stretch': [day(2026, 11, 3), day(2026, 11, 4)],
        },
        profiles: profiles,
      );
      final report = on({
        'gym': targeted(CategoryKind.custom, perWeek(TargetKind.atLeast, 3)),
        'birthday': kindOf(CategoryKind.bill),
        'cardio': targeted(CategoryKind.custom, perWeek(TargetKind.atMost, 1)),
        'mobility': kindOf(CategoryKind.routine),
        'holiday': kindOf(CategoryKind.trip),
      });
      expect(
        [for (final i in report.insights) '${i.rule.name} ${i.categoryId}'],
        ['g1 gym', 'd4 birthday', 'g2 cardio', 'p5 mobility', 'a2 holiday'],
        reason:
            'G1 and D4 at 3, the gym leading by one kept day; G2 and P5 at 2 '
            'with two each, so the rule order',
      );
      expect(on(const {}).insights, isEmpty);
    });

    test('ranking: a severity tie goes to the larger primary over the rule '
        'order, then a full tie to the emission order', () {
      final report = foldFacts(
        [
          ev('lift', 'gym', day(2026, 11, 2)),
          ev('rent', 'birthday', day(2026, 11, 2), tracked: true),
          ev('water', 'birthday', day(2026, 11, 3), tracked: true),
        ],
        week,
        day(2026, 11, 5),
        missed: {
          'rent': [day(2026, 11, 2)],
          'water': [day(2026, 11, 3)],
        },
        profiles: {
          'gym': targeted(CategoryKind.custom, perWeek(TargetKind.atLeast, 3)),
          'birthday': kindOf(CategoryKind.bill),
        },
        money: {'rent': -1200},
      );
      expect(
        (
          report.measures['gym']!.primary,
          report.measures['birthday']!.primary,
          report.measures['birthday']!.spentCents,
        ),
        (ReportMeasure.count, ReportMeasure.money, 1200),
      );
      expect(
        [
          for (final i in report.insights)
            '${i.rule.name} ${i.categoryId} ${i.eventId}',
        ],
        ['d4 birthday water', 'd4 birthday rent', 'g1 gym null'],
        reason:
            'all at 3: the Bill category leads G1\'s count by its cents though '
            'D4 comes later in the rule order; the two D4s tie on both and '
            'keep the Due soon order (the fewest days since first), not the '
            'event ids\'',
      );
    });

    test('the measures the rules read: missed by weekday from the week '
        'start', () {
      final events = [
        ev('gym', 'gym', day(2026, 10, 31), rule: daily, tracked: true),
      ];
      final range = span(day(2026, 10, 31), day(2026, 11, 6));
      final missed = {
        'gym': [day(2026, 10, 31), day(2026, 11, 2)],
      };
      final saturday = foldFacts(
        events,
        range,
        later,
        missed: missed,
        weekStart: CalendarWeekStart.saturday,
      ).measures['gym']!;
      expect(saturday.missedByWeekday, [1, 0, 1, 0, 0, 0, 0]);
      expect(saturday.weekdayHistogram, [0, 1, 0, 1, 1, 1, 1]);
      final monday = foldFacts(
        events,
        range,
        later,
        missed: missed,
      ).measures['gym']!;
      expect(monday.missedByWeekday, [1, 0, 0, 0, 0, 1, 0]);
    });

    test('the measures the rules read: late and short days per week, the '
        'weekend\'s minutes', () {
      final events = [
        ev(
          'desk',
          'cardio',
          day(2026, 11, 7),
          rule: daily,
          end: day(2026, 11, 9),
          time: at(13, 0, 400),
        ),
      ];
      final monday = foldFacts(events, november, later).measures['cardio']!;
      expect(
        (
          monday.lateDays,
          monday.maxLateDaysInAWeek,
          monday.maxShortDaysInAWeek,
          monday.weekendMinutes,
        ),
        (3, 2, 2, 800),
        reason: 'Saturday and Sunday close a Monday week',
      );
      final saturday = foldFacts(
        events,
        november,
        later,
        weekStart: CalendarWeekStart.saturday,
      ).measures['cardio']!;
      expect(
        (saturday.maxLateDaysInAWeek, saturday.maxShortDaysInAWeek),
        (3, 3),
      );
    });

    test('the measures the rules read: the start spread wraps past '
        'midnight', () {
      int spreadOf(List<EventTime> times) => foldFacts(
        [
          for (final (i, t) in times.indexed)
            ev('n$i', 'rest', day(2026, 11, 2 + i), time: t),
        ],
        november,
        later,
        profiles: {'rest': kindOf(CategoryKind.sleep)},
      ).measures['rest']!.startMinuteSpread;
      expect(spreadOf([at(23, 30, 60), at(0, 30, 60)]), 60);
      expect(spreadOf([at(22, 0, 60), at(23, 30, 60)]), 90);
      expect(spreadOf([at(22, 0, 60), at(23, 30, 60), at(1, 0, 60)]), 180);
      expect(spreadOf([at(22, 0, 60)]), 0);
    });

    test('the measures the rules read: the bedtime spread is the 10th to '
        'the 90th percentile', () {
      ReportMeasures on(List<EventTime> times, {CategoryKind? kind}) =>
          foldFacts(
            [
              for (final (i, t) in times.indexed)
                ev('n$i', 'rest', day(2026, 11, 1 + i), time: t),
            ],
            november,
            day(2026, 12, 1),
            profiles: {if (kind != null) 'rest': kindOf(kind)},
          ).measures['rest']!;
      final oneLate = [
        for (var i = 0; i < 29; i++) at(23, 0, 480),
        at(0, 45, 480),
      ];
      final sleep = on(oneLate, kind: CategoryKind.sleep);
      expect(
        sleep.startMinuteSpread,
        0,
        reason: 'one 00:45 night in thirty is no spread (the full range: 105)',
      );
      expect(sleep.medianStartMinute, 23 * 60);
      // 21:00, nine nights 22:00–23:20 and 02:00: the trim leaves one out at
      // each end, so 22:00–23:20 — never the 21:00–02:00 range's 300.
      final real = [
        at(21, 0, 480),
        for (var i = 0; i < 9; i++) at(22, 10 * i, 480),
        at(2, 0, 480),
      ];
      expect(on(real, kind: CategoryKind.sleep).startMinuteSpread, 80);
      expect(
        on(real).startMinuteSpread,
        0,
        reason: 'read only on a Sleep category',
      );
      expect(
        on(real, kind: CategoryKind.workout).startMinuteSpread,
        0,
        reason: 'read only on a Sleep category',
      );
    });

    test('the measures the rules read: a nap is no short night', () {
      int shortOf(int minutes) => foldFacts(
        [
          for (var i = 0; i < 3; i++)
            ev('n$i', 'rest', day(2026, 11, 2 + i), time: at(14, 0, minutes)),
        ],
        week,
        later,
        profiles: {'rest': kindOf(CategoryKind.sleep)},
      ).measures['rest']!.maxShortDaysInAWeek;
      expect(shortOf(AnalyticsMetrics.sleepNightMinMinutes), 3);
      expect(shortOf(AnalyticsMetrics.sleepNightMinMinutes - 1), 0);
      expect(shortOf(AnalyticsMetrics.sleepShortMinutes - 1), 3);
      expect(shortOf(AnalyticsMetrics.sleepShortMinutes), 0);
    });

    test('P3: three naps in a week are no short nights', () {
      CalendarReport on(int minutes) => foldFacts(
        [
          for (var i = 0; i < 3; i++)
            ev('n$i', 'rest', day(2026, 11, 2 + i), time: at(14, 0, minutes)),
        ],
        week,
        later,
        profiles: {'rest': kindOf(CategoryKind.sleep)},
      );
      expect(one(on(180), InsightRule.p3).n1, 3);
      expect(fired(on(90), InsightRule.p3), isEmpty);
    });

    test('the measures the rules read: only an Episode category walks '
        'episodes', () {
      ReportMeasures on(CategoryKind? kind) => foldFacts(
        [
          ev('a', 'rest', day(2026, 11, 2)),
          ev('b', 'rest', day(2026, 11, 9)),
          ev('c', 'rest', day(2026, 11, 16)),
        ],
        november,
        later,
        profiles: {if (kind != null) 'rest': kindOf(kind)},
      ).measures['rest']!;
      expect(on(CategoryKind.episode).episodes, 3);
      for (final kind in [null, CategoryKind.workout, CategoryKind.sleep]) {
        final m = on(kind);
        expect(
          (m.episodes, m.lastEpisodeDay, m.episodeGapMean, m.episodeGapCv),
          (0, null, null, null),
          reason: '$kind',
        );
        expect(m.count, 3, reason: 'the kept days still count');
      }
    });

    test('the measures the rules read: the longest gap between kept '
        'days', () {
      ReportMeasures on(List<DateTime> days) => foldFacts(
        [ev('run', 'gym', days.first, rule: dates(days), tracked: true)],
        november,
        later,
        missed: {
          'run': [day(2026, 11, 8)],
        },
      ).measures['gym']!;
      expect(
        on([
          day(2026, 11, 1),
          day(2026, 11, 4),
          day(2026, 11, 8),
          day(2026, 11, 12),
        ]).longestGapDays,
        7,
        reason: 'the missed 8th is no kept day',
      );
      expect(on([day(2026, 11, 1)]).longestGapDays, 0);
    });

    test('the measures the rules read: a tag\'s median gap', () {
      List<ReportTag> on(List<DateTime> days) => foldFacts(
        [
          ev(
            'dinner',
            'friends',
            days.first,
            rule: dates(days),
          ).copyWith(title: 'Dinner #ana'),
          ev('lunch', 'friends', days.first).copyWith(title: 'Lunch #ana'),
        ],
        span(day(2026, 10, 1), day(2026, 10, 31)),
        later,
      ).tags;
      expect(
        on([
          day(2026, 10, 1),
          day(2026, 10, 8),
          day(2026, 10, 22),
          day(2026, 10, 25),
        ]).single.medianGapDays,
        7,
        reason: 'gaps 7, 14 and 3; the lunch on the 1st adds none',
      );
      expect(on([day(2026, 10, 1)]).single.medianGapDays, isNull);
    });

    test('profiled: a category with a profile of its own', () {
      final report = foldFacts(
        [
          ev('a', 'gym', day(2026, 11, 2)),
          ev('b', 'cardio', day(2026, 11, 2)),
          ev('c', 'mobility', day(2026, 11, 2)),
        ],
        week,
        later,
        profiles: {
          'gym': kindOf(CategoryKind.workout),
          'mobility': targeted(CategoryKind.custom, maxGap(5)),
        },
      );
      expect(
        [
          for (final id in ['gym', 'cardio', 'mobility'])
            report.measures[id]!.profiled,
        ],
        [true, false, true],
      );
    });
  });

  group('purity', () {
    const roots = [
      'lib/utils/calendar_report_builder.dart',
      'lib/models/calendar_report.dart',
      'lib/utils/report_insights.dart',
      'lib/utils/task_count.dart',
    ];
    String code(String path) => File(path)
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('///'))
        .join('\n');

    test('the builder, the model and the counter read no clock', () {
      for (final path in roots) {
        final source = code(path);
        expect(source, isNot(contains('DateTime.now')), reason: path);
        expect(source, isNot(contains('DateFormat')), reason: path);
      }
    });

    // Two imports of existing files lead out of the pure set, and are left
    // for the lead to rule on rather than refactored in this slice: the
    // recurrence rules import the public-holiday catalogue, which imports
    // the generated localizations (intl, widgets), and the markdown line
    // shape imports the markdown constants, which import Material for their
    // icons. The walk steps over exactly these two edges and asserts they
    // are still there, so fixing either one makes this test say so.
    const knownEdges = {
      'lib/models/recurrence_rule.dart': 'lib/constants/public_holidays.dart',
      'lib/utils/markdown_line_shape.dart':
          'lib/constants/markdown_constants.dart',
    };

    test('their relative imports reach no service, string, page, widget or '
        'bloc', () {
      final relativeImport = RegExp(r"^import '([^':]+)'", multiLine: true);
      final seen = <String>{};
      final stepped = <String, String>{};
      final queue = [...roots];
      while (queue.isNotEmpty) {
        final path = queue.removeLast();
        if (!seen.add(path)) continue;
        for (final match in relativeImport.allMatches(code(path))) {
          final target = Uri.parse(path).resolve(match.group(1)!).path;
          if (knownEdges[path] == target) {
            stepped[path] = target;
            continue;
          }
          queue.add(target);
        }
      }

      expect(stepped, knownEdges);
      expect(seen, contains('lib/utils/within_day_order.dart'));
      expect(seen, isNot(contains('lib/utils/event_agenda.dart')));
      for (final path in seen) {
        for (final banned in [
          'lib/services/',
          'lib/l10n/',
          'lib/pages/',
          'lib/widgets/',
          'lib/bloc/',
        ]) {
          expect(path, isNot(startsWith(banned)));
        }
        final source = code(path);
        expect(
          source,
          isNot(contains("import 'package:flutter/material.dart'")),
          reason: path,
        );
        expect(source, isNot(contains("import 'package:intl")), reason: path);
      }
    });
  });
}
