import '../constants/occurrence_descriptions.dart';
import '../constants/report_metrics.dart';
import '../models/calendar_event.dart';
import '../models/calendar_report.dart';
import '../models/date_range.dart';
import 'task_count.dart';
import 'within_day_order.dart';

/// Folds occurrence samples into a [CalendarReport] — the one place a report
/// number is computed (U), so the page, the digest's words and the share can
/// never disagree.
///
/// Pure on purpose: the sampler hands over the samples, today, the week start
/// and the description texts, so the fold reads no clock, no static cache and
/// no formatter, and runs the same from a bloc's handler or the digest
/// planner with no bloc alive.
abstract final class CalendarReportBuilder {
  /// The tense-agnostic counts of the [samples] whose day lies in [counted].
  ///
  /// Tasks follow D27: a shared-scope event's text counts once if it occurs
  /// in the range at all; a per-day-scope event counts what each of its days
  /// shows (that day's override, else the shared text). A missed flag counts
  /// only on a tracked event — an untracked occurrence cannot be missed.
  ///
  /// Trusts the sampler's `missed` and `pending` flags as they come: a
  /// pending sample is left out (it has not happened yet, D31), and unlike
  /// [fold] nothing here clears a flag on a day after today — the caller
  /// folding a previous span hands over days that have all passed. A plan's
  /// previous span may hold today, and a plan counts every occurrence, so a
  /// caller folding a plan's previous totals clears `pending` first.
  static ReportTotals foldTotals({
    required DateRange counted,
    required Map<String, CalendarEvent> events,
    required Iterable<ReportSample> samples,
    required Map<String, Map<DateTime, String>> overrides,
  }) {
    assert(
      _isDateOnly(counted.start) && _isDateOnly(counted.end),
      'foldTotals requires a date-only UTC range',
    );
    assert(
      samples.every((s) => _isDateOnly(s.day)),
      'foldTotals requires date-only UTC sample days',
    );
    var occurrences = 0;
    var kept = 0;
    var missed = 0;
    var attended = 0;
    var tracked = 0;
    var minutesKept = 0;
    var minutesAll = 0;
    var tasksTicked = 0;
    var tasksTotal = 0;
    final sharedCounted = <String>{};
    for (final sample in samples) {
      if (sample.pending || !_contains(counted, sample.day)) continue;
      final event = events[sample.eventId];
      if (event == null) continue;
      occurrences++;
      final routine = _isRoutine(event);
      final minutes = event.time?.durationMinutes ?? 0;
      minutesAll += minutes;
      if (routine) tracked++;
      if (_isMissed(sample, event)) {
        missed++;
      } else {
        kept++;
        minutesKept += minutes;
        if (routine) attended++;
      }
      final ReportTaskCount? tasks;
      if (OccurrenceDescriptions.appliesTo(event)) {
        tasks = countTasks(_textFor(event, sample.day, overrides));
      } else {
        tasks = sharedCounted.add(event.id)
            ? countTasks(event.description)
            : null;
      }
      if (tasks != null) {
        tasksTicked += tasks.ticked;
        tasksTotal += tasks.total;
      }
    }
    return ReportTotals(
      occurrences: occurrences,
      kept: kept,
      missed: missed,
      attended: attended,
      tracked: tracked,
      minutesKept: minutesKept,
      minutesAll: minutesAll,
      tasksTicked: tasksTicked,
      tasksTotal: tasksTotal,
    );
  }

