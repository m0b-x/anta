import 'dart:math' as math;

import '../constants/analytics_metrics.dart';
import '../constants/category_kinds.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/report_metrics.dart';
import '../models/calendar_event.dart';
import '../models/calendar_report.dart';
import '../models/category_profile.dart';
import '../models/date_range.dart';
import '../models/recurrence_rule.dart';
import 'report_insights.dart';
import 'tag_extractor.dart';
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
  ///
  /// Minutes count only in the categories whose effective profile counts
  /// hours, and include the confirmed counts-as of untimed days (I); a
  /// category absent from [profiles] folds unprofiled, so [categoryOf] and
  /// [profiles] left empty fold today's totals.
  static ReportTotals foldTotals({
    required DateRange counted,
    required Map<String, CalendarEvent> events,
    required Iterable<ReportSample> samples,
    required Map<String, Map<DateTime, String>> overrides,
    Map<String, String> categoryOf = const {},
    Map<String, EffectiveProfile> profiles = const {},
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
    var nominalKept = 0;
    var nominalAll = 0;
    final sharedCounted = <String>{};
    for (final sample in samples) {
      if (sample.pending || !_contains(counted, sample.day)) continue;
      final event = events[sample.eventId];
      if (event == null) continue;
      occurrences++;
      final graded = event.tracksPresence;
      final profile =
          profiles[categoryOf[event.id] ?? event.categoryId] ??
          EffectiveProfile.unprofiled;
      final (:minutes, :nominal) = profile.countsHours
          ? _minutesOf(event, profile)
          : (minutes: 0, nominal: 0);
      minutesAll += minutes;
      nominalAll += nominal;
      if (graded) tracked++;
      if (_isMissed(sample, event)) {
        missed++;
      } else {
        kept++;
        minutesKept += minutes;
        nominalKept += nominal;
        if (graded) attended++;
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
      nominalKept: nominalKept,
      nominalAll: nominalAll,
    );
  }

  /// The report of [input]'s span: counted from the span's start to today
  /// (or its end, when that comes first), the rest ahead; a span wholly
  /// after today is a plan, counted whole and graded on nothing (T). A
  /// pending sample (D31) is read as ahead in a graded span and as a plain
  /// occurrence in a plan. A [ReportFoldRole.compared] fold stops at what
  /// Compare reads; a main fold given [ReportInput.compared] carries it, and
  /// under last year its trend's outline and Balance's second bar. A main
  /// fold of a whole calendar year adds [CalendarReport.year] from the same
  /// walk.
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
    assert(
      input.billsAhead.every((s) => _isDateOnly(s.day)),
      'fold requires date-only UTC bills-ahead days',
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
      categoryOf: input.categoryOf,
      profiles: input.profiles,
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

    if (input.role == ReportFoldRole.main) {
      countedSamples.sort(byDay);
      aheadSamples.sort(byDay);
    } else {
      // A compared fold draws no row, so only the days' order counts — and
      // the sampler's scan already walks day by day: the within-day sort is
      // most of a compared fold's cost (§8 "Cost").
      _sortByDay(countedSamples);
      _sortByDay(aheadSamples);
    }

    final order = <String, int>{
      for (final (i, id) in input.categoryOrder.indexed) id: i,
    };

    final main = input.role == ReportFoldRole.main;
    final compared = main ? input.compared : null;
    final lastYear =
        compared != null && input.compare == ReportCompare.lastYear;
    var trend = graded && totals.kept >= ReportMetrics.trendMinOccurrences
        ? _trend(input, countedSamples)
        : null;
    if (lastYear && trend != null) {
      // A shifted span that loses 29 February can change the column unit
      // (183 → 182 days reads weeks, 32 → 31 days): index-aligned counts
      // under two units would compare a month with a week.
      if (compared.trend case final before? when before.unit == trend.unit) {
        trend = trend.withLastYear(
          List.unmodifiable([
            for (var i = 0; i < trend.buckets.length; i++)
              if (i < before.buckets.length) before.buckets[i].happened,
          ]),
        );
      }
    }
    // A year is a span like any other (S6 N), so however it was picked a
    // whole calendar year to today or past gains its aggregates; a plan has
    // kept nothing to rank.
    final wholeYear =
        main &&
        graded &&
        span.start == DateTime.utc(span.start.year, 1, 1) &&
        span.end == DateTime.utc(span.start.year, 12, 31);
    // `when` is a pattern keyword, so its variable takes another name.
    final (:measures, :tags, :goals, when: heatmap, :year) = _measures(
      input,
      countedSamples,
      aheadSamples,
      order,
      year: wholeYear ? _YearTally(span.start, input) : null,
    );
    final balance = _balance(input, measures);
    final money = Map<String, int>.unmodifiable({
      for (final MapEntry(key: eventId, value: net) in input.money.entries)
        if (net != 0 && events.containsKey(eventId)) eventId: net,
    });
    if (!main) {
      return CalendarReport(
        span: span,
        today: today,
        tense: tense,
        countedTo: countedTo,
        events: Map.unmodifiable(events),
        tiles: List.unmodifiable(_tiles(tense, input, totals)),
        skippedDays: input.skippedDays,
        aheadCount: aheadSamples.length,
        categories: const [],
        trend: trend,
        missed: const [],
        ahead: const [],
        measures: measures,
        nominalMinutes: graded ? totals.nominalKept : totals.nominalAll,
        balance: balance,
        when: heatmap,
        money: money,
        totals: totals,
      );
    }
    final due = _dueSoon(
      input,
      countedSamples,
      aheadSamples,
      goals,
      order,
      graded: graded,
    );
    final report = CalendarReport(
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
      measures: measures,
      tags: tags,
      nominalMinutes: graded ? totals.nominalKept : totals.nominalAll,
      workingDays: input.workingDays,
      publicHolidays: input.publicHolidays,
      goals: goals,
      dueSoon: due,
      balance: balance,
      when: heatmap,
      money: money,
      billsAhead: _billsAhead(input),
      compare: input.compare,
      compared: compared,
      balanceLastYear: lastYear ? compared.balance : null,
      totals: totals,
      year: year,
    );
    return report.withInsights(
      List.unmodifiable(ReportInsights.rank(report, input.profiles)),
    );
  }

  /// The eleven measures per category and the tags (H, Y, §6.3), the goals'
  /// period buckets (§8 "Cost") and the When cells, in one walk of the
  /// samples [fold] already sorted — [counted] by day, then [ahead] — so a
  /// day's tags and rows come oldest first and no scan runs twice. Only the
  /// lookback's and the lookahead's samples, which lie outside the span,
  /// take a walk of their own. Given a [year] tally, the same walk fills it
  /// and the year's aggregates come back with the rest (§6.12: nothing new
  /// is scanned).
  static ({
    Map<String, ReportMeasures> measures,
    List<ReportTag> tags,
    List<ReportGoal> goals,
    ReportWhen when,
    ReportYear? year,
  })
  _measures(
    ReportInput input,
    List<ReportSample> counted,
    List<ReportSample> ahead,
    Map<String, int> order, {
    _YearTally? year,
  }) {
    final today = input.today;
    final events = input.events;
    final tallies = <String, _MeasureTally>{};
    _MeasureTally tallyOf(String categoryId) =>
        tallies.putIfAbsent(categoryId, _MeasureTally.new);

    final byCategory = <String, List<CalendarEvent>>{};
    // What the walk reads of each event, resolved once: one lookup a sample
    // instead of four, on the path every fold — the compared one too — pays.
    final factsOf =
        <
          String,
          ({
            CalendarEvent event,
            String categoryId,
            _MeasureTally tally,
            EffectiveProfile profile,
            _EventYear? year,
          })
        >{};
    for (final event in events.values) {
      final categoryId = _categoryOf(input, event);
      (byCategory[categoryId] ??= []).add(event);
      final tally = tallyOf(categoryId);
      final profile = _profileOf(input, categoryId);
      factsOf[event.id] = (
        event: event,
        categoryId: categoryId,
        tally: tally,
        profile: profile,
        year: year?.eventOf(event, categoryId, profile.kind),
      );
      // The ledger's entry, not the link: with money off it holds nothing.
      if (input.money.containsKey(event.id)) tally.hasMoney = true;
    }

    // A compared fold reads no goal and no tag, so it pays for neither.
    final main = input.role == ReportFoldRole.main;
    final goalTallies = <String, _GoalTally>{};
    for (final MapEntry(key: categoryId, value: categoryEvents)
        in byCategory.entries) {
      final period = _profileOf(input, categoryId).target?.period;
      if (period == null || !main) continue;
      goalTallies[categoryId] = _goalTallyOf(input, period, categoryEvents);
    }

    // Money once per event, never per recurrence (P): the ledger's net is
    // the note's whole, read for an event whose start day is in the span —
    // and for a goal, in the period.
    final moneyOf = <String, int>{};
    for (final MapEntry(key: eventId, value: net) in input.money.entries) {
      final event = events[eventId];
      if (event == null || net == 0) continue;
      final start = _dateOnly(event.startDate);
      if (goalTallies[_categoryOf(input, event)] case final goal?) {
        if (goal.bucketAt(_periodIndexOf(goal, start, input)) case final b?) {
          if (net < 0) b.spentCents -= net;
          if (net > 0) b.receivedCents += net;
        }
      }
      if (!_contains(input.span, start)) continue;
      moneyOf[eventId] = net;
      final categoryId = _categoryOf(input, event);
      final tally = tallyOf(categoryId);
      if (net < 0) {
        tally.spentCents -= net;
      } else {
        tally.receivedCents += net;
      }
      year?.money(categoryId, start, net);
    }

    for (final sample in input.cancelled) {
      final event = events[sample.eventId];
      if (event == null) continue;
      final categoryId = _categoryOf(input, event);
      final tally = tallyOf(categoryId);
      tally.cancelled++;
      tally.planned++;
      year?.cancel(categoryId, sample.day);
    }

    final tags = <String, _TagTally>{};
    final ownTags = <String, List<({String key, String label})>>{};
    final sharedCounted = <String>{};
    final leadCounted = <String>{};
    void leadTime(CalendarEvent event, _MeasureTally tally) {
      final created = event.createdAt;
      if (created == null || event.rule is! OneTimeRecurrence) return;
      if (!leadCounted.add(event.id)) return;
      final days = _dateOnly(event.startDate)
          .difference(DateTime.utc(created.year, created.month, created.day))
          .inDays;
      // An event written after its day is a log, not a booking.
      if (days >= 0) tally.leadDays.add(days);
    }

    // Episodes run across the span's edges (D5), so an Episode category's
    // lookback is walked before the span and its lookahead after, each
    // window oldest first, then its span's days in the walk below; every
    // other category walks no episode at all, and pays no second walk of a
    // year of samples.
    void episodesOutside(Map<String, List<ReportSample>> windows) {
      for (final MapEntry(key: categoryId, value: window) in windows.entries) {
        final tally = tallies[categoryId];
        if (tally == null ||
            _profileOf(input, categoryId).kind != CategoryKind.episode) {
          continue;
        }
        for (final sample in window) {
          final event = events[sample.eventId];
          if (event == null ||
              !_isOutside(input, sample.day) ||
              _isMissed(sample, event)) {
            continue;
          }
          _episodeDay(tally, _epochDay(sample.day));
        }
      }
    }

    episodesOutside(input.lookback);
    final whenCells = List<int>.filled(ReportWhen.cellCount, 0);
    var timedDays = 0;
    // The categories with an occurrence up to today in the span, kept or
    // missed: a gap has something to measure.
    final occurred = <String>{};
    for (final sample in counted) {
      final (:event, :categoryId, :tally, :profile, year: eventYear) =
          factsOf[sample.eventId]!;
      final day = sample.day;
      final missed = _isMissed(sample, event);
      final past = !day.isAfter(today);
      final row = (day.weekday - input.weekStart.weekday + 7) % 7;
      leadTime(event, tally);
      if (past) {
        occurred.add(categoryId);
        tally.planned++;
        if (event.tracksPresence) {
          tally.tracked++;
          if (!missed) tally.attended++;
        }
      } else {
        tally.nextDay ??= day;
      }
      final ReportTaskCount? tasks;
      if (OccurrenceDescriptions.appliesTo(event)) {
        tasks = countTasks(_textFor(event, day, input.overrides));
      } else {
        tasks = sharedCounted.add(event.id)
            ? countTasks(event.description)
            : null;
      }
      if (tasks != null) {
        tally.tasksTicked += tasks.ticked;
        tally.tasksTotal += tasks.total;
      }
      final (:minutes, :nominal) = missed
          ? (minutes: 0, nominal: 0)
          : _minutesOf(event, profile);
      if (goalTallies[categoryId] case final goal?) {
        _addToGoal(
          input,
          goal,
          sample,
          event,
          missed: missed,
          minutes: minutes,
        );
      }
      if (missed) {
        tally.missedWeekdays[row]++;
        eventYear?.miss();
        continue;
      }

      tally.count++;
      tally.events.add(event.id);
      tally.minutes += minutes;
      tally.nominal += nominal;
      if (past) tally.lastSeen = day;
      // Day numbers, not dates: a week's key is its first day's number, so
      // the per-week maxima and the gaps allocate nothing per sample.
      final epochDay = _epochDay(day);
      final week = epochDay - row;
      if (tally.lastKeptDay case final last?) {
        final gap = epochDay - last - 1;
        if (gap > tally.longestGap) {
          tally.longestGap = gap;
          tally.longestGapFrom = last;
        }
      }
      tally.lastKeptDay = epochDay;
      if (eventYear != null) {
        year!.keep(eventYear, day, epochDay, week, minutes: minutes);
      }
      if (day.weekday >= DateTime.saturday) tally.weekendMinutes += minutes;
      if (past && profile.kind == CategoryKind.episode) {
        _episodeDay(tally, epochDay);
      }
      final time = event.time;
      if (time != null) {
        tally.startMinutes.add(time.startMinute);
        final end = time.endMinute;
        if (end != null && end > AnalyticsMetrics.workLateMinute) {
          tally.lateDays++;
          tally.lateWeeks.add(week);
        }
        final duration = time.durationMinutes;
        if (duration != null &&
            duration >= AnalyticsMetrics.sleepNightMinMinutes &&
            duration < AnalyticsMetrics.sleepShortMinutes) {
          tally.shortWeeks.add(week);
        }
      }
      tally.weekdays[row]++;
      // When shows where the waking hours go: the counts-hours rule Balance
      // follows, and never Sleep, whose eight hours a night would bury
      // every other cell.
      if (time
          case EventTime(:final startMinute, durationMinutes: final duration?)
          when duration > 0 &&
              profile.countsHours &&
              profile.kind != CategoryKind.sleep) {
        timedDays++;
        _fillWhen(
          whenCells,
          row * EventTime.minutesPerDay + startMinute,
          duration,
        );
      }
      if (!main) continue;

      // Nothing is built for an untagged day (§8 "Cost": thousands of kept
      // samples): the event's own tags are keyed once, and a per-day set
      // exists only when the day's own text adds tags.
      final own = ownTags[event.id] ??= _ownTagsOf(event);
      final dayOwn = extractTags(input.overrides[event.id]?[day]);
      if (own.isEmpty && dayOwn.isEmpty) continue;
      for (final (:key, :label) in own) {
        _tallyTag(
          input,
          tags[key] ??= _TagTally(label),
          sample,
          event,
          categoryId,
          minutes: minutes,
          past: past,
          net: moneyOf[event.id],
        );
      }
      if (dayOwn.isEmpty) continue;
      final keys = {for (final (:key, label: _) in own) key};
      for (final label in dayOwn) {
        final key = label.toLowerCase();
        if (!keys.add(key)) continue;
        _tallyTag(
          input,
          tags[key] ??= _TagTally(label),
          sample,
          event,
          categoryId,
          minutes: minutes,
          past: past,
          net: moneyOf[event.id],
        );
      }
    }
    // Every ahead sample is still to come, today's pending one first: it is
    // the next occurrence, so an Expiry due today reads 0 days.
    for (final sample in ahead) {
      final event = events[sample.eventId]!;
      final tally = tallyOf(_categoryOf(input, event));
      leadTime(event, tally);
      tally.nextDay ??= sample.day;
    }
    episodesOutside(input.lookahead);
    for (final MapEntry(key: categoryId, value: goal) in goalTallies.entries) {
      final profile = _profileOf(input, categoryId);
      // Plain loops, not [_outside]'s chain: a year of daily samples per
      // goal walks here (§8 "Cost").
      for (final window in [
        ?input.lookback[categoryId],
        ?input.lookahead[categoryId],
      ]) {
        for (final sample in window) {
          final event = events[sample.eventId];
          if (event == null || !_isOutside(input, sample.day)) continue;
          final missed = _isMissed(sample, event);
          _addToGoal(
            input,
            goal,
            sample,
            event,
            missed: missed,
            minutes: missed ? 0 : _minutesOf(event, profile).minutes,
          );
        }
      }
    }

    int byOrder(String a, String b) {
      final byIndex = (order[a] ?? order.length).compareTo(
        order[b] ?? order.length,
      );
      return byIndex != 0 ? byIndex : a.compareTo(b);
    }

    final categoryIds = byCategory.keys.toList()..sort(byOrder);
    final measures = <String, ReportMeasures>{
      for (final categoryId in categoryIds)
        categoryId: _measuresOf(
          input,
          categoryId,
          byCategory[categoryId]!,
          tallies[categoryId]!,
        ),
    };

    for (final tag in tags.values) {
      tag.categoryIds.sort(byOrder);
    }
    final tagList = [
      for (final MapEntry(:key, value: tag) in tags.entries)
        if (_tagKindOf(input, tag.categoryIds) case (
          :final kind,
          :final categoryId,
        ))
          ReportTag(
            key: key,
            label: tag.label,
            events: tag.events.length,
            count: tag.count,
            minutes: tag.minutes,
            spentCents: tag.spentCents,
            receivedCents: tag.receivedCents,
            lastSeenDay: tag.lastSeen,
            categoryIds: List.unmodifiable(tag.categoryIds),
            kind: kind,
            kindCategoryId: categoryId,
            rows: List.unmodifiable(tag.rows),
            medianGapDays: tag.gaps.isEmpty ? null : _lowerMedian(tag.gaps),
          ),
    ];
    tagList.sort((a, b) {
      final byEvents = b.events.compareTo(a.events);
      if (byEvents != 0) return byEvents;
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
    final goals = [
      for (final categoryId in main ? categoryIds : const <String>[])
        if (_profileOf(input, categoryId).target case final target?)
          _goalOf(
            input,
            categoryId,
            target,
            measures[categoryId]!,
            goalTallies[categoryId],
            occurred:
                occurred.contains(categoryId) ||
                _outside(input, categoryId).isNotEmpty,
          ),
    ];
    return (
      measures: Map.unmodifiable(measures),
      tags: List.unmodifiable(tagList),
      goals: List.unmodifiable(goals),
      when: _when(whenCells, timedDays),
      year: year == null
          ? null
          : _year(
              input,
              year,
              categoryIds,
              measures,
              tallies,
              goals,
              goalTallies,
            ),
    );
  }

  /// The year's aggregates from its [year] tally (§6.12, S6 §2.8): the
  /// records in [ReportRecordKind]'s order, then per category in
  /// [categoryIds]' order its months, its kept span and its goal's tally,
  /// counted from its [periods]' `streakFrom`.
  static ReportYear _year(
    ReportInput input,
    _YearTally year,
    List<String> categoryIds,
    Map<String, ReportMeasures> measures,
    Map<String, _MeasureTally> tallies,
    List<ReportGoal> goals,
    Map<String, _GoalTally> periods,
  ) {
    final first = input.span.start;
    final lastOfYear = DateTime.utc(first.year, 12, 31);
    final records = <ReportRecord>[];
    // The earliest of the largest: a later month only wins by more.
    void month(ReportRecordKind kind, List<int> values) {
      var best = 0;
      for (var m = 1; m < values.length; m++) {
        if (values[m] > values[best]) best = m;
      }
      if (values[best] == 0) return;
      // A spend under half a unit would read "June · 0": no record.
      if (kind == ReportRecordKind.moneyMonth &&
          (values[best] / 100).round() == 0) {
        return;
      }
      records.add(
        ReportRecord(
          kind: kind,
          value: values[best],
          start: DateTime.utc(first.year, best + 1, 1),
          end: DateTime.utc(first.year, best + 2, 0),
        ),
      );
    }

    month(ReportRecordKind.busiestMonth, year.kept);
    var week = 0;
    for (var w = 1; w < year.weeks.length; w++) {
      if (year.weeks[w] > year.weeks[week]) week = w;
    }
    if (year.weeks[week] > 0) {
      final start = _addDays(first, year.firstWeekOffset + week * 7);
      final end = _addDays(start, 6);
      records.add(
        ReportRecord(
          kind: ReportRecordKind.busiestWeek,
          value: year.weeks[week],
          start: start,
          end: end.isAfter(lastOfYear) ? lastOfYear : end,
        ),
      );
    }
    month(ReportRecordKind.socialMonth, year.social);
    month(ReportRecordKind.moneyMonth, year.spent);

    ReportRecord runRecord(ReportRecordKind kind, _Run run) => ReportRecord(
      kind: kind,
      categoryId: run.categoryId,
      eventId: run.eventId,
      value: run.length,
      start: _fromEpochDay(run.start),
      end: _fromEpochDay(run.last),
    );
    // Longest, then earliest, then the walk's order: the one sort every
    // run record takes, since `List.sort` keeps no order of its own.
    int byRun(_Run a, _Run b) {
      final byLength = b.length.compareTo(a.length);
      if (byLength != 0) return byLength;
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.order.compareTo(b.order);
    }

    _Run? trip;
    for (final run in year.trips()) {
      if (trip == null || byRun(run, trip) < 0) trip = run;
    }
    if (trip != null) {
      records.add(runRecord(ReportRecordKind.longestTrip, trip));
    }
    final streaks = [
      for (final run in year.streaks())
        if (run.length >= AnalyticsMetrics.recordStreakMin) run,
    ]..sort(byRun);
    for (final run in streaks) {
      records.add(runRecord(ReportRecordKind.longestStreak, run));
    }
    final gaps = <(int, ReportRecord)>[];
    for (final (i, categoryId) in categoryIds.indexed) {
      final tally = tallies[categoryId]!;
      final from = tally.longestGapFrom;
      if (_profileOf(input, categoryId).target?.kind != TargetKind.maxGap ||
          from == null) {
        continue;
      }
      gaps.add((
        i,
        ReportRecord(
          kind: ReportRecordKind.longestGap,
          categoryId: categoryId,
          value: tally.longestGap,
          start: _fromEpochDay(from),
          end: _fromEpochDay(from + tally.longestGap + 1),
        ),
      ));
    }
    gaps.sort((a, b) {
      final byValue = b.$2.value.compareTo(a.$2.value);
      if (byValue != 0) return byValue;
      final byStart = a.$2.start.compareTo(b.$2.start);
      return byStart != 0 ? byStart : a.$1.compareTo(b.$1);
    });
    records.addAll([for (final (_, record) in gaps) record]);

    final months = <String, List<int>>{};
    final spans = <String, ({DateTime first, DateTime last})>{};
    for (final categoryId in categoryIds) {
      final category = year.categories[categoryId];
      final kept = category?.first;
      if (category == null || kept == null) continue;
      final income = _profileOf(input, categoryId).kind == CategoryKind.income;
      months[categoryId] = List.unmodifiable(
        switch (measures[categoryId]!.primary) {
          ReportMeasure.events => category.events,
          ReportMeasure.hours => category.minutes,
          ReportMeasure.attendance => category.attended,
          ReportMeasure.cancelled => category.cancelled,
          ReportMeasure.money =>
            income ? category.receivedCents : category.spentCents,
          _ => category.kept,
        },
      );
      spans[categoryId] = (
        first: _fromEpochDay(kept),
        last: _fromEpochDay(category.last),
      );
    }

    final goalTallies = <String, ReportGoalTally>{};
    for (final goal in goals) {
      final period = goal.target.period;
      if (period == null || period == TargetPeriod.year) continue;
      // The bound the goal's own streak reads: a budget begun in July never
      // met the weeks before it existed.
      final from = periods[goal.categoryId]?.streakFrom ?? first;
      var met = 0;
      var closed = 0;
      var run = 0;
      var longest = 0;
      for (final p in goal.periods) {
        // A week begun in December belongs to the year before, as on the
        // Records' busiest week; a period ending today is still open.
        if (p.start.isBefore(first) ||
            p.start.isBefore(from) ||
            !p.end.isBefore(input.today)) {
          continue;
        }
        closed++;
        if (p.state == GoalState.met) {
          met++;
          if (++run > longest) longest = run;
        } else {
          run = 0;
        }
      }
      goalTallies[goal.categoryId] = ReportGoalTally(
        met: met,
        closed: closed,
        longestStreak: longest,
      );
    }

    return ReportYear(
      records: List.unmodifiable(records),
      months: Map.unmodifiable(months),
      spans: Map.unmodifiable(spans),
      goalTallies: Map.unmodifiable(goalTallies),
    );
  }

  /// A category's goal tally: one bucket per period from the earliest the
  /// streak may read — the first whole period inside the lookback, never
  /// one before the category's first event — or the span's first period,
  /// whichever comes first, to the period holding the counted range's end.
  static _GoalTally _goalTallyOf(
    ReportInput input,
    TargetPeriod period,
    List<CalendarEvent> events,
  ) {
    final span = input.span;
    final countedTo = CalendarReport.countedToOf(
      span: span,
      today: input.today,
    );
    final spanFirst = _periodStartOf(period, span.start, input);
    final last = _periodStartOf(period, countedTo, input);
    final lookbackFrom = _addDays(span.start, -AnalyticsMetrics.lookbackDays);
    var streakFrom = _periodStartOf(period, lookbackFrom, input);
    if (streakFrom.isBefore(lookbackFrom)) {
      streakFrom = _nextPeriodOf(period, streakFrom);
    }
    var firstDay = _dateOnly(events.first.startDate);
    for (final event in events.skip(1)) {
      final start = _dateOnly(event.startDate);
      if (start.isBefore(firstDay)) firstDay = start;
    }
    final firstPeriod = _periodStartOf(period, firstDay, input);
    if (firstPeriod.isAfter(streakFrom)) streakFrom = firstPeriod;
    final base = streakFrom.isBefore(spanFirst) ? streakFrom : spanFirst;
    return _GoalTally(
      period: period,
      base: base,
      streakFrom: streakFrom,
      spanFirst: spanFirst,
      length: _periodsBetween(period, base, last) + 1,
    );
  }

  /// Adds one sample to its period's bucket: a period that has begun counts
  /// what was kept to today, a future one what is planned in it. Tasks follow
  /// D27 per period — a shared text once per period, a per-day text per day
  /// — and count on a missed day as the measures do.
  static void _addToGoal(
    ReportInput input,
    _GoalTally goal,
    ReportSample sample,
    CalendarEvent event, {
    required bool missed,
    required int minutes,
  }) {
    final today = input.today;
    final day = sample.day;
    if (day != goal.lastDay) {
      final start = _periodStartOf(goal.period, day, input);
      goal
        ..lastDay = day
        ..lastStart = start
        ..lastIndex = _periodsBetween(goal.period, goal.base, start);
    }
    if (day.isAfter(today) && !goal.lastStart!.isAfter(today)) return;
    final bucket = goal.bucketAt(goal.lastIndex);
    if (bucket == null) return;
    final ReportTaskCount? tasks;
    if (OccurrenceDescriptions.appliesTo(event)) {
      tasks = countTasks(_textFor(event, day, input.overrides));
    } else {
      tasks = bucket.sharedCounted.add(event.id)
          ? countTasks(event.description)
          : null;
    }
    if (tasks != null) bucket.tasksTicked += tasks.ticked;
    if (missed) return;
    bucket.count++;
    bucket.events.add(event.id);
    bucket.minutes += minutes;
    if (event.tracksPresence && !day.isAfter(today)) bucket.attended++;
  }

  /// The goal [target] sets on [categoryId] (§6.6, K): a gap reading for a
  /// *max gap*, else its periods judged and the streak counted.
  ///
  /// A gap whose category never [occurred] up to today — in the span, the
  /// lookback or the lookahead — has nothing to measure and reads no gap;
  /// one that occurred with no kept day in that window reads the lookback's
  /// length as a floor, so a service last done 400 days ago is overdue.
  static ReportGoal _goalOf(
    ReportInput input,
    String categoryId,
    ReportTarget target,
    ReportMeasures measures,
    _GoalTally? tally, {
    required bool occurred,
  }) {
    final today = input.today;
    if (tally == null) {
      final seen = measures.lastSeenDays;
      final since = seen ?? AnalyticsMetrics.lookbackDays;
      final limit = target.value;
      return ReportGoal(
        categoryId: categoryId,
        measure: measures.primary,
        target: target,
        gap: seen == null && !occurred
            ? null
            : ReportGapState(
                daysSince: since,
                limit: limit,
                state: since > limit
                    ? GapState.overdue
                    : since >= limit * (1 - AnalyticsMetrics.gapDueFraction)
                    ? GapState.due
                    : GapState.within,
                beyondLookback: seen == null,
              ),
      );
    }
    final period = tally.period;
    final periods = <ReportGoalPeriod>[];
    var streak = 0;
    var broken = 0;
    var start = tally.base;
    for (var i = 0; i < tally.buckets.length; i++) {
      final end = _periodEndOf(period, start);
      final days = end.difference(start).inDays + 1;
      final elapsed = end.isBefore(today)
          ? days
          : start.isAfter(today)
          ? 0
          : today.difference(start).inDays + 1;
      final value = _goalValue(measures.primary, target.kind, tally.buckets[i]);
      final expected = (target.value * elapsed + days - 1) ~/ days;
      final state = _goalState(target, value, expected, start, end, today);
      // A past span's last period running past its end is exact too: the
      // lookahead sampled its later days, so it is judged like any other.
      if (end.isBefore(today) && !start.isBefore(tally.streakFrom)) {
        broken = state == GoalState.met ? 0 : streak;
        streak = state == GoalState.met ? streak + 1 : 0;
      }
      if (!start.isBefore(tally.spanFirst)) {
        periods.add(
          ReportGoalPeriod(
            start: start,
            end: end,
            value: value,
            expected: expected,
            state: state,
          ),
        );
      }
      start = _addDays(end, 1);
    }
    return ReportGoal(
      categoryId: categoryId,
      measure: measures.primary,
      target: target,
      periods: List.unmodifiable(periods),
      streak: streak,
      brokenStreak: broken,
    );
  }

  /// A period's value in the goal's unit. Money spends for a budget and an
  /// *at most* cap, and receives for an *at least*; a primary with no period
  /// value of its own (Cancelled, Last seen, Lead time, Timing, Days until)
  /// counts kept days.
  static int _goalValue(
    ReportMeasure measure,
    TargetKind kind,
    _PeriodTally? tally,
  ) {
    if (tally == null) return 0;
    return switch (measure) {
      ReportMeasure.events => tally.events.length,
      ReportMeasure.hours => tally.minutes,
      ReportMeasure.attendance => tally.attended,
      ReportMeasure.tasks => tally.tasksTicked,
      ReportMeasure.money =>
        kind == TargetKind.atLeast ? tally.receivedCents : tally.spentCents,
      _ => tally.count,
    };
  }

  /// One period's state (§6.6, K); a *max gap* never has periods, so only
  /// *at least* reads differently from the caps.
  static GoalState _goalState(
    ReportTarget target,
    int value,
    int expected,
    DateTime start,
    DateTime end,
    DateTime today,
  ) {
    if (start.isAfter(today)) return GoalState.future;
    final closed = end.isBefore(today);
    if (!closed && start == today && value == 0) return GoalState.notDue;
    final limit = target.value;
    if (target.kind == TargetKind.atLeast) {
      if (value >= limit) return GoalState.met;
      if (closed) return GoalState.missed;
      return value >= expected ? GoalState.onPace : GoalState.behind;
    }
    if (value > limit) return GoalState.over;
    if (closed) return GoalState.met;
    return value <= expected ? GoalState.onPace : GoalState.behind;
  }

  /// Every Due soon row (§6.8, O), ordered; the page caps. Graded: the gap
  /// goals due or overdue; an Expiry's next day inside
  /// `AnalyticsMetrics.expiryWarnDays` — from the span's samples, else a
  /// one-off's day past the span's end (the fold never scans) — and its
  /// missed days; a Bill's or a Deadline's missed days. A plan lists the
  /// span's Expiry and Bill days as upcoming, nothing else.
  static List<ReportDueRow> _dueSoon(
    ReportInput input,
    List<ReportSample> counted,
    List<ReportSample> ahead,
    List<ReportGoal> goals,
    Map<String, int> order, {
    required bool graded,
  }) {
    final today = input.today;
    final events = input.events;
    final rows = <ReportDueRow>[];
    CategoryKind kindOf(String categoryId) =>
        _profileOf(input, categoryId).kind;

    if (!graded) {
      for (final sample in counted) {
        final categoryId = _categoryOf(input, events[sample.eventId]!);
        final kind = kindOf(categoryId);
        if (kind != CategoryKind.expiry && kind != CategoryKind.bill) continue;
        rows.add(
          ReportDueRow(
            categoryId: categoryId,
            eventId: sample.eventId,
            day: sample.day,
            kind: kind == CategoryKind.expiry
                ? ReportDueKind.expiry
                : ReportDueKind.upcoming,
            state: ReportDueState.upcoming,
            days: sample.day.difference(today).inDays,
          ),
        );
      }
    } else {
      for (final goal in goals) {
        final gap = goal.gap;
        if (gap == null || gap.state == GapState.within) continue;
        final since = gap.daysSince;
        final lastKept = _addDays(today, -since);
        final overdue = gap.state == GapState.overdue;
        rows.add(
          ReportDueRow(
            categoryId: goal.categoryId,
            eventId: _keptOn(input, goal.categoryId, lastKept, counted),
            day: _addDays(lastKept, gap.limit),
            kind: ReportDueKind.gap,
            state: overdue ? ReportDueState.overdue : ReportDueState.due,
            days: overdue ? since - gap.limit : gap.limit - since,
            beyondLookback: gap.beyondLookback,
          ),
        );
      }

      final upcoming = <String>{};
      void expiresOn(CalendarEvent event, String categoryId, DateTime day) {
        final days = day.difference(today).inDays;
        if (days > AnalyticsMetrics.expiryWarnDays) return;
        if (!upcoming.add(event.id)) return;
        rows.add(
          ReportDueRow(
            categoryId: categoryId,
            eventId: event.id,
            day: day,
            kind: ReportDueKind.expiry,
            state: ReportDueState.upcoming,
            days: days,
          ),
        );
      }

      for (final sample in [...counted, ...ahead]) {
        final event = events[sample.eventId]!;
        final categoryId = _categoryOf(input, event);
        final kind = kindOf(categoryId);
        final day = sample.day;
        if (_isMissed(sample, event)) {
          final unmarked =
              kind == CategoryKind.bill || kind == CategoryKind.deadline;
          if (kind != CategoryKind.expiry && !unmarked) continue;
          rows.add(
            ReportDueRow(
              categoryId: categoryId,
              eventId: event.id,
              day: day,
              kind: unmarked ? ReportDueKind.unmarked : ReportDueKind.expiry,
              state: unmarked
                  ? ReportDueState.unmarked
                  : ReportDueState.overdue,
              days: today.difference(day).inDays,
            ),
          );
        } else if (kind == CategoryKind.expiry && !day.isBefore(today)) {
          expiresOn(event, categoryId, day);
        }
      }
      for (final event in events.values) {
        final categoryId = _categoryOf(input, event);
        if (kindOf(categoryId) != CategoryKind.expiry ||
            event.rule is! OneTimeRecurrence) {
          continue;
        }
        final day = _dateOnly(event.startDate);
        if (day.isAfter(input.span.end) && !day.isBefore(today)) {
          expiresOn(event, categoryId, day);
        }
      }
    }

    // The most urgent first: an overdue row the longest past, every other
    // state the soonest.
    rows.sort((a, b) {
      final byState = a.state.index.compareTo(b.state.index);
      if (byState != 0) return byState;
      final byDays = a.state == ReportDueState.overdue
          ? b.days.compareTo(a.days)
          : a.days.compareTo(b.days);
      if (byDays != 0) return byDays;
      final byOrder = (order[a.categoryId] ?? order.length).compareTo(
        order[b.categoryId] ?? order.length,
      );
      if (byOrder != 0) return byOrder;
      final byDay = a.day.compareTo(b.day);
      return byDay != 0 ? byDay : a.eventId.compareTo(b.eventId);
    });
    return List.unmodifiable(rows);
  }

  /// [ReportInput.billsAhead]'s events by resolved Bill-kind category, each
  /// once, in the order they first occur — M1 sums an event's money once,
  /// whatever its occurrences (P).
  static Map<String, List<String>> _billsAhead(ReportInput input) {
    final byCategory = <String, List<String>>{};
    final seen = <String>{};
    for (final sample in input.billsAhead) {
      final event = input.events[sample.eventId];
      if (event == null || !seen.add(event.id)) continue;
      final categoryId = _categoryOf(input, event);
      if (_profileOf(input, categoryId).kind != CategoryKind.bill) continue;
      (byCategory[categoryId] ??= []).add(event.id);
    }
    return Map.unmodifiable({
      for (final MapEntry(:key, :value) in byCategory.entries)
        key: List<String>.unmodifiable(value),
    });
  }

  /// The event of [categoryId] kept on [day], from the lookahead, the span's
  /// samples or the lookback; failing all three — a last-seen day handed
  /// over without its samples, or the floor of a gap beyond the lookback —
  /// the category's first event by id.
  static String _keptOn(
    ReportInput input,
    String categoryId,
    DateTime day,
    List<ReportSample> counted,
  ) {
    final events = input.events;
    for (final sample in [
      ...?input.lookahead[categoryId]?.reversed,
      ...counted.reversed,
      ...?input.lookback[categoryId]?.reversed,
    ]) {
      final event = events[sample.eventId];
      if (event == null || sample.day != day) continue;
      if (_categoryOf(input, event) == categoryId &&
          !_isMissed(sample, event)) {
        return event.id;
      }
    }
    return ([
      for (final event in events.values)
        if (_categoryOf(input, event) == categoryId) event.id,
    ]..sort()).first;
  }

  /// Balance (§6.10, M): the categories whose hours count add their minutes,
  /// counts-as included, to their area; Sleep's row counts none.
  static Map<LifeArea, int> _balance(
    ReportInput input,
    Map<String, ReportMeasures> measures,
  ) {
    final minutes = List<int>.filled(LifeArea.values.length, 0);
    for (final measure in measures.values) {
      final profile = _profileOf(input, measure.categoryId);
      if (profile.countsHours) minutes[profile.area.index] += measure.minutes;
    }
    return Map.unmodifiable({
      for (final area in LifeArea.values)
        if (minutes[area.index] > 0) area: minutes[area.index],
    });
  }

  /// Adds [duration] minutes from [minuteOfWeek] (row × day + start) to the
  /// hour cells they cover, wrapping from the week's last row to its first.
  static void _fillWhen(List<int> cells, int minuteOfWeek, int duration) {
    var minute = minuteOfWeek;
    var left = duration;
    while (left > 0) {
      final take = 60 - minute % 60 < left ? 60 - minute % 60 : left;
      cells[(minute ~/ 60) % ReportWhen.cellCount] += take;
      minute += take;
      left -= take;
    }
  }

  static ReportWhen _when(List<int> cells, int timedDays) {
    if (timedDays < AnalyticsMetrics.whenMinTimedSamples) {
      return ReportWhen(cells: List.unmodifiable(cells), timedDays: timedDays);
    }
    const hours = ReportWhen.hoursPerDay;
    final rows = List<int>.filled(cells.length ~/ hours, 0);
    final columns = List<int>.filled(hours, 0);
    for (var i = 0; i < cells.length; i++) {
      rows[i ~/ hours] += cells[i];
      columns[i % hours] += cells[i];
    }
    int firstMax(List<int> values) {
      var best = 0;
      for (var i = 1; i < values.length; i++) {
        if (values[i] > values[best]) best = i;
      }
      return best;
    }

    return ReportWhen(
      cells: List.unmodifiable(cells),
      timedDays: timedDays,
      busiestWeekday: firstMax(rows),
      busiestHour: firstMax(columns),
    );
  }

  /// The first day of [period] holding [day].
  static DateTime _periodStartOf(
    TargetPeriod period,
    DateTime day,
    ReportInput input,
  ) => switch (period) {
    TargetPeriod.day => day,
    TargetPeriod.week => _weekStartOf(day, input),
    TargetPeriod.month => DateTime.utc(day.year, day.month, 1),
    TargetPeriod.year => DateTime.utc(day.year, 1, 1),
  };

  /// The last day of the [period] that starts on [start].
  static DateTime _periodEndOf(TargetPeriod period, DateTime start) =>
      switch (period) {
        TargetPeriod.day => start,
        TargetPeriod.week => _addDays(start, 6),
        TargetPeriod.month => DateTime.utc(start.year, start.month + 1, 0),
        TargetPeriod.year => DateTime.utc(start.year, 12, 31),
      };

  static DateTime _nextPeriodOf(TargetPeriod period, DateTime start) =>
      _addDays(_periodEndOf(period, start), 1);

  /// Whole periods from [base] to [start], both a period's first day — the
  /// bucket index, by calendar fields for months and years.
  static int _periodsBetween(
    TargetPeriod period,
    DateTime base,
    DateTime start,
  ) => switch (period) {
    TargetPeriod.day => start.difference(base).inDays,
    TargetPeriod.week => start.difference(base).inDays ~/ 7,
    TargetPeriod.month =>
      (start.year - base.year) * 12 + start.month - base.month,
    TargetPeriod.year => start.year - base.year,
  };

  static int _periodIndexOf(_GoalTally goal, DateTime day, ReportInput input) =>
      _periodsBetween(
        goal.period,
        goal.base,
        _periodStartOf(goal.period, day, input),
      );

  /// One category's measures from its tally, its primary resolved: the
  /// profile's, else Auto (§6.2) over [events] — Auto's "all repeats" and
  /// its last rule both read Count, so they share one branch — then the
  /// fallback when the chosen measure has no source over the span.
  static ReportMeasures _measuresOf(
    ReportInput input,
    String categoryId,
    List<CalendarEvent> events,
    _MeasureTally tally,
  ) {
    final today = input.today;
    final profile = _profileOf(input, categoryId);
    final chosen =
        profile.primary ??
        (events.every((e) => e.tracksPresence)
            ? ReportMeasure.attendance
            : events.any((e) => e.time?.durationMinutes != null) ||
                  profile.nominalMinutes != null
            ? ReportMeasure.hours
            : events.any((e) => _holdsTasks(e, input.overrides))
            ? ReportMeasure.tasks
            : ReportMeasure.count);
    final unsourced =
        (chosen == ReportMeasure.tasks && tally.tasksTotal == 0) ||
        (chosen == ReportMeasure.money && !tally.hasMoney);
    final lastSeen =
        _lastKeptAfterSpan(input, categoryId) ??
        tally.lastSeen ??
        input.lastSeenBefore[categoryId];
    final next = tally.nextDay;
    final episodes = tally.episodes;
    final mean = episodes < 2 ? null : tally.gapSum / (episodes - 1);
    final variance = mean == null
        ? null
        : tally.gapSquares / (episodes - 1) - mean * mean;
    final lastEpisode = tally.lastEpisode;
    // Sorted once, in place: the median and the bedtime spread read the
    // same order.
    final starts = tally.startMinutes..sort();
    return ReportMeasures(
      categoryId: categoryId,
      primary: unsourced
          ? profile.primaryFallback ?? ReportMeasure.count
          : chosen,
      fallbackApplied: unsourced,
      count: tally.count,
      events: tally.events.length,
      minutes: tally.minutes,
      nominalMinutes: tally.nominal,
      attended: tally.attended,
      tracked: tally.tracked,
      cancelled: tally.cancelled,
      planned: tally.planned,
      tasksTicked: tally.tasksTicked,
      tasksTotal: tally.tasksTotal,
      spentCents: tally.spentCents,
      receivedCents: tally.receivedCents,
      hasMoney: tally.hasMoney,
      lastSeenDay: lastSeen,
      lastSeenDays: lastSeen == null ? null : today.difference(lastSeen).inDays,
      leadTimeDays: tally.leadDays.isEmpty
          ? null
          : _lowerMedian(tally.leadDays),
      medianStartMinute: starts.isEmpty
          ? null
          : starts[(starts.length - 1) ~/ 2],
      lateDays: tally.lateDays,
      weekdayHistogram: List.unmodifiable(tally.weekdays),
      daysUntil: next?.difference(today).inDays,
      nextDay: next,
      profiled: !profile.isUnprofiled,
      leadTimeEvents: tally.leadDays.length,
      missedByWeekday: List.unmodifiable(tally.missedWeekdays),
      maxLateDaysInAWeek: tally.lateWeeks.max,
      weekendMinutes: tally.weekendMinutes,
      maxShortDaysInAWeek: tally.shortWeeks.max,
      startMinuteSpread: profile.kind == CategoryKind.sleep
          ? _startSpread(starts)
          : 0,
      longestGapDays: tally.longestGap,
      episodes: episodes,
      lastEpisodeDay: lastEpisode == null
          ? null
          : DateTime.utc(1970, 1, 1 + lastEpisode),
      episodeGapMean: mean,
      // Rounding can leave a hair below zero when every gap is equal.
      episodeGapCv: mean == null
          ? null
          : math.sqrt(math.max(0.0, variance!)) / mean,
    );
  }

  /// P3's bedtime spread over the ascending [sorted] starts: the minutes
  /// from the 10th to the 90th percentile (nearest rank, the
  /// [AnalyticsMetrics.bedtimeSpreadTrim] share left out at each end) on the
  /// shortest arc of the day — the starts read from just after the widest
  /// empty stretch between two neighbours, the one across midnight
  /// included, so 23:30 and 00:30 are 60 apart, never 1,380, and one late
  /// night in thirty is no spread. 0 under two.
  static int _startSpread(List<int> sorted) {
    final n = sorted.length;
    if (n < 2) return 0;
    var from = 0;
    var widest = sorted.first + EventTime.minutesPerDay - sorted.last;
    for (var i = 1; i < n; i++) {
      final empty = sorted[i] - sorted[i - 1];
      if (empty > widest) {
        widest = empty;
        from = i;
      }
    }
    final trim = (AnalyticsMetrics.bedtimeSpreadTrim * (n - 1)).round();
    final low = sorted[(from + trim) % n];
    final high = sorted[(from + n - 1 - trim) % n];
    return (high - low + EventTime.minutesPerDay) % EventTime.minutesPerDay;
  }

  /// One kept day up to today of the category [tally] counts (D5): it
  /// starts an episode unless the category was kept the day before or
  /// already that day — a run of consecutive kept days is one episode
  /// whichever events cover it, so two overlapping events never read as
  /// two. The days arrive oldest first: the lookback, the span, the
  /// lookahead.
  static void _episodeDay(_MeasureTally tally, int epochDay) {
    final last = tally.lastRunDay;
    tally.lastRunDay = epochDay;
    if (last != null && epochDay - last <= 1) return;
    final previous = tally.lastEpisode;
    if (previous != null) {
      final gap = epochDay - previous;
      tally.gapSum += gap;
      tally.gapSquares += gap * gap;
    }
    tally.episodes++;
    tally.lastEpisode = epochDay;
  }

  /// [day]'s number counted from 1 January 1970 — exact for a date-only UTC
  /// day, so differences are whole days with no `DateTime` built.
  static int _epochDay(DateTime day) =>
      day.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  /// The date-only UTC day [_epochDay] numbered [epochDay].
  static DateTime _fromEpochDay(int epochDay) =>
      DateTime.utc(1970, 1, 1 + epochDay);

  /// One occurrence's minutes under [profile]: its duration when it has one,
  /// else the confirmed counts-as (I) — never on a repeat (an Anniversary is
  /// no time spent) nor on Sleep, whose hours are its own card's.
  static ({int minutes, int nominal}) _minutesOf(
    CalendarEvent event,
    EffectiveProfile profile,
  ) {
    final duration = event.time?.durationMinutes;
    if (duration != null) return (minutes: duration, nominal: 0);
    final nominal = profile.nominalMinutes;
    if (nominal == null ||
        profile.kind == CategoryKind.sleep ||
        shapeOf(event) == ReportShape.repeat) {
      return (minutes: 0, nominal: 0);
    }
    return (minutes: nominal, nominal: nominal);
  }

  static EffectiveProfile _profileOf(ReportInput input, String categoryId) =>
      input.profiles[categoryId] ?? EffectiveProfile.unprofiled;

  /// A tag's noun and the category it is read from: the first profiled of
  /// its [categoryIds] — the catalogue seeds Other first, so the plain first
  /// id would let an uncategorised event erase a Social tag's person — else
  /// the first id under no kind.
  static ({CategoryKind kind, String categoryId}) _tagKindOf(
    ReportInput input,
    List<String> categoryIds,
  ) {
    for (final categoryId in categoryIds) {
      final profile = _profileOf(input, categoryId);
      if (!profile.isUnprofiled) {
        return (kind: profile.kind, categoryId: categoryId);
      }
    }
    return (kind: CategoryKind.custom, categoryId: categoryIds.first);
  }

  /// [categoryId]'s lookback and lookahead samples, oldest first, that the
  /// fold may read: an event in the selection, a day outside the span and
  /// never after today.
  static Iterable<ReportSample> _outside(
    ReportInput input,
    String categoryId,
  ) => (input.lookback[categoryId] ?? const <ReportSample>[])
      .followedBy(input.lookahead[categoryId] ?? const [])
      .where(
        (s) => input.events.containsKey(s.eventId) && _isOutside(input, s.day),
      );

  static bool _isOutside(ReportInput input, DateTime day) =>
      !_contains(input.span, day) && !day.isAfter(input.today);

  /// The latest kept day of [categoryId] after a past span, to today, from
  /// the lookahead; null when it holds none.
  static DateTime? _lastKeptAfterSpan(ReportInput input, String categoryId) {
    for (final sample
        in input.lookahead[categoryId]?.reversed ?? const <ReportSample>[]) {
      final event = input.events[sample.eventId];
      if (event == null ||
          !sample.day.isAfter(input.span.end) ||
          sample.day.isAfter(input.today) ||
          _isMissed(sample, event)) {
        continue;
      }
      return sample.day;
    }
    return null;
  }

  /// [event]'s title and description tags keyed once per event, the first
  /// spelling kept — `const []` for an untagged event, so the walk builds
  /// nothing for it.
  static List<({String key, String label})> _ownTagsOf(CalendarEvent event) {
    final title = extractTags(event.title);
    final description = extractTags(event.description);
    if (title.isEmpty && description.isEmpty) return const [];
    final keyed = <({String key, String label})>[];
    final keys = <String>{};
    for (final label in title.followedBy(description)) {
      final key = label.toLowerCase();
      if (keys.add(key)) keyed.add((key: key, label: label));
    }
    return keyed;
  }

  /// One kept day of [event] counted under [tag]: once per day, its money
  /// once per event.
  static void _tallyTag(
    ReportInput input,
    _TagTally tag,
    ReportSample sample,
    CalendarEvent event,
    String categoryId, {
    required int minutes,
    required bool past,
    required int? net,
  }) {
    tag.count++;
    tag.minutes += minutes;
    if (past) tag.lastSeen = sample.day;
    // The samples arrive by day: a second event tagged the same day adds no
    // gap.
    final epochDay = _epochDay(sample.day);
    if (tag.lastDay case final last? when epochDay > last) {
      tag.gaps.add(epochDay - last);
    }
    tag.lastDay = epochDay;
    if (tag.events.add(event.id) && net != null) {
      if (net < 0) tag.spentCents -= net;
      if (net > 0) tag.receivedCents += net;
    }
    if (!tag.categoryIds.contains(categoryId)) tag.categoryIds.add(categoryId);
    if (tag.rows.length < ReportMetrics.maxListRows) {
      tag.rows.add(_datedRow(input, sample, event));
    }
  }

  /// The tile set (D15, D20): decided by what the selection could ever show,
  /// never by what the period holds, so stepping never reshuffles the grid.
  /// A compared view's fold takes the page's set instead
  /// ([ReportInput.tileSet]), with no delta: its column stands beside the
  /// page's.
  static List<ReportTileValue> _tiles(
    ReportTense tense,
    ReportInput input,
    ReportTotals totals,
  ) {
    final plan = tense == ReportTense.future;
    if (input.tileSet case final tileSet?) {
      return [
        for (final tile in tileSet)
          switch (tile) {
            ReportTile.events => ReportTileValue(
              tile: tile,
              value: totals.kept,
            ),
            ReportTile.planned => ReportTileValue(
              tile: tile,
              value: totals.occurrences,
            ),
            ReportTile.attended => ReportTileValue(
              tile: tile,
              value: totals.attended,
              of: totals.tracked,
            ),
            ReportTile.missed => ReportTileValue(
              tile: tile,
              value: totals.missed,
            ),
            ReportTile.hours => ReportTileValue(
              tile: tile,
              value: plan ? totals.minutesAll : totals.minutesKept,
            ),
            ReportTile.tasks => ReportTileValue(
              tile: tile,
              value: totals.tasksTicked,
              of: totals.tasksTotal,
            ),
          },
      ];
    }
    final events = input.events.values;
    // A tracked one-off is graded too (analytics AM), so it shows the grades.
    final anyRoutine = events.any((e) => e.tracksPresence);
    final anyTimed = events.any((e) {
      final profile = _profileOf(input, _categoryOf(input, e));
      return profile.countsHours &&
          (e.time?.durationMinutes != null ||
              _minutesOf(e, profile).nominal > 0);
    });
    final anyTasks = events.any((e) => _holdsTasks(e, input.overrides));
    final previous = input.previousTotals;
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
  /// samples; the columns cover the whole span. A compared fold's trend is
  /// its columns alone — the outline behind the page's (§6.11) — since no
  /// caption names its busiest day or usual hours.
  static ReportTrend _trend(
    ReportInput input,
    List<ReportSample> countedSamples,
  ) {
    final captions = input.role == ReportFoldRole.main;
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
      if (!captions) continue;
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
    final buckets = List<ReportTrendBucket>.unmodifiable([
      for (var i = 0; i < starts.length; i++)
        ReportTrendBucket(
          start: starts[i],
          happened: happened[i],
          missed: missed[i],
        ),
    ]);
    if (!captions) return ReportTrend(unit: unit, buckets: buckets);

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
      buckets: buckets,
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

  /// Orders [samples] by day in place, with one pass when they already are.
  static void _sortByDay(List<ReportSample> samples) {
    for (var i = 1; i < samples.length; i++) {
      if (samples[i].day.isBefore(samples[i - 1].day)) {
        samples.sort((a, b) => a.day.compareTo(b.day));
        return;
      }
    }
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

  /// A pending occurrence has not happened yet, so it is never missed; an
  /// untracked one cannot be. A tracked one-off is graded like a routine's
  /// day (analytics AM): its missed day is a dated Missed row.
  static bool _isMissed(ReportSample sample, CalendarEvent event) =>
      sample.missed && !sample.pending && event.tracksPresence;

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

  static DateTime _dateOnly(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day);
}

/// One category's running measures while [CalendarReportBuilder._measures]
/// walks its samples.
class _MeasureTally {
  int count = 0;
  final Set<String> events = {};
  int minutes = 0;
  int nominal = 0;
  int attended = 0;
  int tracked = 0;
  int cancelled = 0;
  int planned = 0;
  int tasksTicked = 0;
  int tasksTotal = 0;
  int spentCents = 0;
  int receivedCents = 0;
  bool hasMoney = false;
  final List<int> leadDays = [];
  final List<int> startMinutes = [];
  int lateDays = 0;
  final List<int> weekdays = List.filled(7, 0);
  final List<int> missedWeekdays = List.filled(7, 0);
  int weekendMinutes = 0;
  final _WeekMax lateWeeks = _WeekMax();
  final _WeekMax shortWeeks = _WeekMax();

  // Day numbers (`_epochDay`): the latest kept day in the span and the
  // widest gap behind it; the episodes' count, latest start, the latest day
  // of the run that started it, and the sum and sum of squares of the gaps
  // between starts, which give the mean and the spread with no list kept.
  int? lastKeptDay;
  int longestGap = 0;
  // The kept day before [longestGap]: the first of the widest, since a tie
  // never replaces it.
  int? longestGapFrom;
  int episodes = 0;
  int? lastEpisode;
  int? lastRunDay;
  int gapSum = 0;
  int gapSquares = 0;

  // The samples arrive sorted by day: the last kept day to today seen is the
  // latest, the first one still to come (today's pending one included) the
  // next.
  DateTime? lastSeen;
  DateTime? nextDay;
}

/// The most days counted in one week while the samples arrive by day: a
/// week's count runs until a later week's key arrives.
class _WeekMax {
  int? _week;
  int _inWeek = 0;
  int max = 0;

  void add(int week) {
    if (week != _week) {
      _week = week;
      _inWeek = 0;
    }
    if (++_inWeek > max) max = _inWeek;
  }
}

/// A whole year's running aggregates while [CalendarReportBuilder._measures]
/// walks its kept samples by day (§6.12): fixed month and week slots, and
/// each event's own slot resolved before the walk, so a year of daily
/// samples adds a few increments each and no lookup.
class _YearTally {
  _YearTally(DateTime first, ReportInput input)
    : year = first.year,
      firstEpochDay = CalendarReportBuilder._epochDay(first),
      firstWeekOffset =
          (7 - (first.weekday - input.weekStart.weekday + 7) % 7) % 7,
      countedTo = CalendarReport.countedToOf(
        span: input.span,
        today: input.today,
      );

  final int year;
  final int firstEpochDay;

  /// Days from 1 January to the first week start inside the year: a week
  /// begun in December is the year before's.
  final int firstWeekOffset;

  /// Money and cancellations count to here, as the kept samples do.
  final DateTime countedTo;

  final List<int> kept = List.filled(12, 0);
  final List<int> social = List.filled(12, 0);
  final List<int> spent = List.filled(12, 0);
  final List<int> weeks = List.filled(53, 0);
  final Map<String, _CategoryYear> categories = {};
  final List<_EventYear> _events = [];
  final List<_Run> _closedTrips = [];

  // The runs' walk order, the last tie-break.
  int _order = 0;

  /// [event]'s slot, made once before the walk.
  _EventYear eventOf(
    CalendarEvent event,
    String categoryId,
    CategoryKind kind,
  ) {
    final slot = _EventYear(
      event.id,
      categoryId,
      categories[categoryId] ??= _CategoryYear(),
      tracked: event.tracksPresence,
      trip: kind == CategoryKind.trip,
      social: kind == CategoryKind.social,
    );
    _events.add(slot);
    return slot;
  }

  void keep(
    _EventYear slot,
    DateTime day,
    int epochDay,
    int week, {
    required int minutes,
  }) {
    final m = day.month - 1;
    kept[m]++;
    if (slot.social) social[m]++;
    final fromFirstWeek = week - firstEpochDay - firstWeekOffset;
    if (fromFirstWeek >= 0) weeks[fromFirstWeek ~/ 7]++;
    final category = slot.category;
    category.kept[m]++;
    // The samples arrive by day, so an event's months only move forward.
    if (slot.lastMonth != m) {
      slot.lastMonth = m;
      category.events[m]++;
    }
    category.minutes[m] += minutes;
    category.first ??= epochDay;
    category.last = epochDay;
    if (slot.trip) {
      final run = slot.openTrip;
      if (run != null && run.last == epochDay - 1) {
        run.extend(epochDay);
      } else {
        if (run != null) _closedTrips.add(run);
        slot.openTrip = _Run(slot, epochDay, _order++);
      }
    }
    if (slot.tracked) {
      category.attended[m]++;
      if (slot.openStreak case final run?) {
        run.extend(epochDay);
      } else {
        slot.openStreak = _Run(slot, epochDay, _order++);
      }
    }
  }

  void money(String categoryId, DateTime start, int net) {
    if (start.isAfter(countedTo)) return;
    final m = start.month - 1;
    final category = categories[categoryId] ??= _CategoryYear();
    if (net < 0) {
      category.spentCents[m] -= net;
      spent[m] -= net;
    } else {
      category.receivedCents[m] += net;
    }
  }

  void cancel(String categoryId, DateTime day) {
    if (day.year != year || day.isAfter(countedTo)) return;
    (categories[categoryId] ??= _CategoryYear()).cancelled[day.month - 1]++;
  }

  /// Every trip, the runs still open at the year's last counted day included.
  Iterable<_Run> trips() => [
    ..._closedTrips,
    for (final slot in _events) ?slot.openTrip,
  ];

  /// Each tracked event's longest run; call once, after the walk.
  Iterable<_Run> streaks() => [
    for (final slot in _events)
      if (slot.tracked) ?(slot..miss()).bestStreak,
  ];
}

/// One event's running year: its last month counted and its open runs.
class _EventYear {
  _EventYear(
    this.eventId,
    this.categoryId,
    this.category, {
    required this.tracked,
    required this.trip,
    required this.social,
  });

  final String eventId;
  final String categoryId;
  final _CategoryYear category;
  final bool tracked;
  final bool trip;
  final bool social;
  int lastMonth = -1;
  _Run? openTrip;
  _Run? openStreak;
  _Run? bestStreak;

  /// A missed day, or the walk's end: the open streak closes, and only a
  /// longer one replaces the best, so the earliest of the longest stays.
  void miss() {
    final run = openStreak;
    if (run == null) return;
    openStreak = null;
    final best = bestStreak;
    if (best == null || run.length > best.length) bestStreak = run;
  }
}

/// One category's twelve months while the year walks.
class _CategoryYear {
  final List<int> kept = List.filled(12, 0);
  final List<int> events = List.filled(12, 0);
  final List<int> minutes = List.filled(12, 0);
  final List<int> attended = List.filled(12, 0);
  final List<int> cancelled = List.filled(12, 0);
  final List<int> spentCents = List.filled(12, 0);
  final List<int> receivedCents = List.filled(12, 0);

  // The first and the latest kept day's number; null until one is kept.
  int? first;
  int last = 0;
}

/// One event's run of consecutive kept days (a trip) or occurrences (a
/// streak), in day numbers.
class _Run {
  _Run(_EventYear slot, this.start, this.order)
    : eventId = slot.eventId,
      categoryId = slot.categoryId,
      last = start;

  final String eventId;
  final String categoryId;
  final int start;
  final int order;
  int last;
  int length = 1;

  void extend(int epochDay) {
    last = epochDay;
    length++;
  }
}

/// One goal's period buckets while the measures walk (§8 "Cost"): a sample
/// lands in its period by index, so a year of daily samples costs one pass
/// and the periods one more.
class _GoalTally {
  _GoalTally({
    required this.period,
    required this.base,
    required this.streakFrom,
    required this.spanFirst,
    required int length,
  }) : buckets = List.filled(length, null);

  final TargetPeriod period;

  /// The first bucket's first day.
  final DateTime base;

  /// The first period the streak reads.
  final DateTime streakFrom;

  /// The first period the goal lists: the one holding the span's start.
  final DateTime spanFirst;

  final List<_PeriodTally?> buckets;

  // The last sample's day, its period's first day and its bucket index: the
  // samples arrive by day, many to a day, so each day's period is resolved
  // once rather than once per sample.
  DateTime? lastDay;
  DateTime? lastStart;
  int lastIndex = 0;

  /// The bucket at [index], made on first use; null outside the tally.
  _PeriodTally? bucketAt(int index) {
    if (index < 0 || index >= buckets.length) return null;
    return buckets[index] ??= _PeriodTally();
  }
}

/// One goal period's running numbers, one per measure a goal can count.
class _PeriodTally {
  int count = 0;
  final Set<String> events = {};
  int minutes = 0;
  int attended = 0;
  int tasksTicked = 0;
  final Set<String> sharedCounted = {};
  int spentCents = 0;
  int receivedCents = 0;
}

/// One tag's running numbers while the measures walk.
class _TagTally {
  _TagTally(this.label);

  final String label;
  int count = 0;
  final Set<String> events = {};
  int minutes = 0;
  int spentCents = 0;
  int receivedCents = 0;
  DateTime? lastSeen;
  final List<String> categoryIds = [];
  final List<ReportDatedRow> rows = [];

  // The latest tagged day's number and the gaps between distinct days —
  // a tagged day is rare, unlike a sample.
  int? lastDay;
  final List<int> gaps = [];
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
