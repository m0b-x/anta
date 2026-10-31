import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/date_range.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/calendar_report_builder.dart';

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

  group('purity', () {
    const roots = [
      'lib/utils/calendar_report_builder.dart',
      'lib/models/calendar_report.dart',
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