  /// The report of [input]'s span: counted from the span's start to today
  /// (or its end, when that comes first), the rest ahead; a span wholly
  /// after today is a plan, counted whole and graded on nothing (T). A
  /// pending sample (D31) is read as ahead in a graded span and as a plain
  /// occurrence in a plan.
  static CalendarReport fold(ReportInput input) {
    final span = input.span;
    final today = input.today;
    final events = input.events;
    assert(
      _isDateOnly(span.start) && _isDateOnly(span.end) && _isDateOnly(today),
      'fold requires a date-only UTC span and today',
    );
    assert(
      input.samples.every((s) => _isDateOnly(s.day)),
      'fold requires date-only UTC sample days',
    );
    assert(
      input.samples.every((s) => !s.pending || s.day == today),
      'a pending sample lies on today',
    );
    final tense = CalendarReport.tenseOf(span: span, today: today);
    final countedTo = CalendarReport.countedToOf(span: span, today: today);
    final DateRange counted = (start: span.start, end: countedTo);
    final DateRange? aheadRange =
        tense == ReportTense.current && today.isBefore(span.end)
        ? (start: _addDays(today, 1), end: span.end)
        : null;

    final graded = tense != ReportTense.future;
    final samples = _settled(input.samples, today, graded: graded);
    final totals = foldTotals(
      counted: counted,
      events: events,
      samples: samples,
      overrides: input.overrides,
    );

    final countedSamples = <ReportSample>[];
    final aheadSamples = <ReportSample>[];
    for (final sample in samples) {
      if (!events.containsKey(sample.eventId)) continue;
      if (_contains(counted, sample.day)) {
        (sample.pending ? aheadSamples : countedSamples).add(sample);
      } else if (aheadRange != null && _contains(aheadRange, sample.day)) {
        aheadSamples.add(sample);
      }
    }
    int byDay(ReportSample a, ReportSample b) {
      final byDate = a.day.compareTo(b.day);
      if (byDate != 0) return byDate;
      return compareEventsWithinDay(events[a.eventId]!, events[b.eventId]!);
    }

    countedSamples.sort(byDay);
    aheadSamples.sort(byDay);

    final order = <String, int>{
      for (final (i, id) in input.categoryOrder.indexed) id: i,
    };

    final trend = graded && totals.kept >= ReportMetrics.trendMinOccurrences
        ? _trend(input, countedSamples)
        : null;
    return CalendarReport(
      span: span,
      today: today,
      tense: tense,
      countedTo: countedTo,
      previousSpan: input.previousSpan,
      previousCounted: input.previousCounted,
      events: Map.unmodifiable(events),
      tiles: List.unmodifiable(_tiles(tense, input, totals)),
      skippedDays: input.skippedDays,
      aheadCount: aheadSamples.length,
      categories: List.unmodifiable(
        _categories(input, countedSamples, order, graded: graded),
      ),
      trend: trend,
      missed: graded
          ? List.unmodifiable(
              _datedGroups(
                input,
                [
                  for (final sample in countedSamples)
                    if (_isMissed(sample, events[sample.eventId]!)) sample,
                ],
                order,
                missedCard: true,
              ),
            )
          : const [],
      ahead: List.unmodifiable(
        _datedGroups(input, aheadSamples, order, missedCard: false),
      ),
    );
  }

  /// The tile set (D15, D20): decided by what the selection could ever show,
  /// never by what the period holds, so stepping never reshuffles the grid.
  static List<ReportTileValue> _tiles(
    ReportTense tense,
    ReportInput input,
    ReportTotals totals,
  ) {
    final events = input.events.values;
    final anyRoutine = events.any(_isRoutine);
    final anyTimed = events.any((e) => e.time?.durationMinutes != null);
    final anyTasks = events.any((e) => _holdsTasks(e, input.overrides));
    final previous = input.previousTotals;
    final plan = tense == ReportTense.future;
    return [
      if (plan)
        ReportTileValue(
          tile: ReportTile.planned,
          value: totals.occurrences,
          previous: previous?.occurrences,
        )
      else ...[
        ReportTileValue(
          tile: ReportTile.events,
          value: totals.kept,
          previous: previous?.kept,
        ),
        if (anyRoutine) ...[
          ReportTileValue(
            tile: ReportTile.attended,
            value: totals.attended,
            of: totals.tracked,
            previous: previous?.attended,
            previousOf: previous?.tracked,
          ),
          ReportTileValue(
            tile: ReportTile.missed,
            value: totals.missed,
            previous: previous?.missed,
          ),
        ],
      ],
      // A plan's minutes are every occurrence's, compared with the previous
      // span's every occurrence (D28): the missed ones were planned too.
      if (anyTimed)
        ReportTileValue(
          tile: ReportTile.hours,
          value: plan ? totals.minutesAll : totals.minutesKept,
          previous: plan ? previous?.minutesAll : previous?.minutesKept,
        ),
      if (anyTasks)
        ReportTileValue(
          tile: ReportTile.tasks,
          value: totals.tasksTicked,
          of: totals.tasksTotal,
          previous: previous?.tasksTicked,
          previousOf: previous?.tasksTotal,
        ),
    ];
  }

  /// The Categories card (W): one group per category with a counted
  /// occurrence. In a graded span a routine is one aggregate row ahead of
  /// the dated rows; in a plan every occurrence is a dated row, since a plan
  /// has nothing to aggregate yet.
  static List<ReportCategoryGroup> _categories(
    ReportInput input,
    List<ReportSample> countedSamples,
    Map<String, int> order, {
    required bool graded,
  }) {
    final events = input.events;
    final groups = <String, _GroupTally>{};
    for (final sample in countedSamples) {
      final event = events[sample.eventId]!;
      final tally = groups.putIfAbsent(
        _categoryOf(input, event),
        _GroupTally.new,
      );
      final missed = _isMissed(sample, event);
      final minutes = event.time?.durationMinutes ?? 0;
      if (missed) {
        tally.missed++;
      } else {
        tally.count++;
        tally.minutes += minutes;
      }
      if (graded && _isRoutine(event)) {
        final routine = tally.routines.putIfAbsent(event.id, _RoutineTally.new);
        routine.total++;
        routine.latest = sample.day;
        if (!missed) {
          routine.attended++;
          routine.minutes += minutes;
          routine.latestAttended = sample.day;
        }
      } else {
        tally.dated.add(_datedRow(input, sample, event));
      }
    }
    final result = [
      for (final MapEntry(key: categoryId, value: tally) in groups.entries)
        ReportCategoryGroup(
          categoryId: categoryId,
          count: tally.count,
          minutes: tally.minutes,
          missed: tally.missed,
          rows: List.unmodifiable([
            ..._routineRows(events, tally.routines),
            ...tally.dated,
          ]),
        ),
    ];
    result.sort((a, b) => _compareGroups(a, b, order));
    return result;
  }

  /// A group's routine rows: the most occurrences first, then by title, so
  /// the routine the period was most about leads.
  static List<ReportRoutineRow> _routineRows(
    Map<String, CalendarEvent> events,
    Map<String, _RoutineTally> routines,
  ) {
    final rows = [
      for (final MapEntry(key: eventId, value: tally) in routines.entries)
        ReportRoutineRow(
          eventId: eventId,
          attended: tally.attended,
          total: tally.total,
          minutes: tally.minutes,
          latestDay: tally.latestAttended ?? tally.latest!,
        ),
    ];
    rows.sort((a, b) {
      final byTotal = b.total.compareTo(a.total);
      if (byTotal != 0) return byTotal;
      final byTitle = events[a.eventId]!.titleFold.compareTo(
        events[b.eventId]!.titleFold,
      );
      return byTitle != 0 ? byTitle : a.eventId.compareTo(b.eventId);
    });
    return rows;
  }

  /// Missed and Ahead (G, N): dated rows only, grouped by category in the
  /// Categories order rule; a header counts its rows. A Missed header spends
  /// no minutes (nothing was spent on a missed day) and counts every row
  /// missed; an Ahead header carries the planned minutes and nothing missed.
  static List<ReportCategoryGroup> _datedGroups(
    ReportInput input,
    List<ReportSample> samples,
    Map<String, int> order, {
    required bool missedCard,
  }) {
    if (samples.isEmpty) return const [];
    final events = input.events;
    final groups = <String, _GroupTally>{};
    for (final sample in samples) {
      final event = events[sample.eventId]!;
      final tally = groups.putIfAbsent(
        _categoryOf(input, event),
        _GroupTally.new,
      );
      tally.count++;
      if (missedCard) {
        tally.missed++;
      } else {
        tally.minutes += event.time?.durationMinutes ?? 0;
      }
      tally.dated.add(_datedRow(input, sample, event));
    }
    final result = [
      for (final MapEntry(key: categoryId, value: tally) in groups.entries)
        ReportCategoryGroup(
          categoryId: categoryId,
          count: tally.count,
          minutes: tally.minutes,
          missed: tally.missed,
          rows: List.unmodifiable(tally.dated),
        ),
    ];
    result.sort((a, b) => _compareGroups(a, b, order));
    return result;
  }

  static ReportDatedRow _datedRow(
    ReportInput input,
    ReportSample sample,
    CalendarEvent event,
  ) {
    return ReportDatedRow(
      eventId: event.id,
      day: sample.day,
      missed: _isMissed(sample, event),
      tasks: countTasks(
        OccurrenceDescriptions.appliesTo(event)
            ? _textFor(event, sample.day, input.overrides)
            : event.description,
      ),
    );
  }

  /// The larger count first; equal counts keep the catalogue's order, so
  /// two folds of the same data always draw the same page.
  static int _compareGroups(
    ReportCategoryGroup a,
    ReportCategoryGroup b,
    Map<String, int> order,
  ) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    final aOrder = order[a.categoryId] ?? order.length;
    final bOrder = order[b.categoryId] ?? order.length;
    final byOrder = aOrder.compareTo(bOrder);
    return byOrder != 0 ? byOrder : a.categoryId.compareTo(b.categoryId);
  }

  /// The Over time series and its caption facts (D29) over the counted
  /// samples; the columns cover the whole span.
  static ReportTrend _trend(
    ReportInput input,
    List<ReportSample> countedSamples,
  ) {
    final span = input.span;
    final days = span.end.difference(span.start).inDays + 1;
    final unit = days <= ReportMetrics.trendDayUnitMaxDays
        ? ReportTrendUnit.day
        : days <= ReportMetrics.trendWeekUnitMaxDays
        ? ReportTrendUnit.week
        : ReportTrendUnit.month;

    final starts = <DateTime>[span.start];
    switch (unit) {
      case ReportTrendUnit.day:
        for (var i = 1; i < days; i++) {
          starts.add(_addDays(span.start, i));
        }
      case ReportTrendUnit.week:
        var next = _addDays(_weekStartOf(span.start, input), 7);
        while (!next.isAfter(span.end)) {
          starts.add(next);
          next = _addDays(next, 7);
        }
      case ReportTrendUnit.month:
        var next = DateTime.utc(span.start.year, span.start.month + 1, 1);
        while (!next.isAfter(span.end)) {
          starts.add(next);
          next = DateTime.utc(next.year, next.month + 1, 1);
        }
    }
    final happened = List<int>.filled(starts.length, 0);
    final missed = List<int>.filled(starts.length, 0);
    final perWeekday = List<int>.filled(8, 0);
    final startMinutes = <int>[];
    final spanStarts = <int>[];
    final spanEnds = <int>[];
    final firstWeek = _weekStartOf(span.start, input);
    for (final sample in countedSamples) {
      final event = input.events[sample.eventId]!;
      final day = sample.day;
      final index = switch (unit) {
        ReportTrendUnit.day => day.difference(span.start).inDays,
        ReportTrendUnit.week =>
          _weekStartOf(day, input).difference(firstWeek).inDays ~/ 7,
        ReportTrendUnit.month =>
          (day.year - span.start.year) * 12 + day.month - span.start.month,
      };
      if (_isMissed(sample, event)) {
        missed[index]++;
        continue;
      }
      happened[index]++;
      perWeekday[day.weekday]++;
      final time = event.time;
      if (time != null) {
        startMinutes.add(time.startMinute);
        final end = time.endMinute;
        if (end != null) {
          spanStarts.add(time.startMinute);
          spanEnds.add(end);
        }
      }
    }

    int? busiest;
    var most = 0;
    var tied = false;
    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
      final count = perWeekday[weekday];
      if (count > most) {
        most = count;
        busiest = weekday;
        tied = false;
      } else if (count == most && count > 0) {
        tied = true;
      }
    }
    // Both ends of the band come from the same occurrences, so "18:00 – 19:00"
    // never pairs one set's start with another's end; without enough of
    // those, the start alone from every timed one.
    const minBand = ReportMetrics.trendMinTimedForBand;
    final int? usualStart;
    final int? usualEnd;
    if (spanEnds.length >= minBand) {
      usualStart = _lowerMedian(spanStarts);
      usualEnd = _lowerMedian(spanEnds) % EventTime.minutesPerDay;
    } else {
      usualStart = startMinutes.length >= minBand
          ? _lowerMedian(startMinutes)
          : null;
      usualEnd = null;
    }
    return ReportTrend(
      unit: unit,
      buckets: List.unmodifiable([
        for (var i = 0; i < starts.length; i++)
          ReportTrendBucket(
            start: starts[i],
            happened: happened[i],
            missed: missed[i],
          ),
      ]),
      busiestWeekday: tied ? null : busiest,
      usualStartMinute: usualStart,
      usualEndMinute: usualEnd,
    );
  }

  /// The lower middle of an even count, so the band is a real minute some
  /// occurrence had, never a half-minute between two.
  static int _lowerMedian(List<int> values) {
    final sorted = [...values]..sort();
    return sorted[(sorted.length - 1) ~/ 2];
  }

  /// The first day of [day]'s week under the app's week start.
  static DateTime _weekStartOf(DateTime day, ReportInput input) {
    final back = (day.weekday - input.weekStart.weekday + 7) % 7;
    return _addDays(day, -back);
  }

  /// [samples] with every missed flag after [today] cleared — a day that has
  /// not come cannot have been missed, whatever an assume-absent default
  /// says, so Ahead never fades a row and a plan grades nothing — and, in a
  /// plan, every pending flag cleared, since a plan counts every occurrence.
  static List<ReportSample> _settled(
    List<ReportSample> samples,
    DateTime today, {
    required bool graded,
  }) {
    bool unsettled(ReportSample s) =>
        (s.missed && s.day.isAfter(today)) || (!graded && s.pending);
    if (!samples.any(unsettled)) return samples;
    return [
      for (final s in samples)
        unsettled(s)
            ? ReportSample(
                eventId: s.eventId,
                day: s.day,
                missed: s.missed && !s.day.isAfter(today),
              )
            : s,
    ];
  }

  /// The one routine test of the fold (§4.1), so the tiles, the totals and
  /// the rows can never disagree about which events are graded.
  static bool _isRoutine(CalendarEvent event) =>
      shapeOf(event) == ReportShape.routine;

  /// A pending occurrence has not happened yet, so it is never missed.
  static bool _isMissed(ReportSample sample, CalendarEvent event) =>
      sample.missed && !sample.pending && _isRoutine(event);

  static bool _holdsTasks(
    CalendarEvent event,
    Map<String, Map<DateTime, String>> overrides,
  ) {
    if (countTasks(event.description) != null) return true;
    if (!OccurrenceDescriptions.appliesTo(event)) return false;
    final days = overrides[event.id];
    return days != null && days.values.any((text) => countTasks(text) != null);
  }

  /// What [event] shows on [day] — `OccurrenceDescriptions.descriptionFor`'s
  /// rule over the sampler's texts: a present override wins, `''` included.
  static String? _textFor(
    CalendarEvent event,
    DateTime day,
    Map<String, Map<DateTime, String>> overrides,
  ) => overrides[event.id]?[day] ?? event.description;

  static String _categoryOf(ReportInput input, CalendarEvent event) =>
      input.categoryOf[event.id] ?? event.categoryId;

  static bool _contains(DateRange range, DateTime day) =>
      !day.isBefore(range.start) && !day.isAfter(range.end);

  static DateTime _addDays(DateTime day, int days) =>
      DateTime.utc(day.year, day.month, day.day + days);

  static bool _isDateOnly(DateTime day) =>
      day == DateTime.utc(day.year, day.month, day.day);
}

/// One category's running numbers while a fold walks its samples.
class _GroupTally {
  int count = 0;
  int minutes = 0;
  int missed = 0;
  final Map<String, _RoutineTally> routines = {};
  final List<ReportDatedRow> dated = [];
}

/// One routine's running numbers while a fold walks its samples.
class _RoutineTally {
  int attended = 0;
  int total = 0;
  int minutes = 0;

  // The samples arrive sorted by day, so the last one seen is the latest.
  DateTime? latestAttended;
  DateTime? latest;
}
