import '../constants/analytics_metrics.dart';
import '../constants/category_kinds.dart';
import '../models/calendar_report.dart';
import '../models/category_profile.dart';

/// The insight library (L, §6.7): one pure function per rule over the
/// folded report, each yielding the facts it found as typed numbers — never
/// a sentence, which the labels write.
///
/// Only a profiled category feeds a rule (`ReportMeasures.profiled`), so a
/// calendar with no profile yields no insight and reads as it did before
/// the analytics. Every threshold is an [AnalyticsMetrics] constant (Z).
abstract final class ReportInsights {
  /// Every insight [report] holds, ranked: severity descending, then the
  /// category's primary value descending (a tag insight's category's), then
  /// [InsightRule] order, then the order a rule found them in — so two folds
  /// of the same data rank the same. [profiles] are the fold's, by resolved
  /// category id; an absent one is unprofiled.
  ///
  /// The primary values compare across units — cents, minutes and counts on
  /// one scale — as §6.7 states the rule: within one severity a money
  /// category outranks a count one; accepted, since only the order among
  /// equals is at stake.
  static List<ReportInsight> rank(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) {
    final fired = [
      for (final rule in _rules) ...rule(report, profiles),
    ].indexed.toList();
    int primaryOf(ReportInsight insight) =>
        _primaryValue(report.measures[insight.categoryId]);
    fired.sort((a, b) {
      final bySeverity = b.$2.severity.compareTo(a.$2.severity);
      if (bySeverity != 0) return bySeverity;
      final byPrimary = primaryOf(b.$2).compareTo(primaryOf(a.$2));
      if (byPrimary != 0) return byPrimary;
      final byRule = a.$2.rule.index.compareTo(b.$2.rule.index);
      return byRule != 0 ? byRule : a.$1.compareTo(b.$1);
    });
    return [for (final (_, insight) in fired) insight];
  }

  static const List<
    Iterable<ReportInsight> Function(
      CalendarReport report,
      Map<String, EffectiveProfile> profiles,
    )
  >
  _rules = [
    _g1,
    _g2,
    _g3,
    _g4,
    _g5,
    _d1d2,
    _d3,
    _d4,
    _d5,
    _p1,
    _p2,
    _p3,
    _p4,
    _p5,
    _p6,
    _m1,
    _m2,
    _r1,
    _r2,
    _l1,
    _l2,
    _a1,
    _a2,
  ];

  /// The size a category leads with, in its primary's unit. A measure that
  /// is a position in time (last seen, lead time, timing, days until) has
  /// no size to rank by, so it ranks by the kept days.
  static int _primaryValue(ReportMeasures? measures) {
    if (measures == null) return 0;
    return switch (measures.primary) {
      ReportMeasure.count => measures.count,
      ReportMeasure.events => measures.events,
      ReportMeasure.hours => measures.minutes,
      ReportMeasure.attendance => measures.attended,
      ReportMeasure.cancelled => measures.cancelled,
      ReportMeasure.tasks => measures.tasksTicked,
      ReportMeasure.money => measures.spentCents + measures.receivedCents,
      ReportMeasure.lastSeen ||
      ReportMeasure.leadTime ||
      ReportMeasure.timing ||
      ReportMeasure.daysUntil => measures.count,
    };
  }

  // G1: an at-least goal behind with more than half its period elapsed.
  static Iterable<ReportInsight> _g1(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    final today = report.today;
    for (final goal in report.goals) {
      if (goal.target.kind != TargetKind.atLeast) continue;
      final period = _currentPeriod(goal, today);
      if (period == null || period.state != GoalState.behind) continue;
      final days = period.end.difference(period.start).inDays + 1;
      final elapsed = today.difference(period.start).inDays + 1;
      if (elapsed / days <= AnalyticsMetrics.goalBehindMinElapsed) continue;
      final target = goal.target.value;
      yield ReportInsight(
        rule: InsightRule.g1,
        severity: 3,
        categoryId: goal.categoryId,
        target: InsightTarget.categoryGroup,
        day: period.start,
        dayEnd: period.end,
        n1: period.value,
        n2: target,
        n3: target - period.value,
      );
    }
  }

  // G2: an at-most or budget goal over in its current period.
  static Iterable<ReportInsight> _g2(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    for (final goal in report.goals) {
      final kind = goal.target.kind;
      if (kind != TargetKind.atMost && kind != TargetKind.budget) continue;
      final period = _currentPeriod(goal, report.today);
      if (period == null || period.state != GoalState.over) continue;
      final target = goal.target.value;
      yield ReportInsight(
        rule: InsightRule.g2,
        severity: 2,
        categoryId: goal.categoryId,
        target: InsightTarget.categoryGroup,
        day: period.start,
        dayEnd: period.end,
        n1: period.value,
        n2: target,
        n3: period.value - target,
      );
    }
  }

  // G3: a goal met before its current period ends — only an at-least goal
  // reads met while its period runs.
  static Iterable<ReportInsight> _g3(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    for (final goal in report.goals) {
      final period = _currentPeriod(goal, report.today);
      if (period == null || period.state != GoalState.met) continue;
      final target = goal.target.value;
      yield ReportInsight(
        rule: InsightRule.g3,
        severity: 1,
        categoryId: goal.categoryId,
        target: InsightTarget.categoryGroup,
        day: period.start,
        dayEnd: period.end,
        n1: target,
        n2: target,
      );
    }
  }

  // G4: a streak at a milestone, or one the last closed period ended. A
  // plan has no closed period of its own: its streak is the lookback's.
  static Iterable<ReportInsight> _g4(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    if (report.tense == ReportTense.future) return;
    for (final goal in report.goals) {
      final streak = goal.streak;
      if (streak > 0 && streak % AnalyticsMetrics.streakMilestone == 0) {
        yield ReportInsight(
          rule: InsightRule.g4,
          severity: 2,
          categoryId: goal.categoryId,
          target: InsightTarget.categoryGroup,
          n1: streak,
        );
      } else if (goal.brokenStreak > 0) {
        yield ReportInsight(
          rule: InsightRule.g4,
          severity: 1,
          categoryId: goal.categoryId,
          target: InsightTarget.categoryGroup,
          n1: goal.brokenStreak,
          alternate: true,
        );
      }
    }
  }

  // G5: a yearly Leave allowance nearly spent early, or days unused late.
  static Iterable<ReportInsight> _g5(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    final today = report.today;
    for (final goal in report.goals) {
      final target = goal.target;
      if (_profileOf(profiles, goal.categoryId).kind != CategoryKind.leave ||
          target.kind != TargetKind.atMost ||
          target.period != TargetPeriod.year) {
        continue;
      }
      final period = _currentPeriod(goal, today);
      if (period == null || period.value > target.value) continue;
      final remaining = target.value - period.value;
      final yearDays = period.end.difference(period.start).inDays + 1;
      final daysLeft = period.end.difference(today).inDays;
      // "Under 20 % left" and "under a month left": both bounds strict.
      final low =
          remaining < AnalyticsMetrics.leaveLowFraction * target.value &&
          daysLeft / yearDays > AnalyticsMetrics.leaveQuarterAhead;
      final unused =
          remaining > 0 && daysLeft < AnalyticsMetrics.leaveUnusedDaysLeft;
      if (!low && !unused) continue;
      yield ReportInsight(
        rule: InsightRule.g5,
        severity: 1,
        categoryId: goal.categoryId,
        target: InsightTarget.categoryGroup,
        day: period.start,
        dayEnd: period.end,
        n1: remaining,
        n2: target.value,
        n3: low ? DateTime.december - today.month : daysLeft,
        alternate: !low,
      );
    }
  }

  // D1 and D2: a gap target overdue or due — one walk, two rules, since a
  // gap reads exactly one state. Graded only, as the Due soon card's rows.
  static Iterable<ReportInsight> _d1d2(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    if (report.tense == ReportTense.future) return;
    for (final goal in report.goals) {
      final gap = goal.gap;
      if (gap == null) continue;
      if (gap.state == GapState.overdue) {
        yield ReportInsight(
          rule: InsightRule.d1,
          severity: 3,
          categoryId: goal.categoryId,
          target: InsightTarget.dueSoon,
          n1: gap.daysSince,
          n2: gap.limit,
          beyondLookback: gap.beyondLookback,
        );
      } else if (gap.state == GapState.due) {
        yield ReportInsight(
          rule: InsightRule.d2,
          severity: 2,
          categoryId: goal.categoryId,
          target: InsightTarget.dueSoon,
          n1: gap.limit - gap.daysSince,
          n2: gap.limit,
        );
      }
    }
  }

  // D3: an Expiry inside the warning window, or one passed unmarked — read
  // from the Due soon rows, which also hold a one-off past the span's end,
  // one insight per event: its first row, the card's most urgent.
  static Iterable<ReportInsight> _d3(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    final seen = <String>{};
    for (final row in report.dueSoon) {
      if (row.kind != ReportDueKind.expiry) continue;
      final overdue = row.state == ReportDueState.overdue;
      if (!overdue &&
          (row.state != ReportDueState.upcoming ||
              row.days > AnalyticsMetrics.expiryWarnDays)) {
        continue;
      }
      if (!seen.add(row.eventId)) continue;
      yield ReportInsight(
        rule: InsightRule.d3,
        severity: overdue ? 2 : 3,
        categoryId: row.categoryId,
        eventId: row.eventId,
        target: InsightTarget.dueSoon,
        day: row.day,
        n1: row.days,
        alternate: overdue,
      );
    }
  }

  // D4: a Bill's or a Deadline's day passed unmarked, once per event. The
  // unmarked rows come the fewest days since first, so an event's first
  // row is its latest unmarked day.
  static Iterable<ReportInsight> _d4(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    final latest = <String, ReportDueRow>{};
    final unmarked = <String, int>{};
    for (final row in report.dueSoon) {
      if (row.state != ReportDueState.unmarked) continue;
      latest.putIfAbsent(row.eventId, () => row);
      unmarked.update(row.eventId, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final MapEntry(key: eventId, value: row) in latest.entries) {
      yield ReportInsight(
        rule: InsightRule.d4,
        severity: 3,
        categoryId: row.categoryId,
        eventId: eventId,
        target: InsightTarget.dueSoon,
        day: row.day,
        n1: unmarked[eventId]!,
        n2: row.days,
      );
    }
  }

  // D5: a regular Episode's next one expected within the notice window.
  static Iterable<ReportInsight> _d5(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    final today = report.today;
    for (final (measures, profile) in _profiled(report, profiles)) {
      final mean = measures.episodeGapMean;
      final cv = measures.episodeGapCv;
      final last = measures.lastEpisodeDay;
      if (profile.kind != CategoryKind.episode ||
          measures.episodes < AnalyticsMetrics.episodeMinCount ||
          mean == null ||
          cv == null ||
          last == null ||
          cv >= AnalyticsMetrics.episodeRegularCv) {
        continue;
      }
      final gap = mean.round();
      final expected = DateTime.utc(last.year, last.month, last.day + gap);
      final until = expected.difference(today).inDays;
      if (until < 0 || until > AnalyticsMetrics.episodeAheadDays) continue;
      yield ReportInsight(
        rule: InsightRule.d5,
        severity: 1,
        categoryId: measures.categoryId,
        target: InsightTarget.categoryGroup,
        day: expected,
        n1: measures.episodes,
        n2: gap,
        n3: until,
      );
    }
  }

  // P1: a routine's attendance by weekday spread wide. Only a category whose
  // every counted row is a routine's, so the kept histogram is attendance.
  static Iterable<ReportInsight> _p1(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    if (report.tense == ReportTense.future) return;
    final routines = {
      for (final group in report.categories)
        if (group.rows.isNotEmpty &&
            group.rows.every((row) => row is ReportRoutineRow))
          group.categoryId,
    };
    for (final (measures, _) in _profiled(report, profiles)) {
      if (!routines.contains(measures.categoryId)) continue;
      final kept = measures.weekdayHistogram;
      final missed = measures.missedByWeekday;
      int tracked(int w) => kept[w] + missed[w];
      // The shares compare exactly, as cross products, and round only for
      // the slots: 5 of 8 and 5 of 22 round to 63 and 23, forty points,
      // while the days hold 39.8.
      int compare(int a, int b) => kept[a] * tracked(b) - kept[b] * tracked(a);
      int? best;
      int? worst;
      for (var w = 0; w < 7; w++) {
        if (tracked(w) < AnalyticsMetrics.weekdayMinDays) continue;
        if (best == null || compare(w, best) > 0) best = w;
        if (worst == null || compare(w, worst) < 0) worst = w;
      }
      if (best == null || worst == null) continue;
      if (100 * compare(best, worst) <
          AnalyticsMetrics.weekdaySpreadPoints *
              tracked(best) *
              tracked(worst)) {
        continue;
      }
      int percent(int w) => (100 * kept[w] + tracked(w) ~/ 2) ~/ tracked(w);
      yield ReportInsight(
        rule: InsightRule.p1,
        severity: 1,
        categoryId: measures.categoryId,
        target: InsightTarget.categoryGroup,
        n1: percent(best),
        n2: percent(worst),
        n3: best,
        n4: worst,
      );
    }
  }

  // P2: Work late evenings piling up in a week, or Work on the weekend.
  static Iterable<ReportInsight> _p2(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    if (report.tense == ReportTense.future) return;
    for (final (measures, profile) in _profiled(report, profiles)) {
      if (profile.kind != CategoryKind.work) continue;
      final late =
          measures.maxLateDaysInAWeek >= AnalyticsMetrics.lateEveningsPerWeek;
      if (!late && measures.weekendMinutes == 0) continue;
      yield ReportInsight(
        rule: InsightRule.p2,
        severity: 1,
        categoryId: measures.categoryId,
        target: InsightTarget.categoryGroup,
        n1: measures.maxLateDaysInAWeek,
        minutes: measures.weekendMinutes,
        alternate: !late,
      );
    }
  }

  // P3: short nights piling up in a week, or bedtimes spread wide.
  static Iterable<ReportInsight> _p3(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    if (report.tense == ReportTense.future) return;
    for (final (measures, profile) in _profiled(report, profiles)) {
      if (profile.kind != CategoryKind.sleep) continue;
      final short =
          measures.maxShortDaysInAWeek >= AnalyticsMetrics.shortNightsPerWeek;
      final spread =
          measures.startMinuteSpread > AnalyticsMetrics.bedtimeSpreadMinutes;
      if (!short && !spread) continue;
      yield ReportInsight(
        rule: InsightRule.p3,
        severity: 1,
        categoryId: measures.categoryId,
        target: InsightTarget.categoryGroup,
        n1: measures.maxShortDaysInAWeek,
        n2: measures.startMinuteSpread,
        alternate: !short,
      );
    }
  }

  // P4: Meetings taking most of the Work + Meeting hours — one insight over
  // every such category, pointed at the Meeting category with the most.
  static Iterable<ReportInsight> _p4(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    if (report.tense == ReportTense.future) return;
    var work = 0;
    var meetings = 0;
    ReportMeasures? lead;
    for (final (measures, profile) in _profiled(report, profiles)) {
      if (profile.kind == CategoryKind.work) work += measures.minutes;
      if (profile.kind != CategoryKind.meeting) continue;
      meetings += measures.minutes;
      if (lead == null || measures.minutes > lead.minutes) lead = measures;
    }
    final total = work + meetings;
    // With no Work hours the share is no share: every hour would read as
    // Meetings.
    if (lead == null || meetings == 0 || work == 0) return;
    final share = meetings / total;
    if (share < AnalyticsMetrics.meetingShare) return;
    yield ReportInsight(
      rule: InsightRule.p4,
      severity: 1,
      categoryId: lead.categoryId,
      target: InsightTarget.categoryGroup,
      n1: total,
      minutes: meetings,
      ratio: share,
    );
  }

  // P5: a large share of the planned days cancelled.
  static Iterable<ReportInsight> _p5(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    if (report.tense == ReportTense.future) return;
    for (final (measures, _) in _profiled(report, profiles)) {
      final planned = measures.planned;
      if (planned < AnalyticsMetrics.cancelledMinPlanned ||
          measures.cancelled == 0) {
        continue;
      }
      final share = measures.cancelled / planned;
      if (share < AnalyticsMetrics.cancelledShare) continue;
      yield ReportInsight(
        rule: InsightRule.p5,
        severity: 2,
        categoryId: measures.categoryId,
        target: InsightTarget.categoryGroup,
        n1: measures.cancelled,
        n2: planned,
        ratio: share,
      );
    }
  }

  // P6: a Workout routine rested for long. In a current span the rest still
  // running counts too — the days after the span's last kept day to today —
  // so "stopped three weeks ago" fires before the next run closes the gap.
  static Iterable<ReportInsight> _p6(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    if (report.tense == ReportTense.future) return;
    for (final (measures, profile) in _profiled(report, profiles)) {
      if (profile.kind != CategoryKind.workout) continue;
      var rest = measures.longestGapDays;
      final seen = measures.lastSeenDay;
      if (report.tense == ReportTense.current &&
          seen != null &&
          !seen.isBefore(report.span.start)) {
        final running = report.today.difference(seen).inDays - 1;
        if (running > rest) rest = running;
      }
      if (rest < AnalyticsMetrics.restGapDays) continue;
      yield ReportInsight(
        rule: InsightRule.p6,
        severity: 1,
        categoryId: measures.categoryId,
        target: InsightTarget.categoryGroup,
        n1: rest,
      );
    }
  }

  // M1: the money of a Bill category's events occurring in the next month,
  // in every tense — the sampler's own window, never the span's Ahead, so a
  // Rent that began last year counts and a report on the 25th sees the 3rd.
  // Money is the note's net once per event (P), spent only.
  static Iterable<ReportInsight> _m1(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    final today = report.today;
    for (final MapEntry(key: categoryId, value: eventIds)
        in report.billsAhead.entries) {
      if (!_profiledKind(report, profiles, categoryId, CategoryKind.bill)) {
        continue;
      }
      var cents = 0;
      var count = 0;
      for (final eventId in eventIds) {
        final net = report.money[eventId];
        if (net == null || net >= 0) continue;
        cents -= net;
        count++;
      }
      if (count == 0) continue;
      yield ReportInsight(
        rule: InsightRule.m1,
        severity: 0,
        categoryId: categoryId,
        target: InsightTarget.overviewDays,
        day: today,
        dayEnd: DateTime.utc(
          today.year,
          today.month,
          today.day + AnalyticsMetrics.billsAheadDays,
        ),
        n1: count,
        cents: cents,
      );
    }
  }

  // M2: on a whole calendar year, the money of a Bill category's recurring
  // events — any shape but a one-off, a tracked one (a routine) included,
  // since the Bill kind marks.
  static Iterable<ReportInsight> _m2(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    final span = report.span;
    if (span.start != DateTime.utc(span.start.year, 1, 1) ||
        span.end != DateTime.utc(span.start.year, 12, 31)) {
      return;
    }
    final byCategory = <String, Set<String>>{};
    for (final group in [
      ...report.categories,
      ...report.missed,
      ...report.ahead,
    ]) {
      if (!_profiledKind(
        report,
        profiles,
        group.categoryId,
        CategoryKind.bill,
      )) {
        continue;
      }
      final ids = byCategory[group.categoryId] ??= {};
      for (final row in group.rows) {
        ids.add(row.eventId);
      }
    }
    for (final MapEntry(key: categoryId, value: ids) in byCategory.entries) {
      var cents = 0;
      var count = 0;
      for (final id in ids) {
        final net = report.money[id];
        final event = report.events[id];
        if (net == null || net >= 0 || event == null) continue;
        if (shapeOf(event) == ReportShape.oneOff) continue;
        cents -= net;
        count++;
      }
      if (count == 0) continue;
      yield ReportInsight(
        rule: InsightRule.m2,
        severity: 0,
        categoryId: categoryId,
        target: InsightTarget.categoryGroup,
        n1: count,
        cents: cents,
      );
    }
  }

  // R1: a tag unseen past its category's gap limit, else past a multiple of
  // its own median gap. Only where the span reaches today: a tag's days
  // come from the span alone, so after a past span its last-seen day is
  // the span's, never the real one, and a past report carries no R1. The
  // lookahead that would close the gap is scanned per target-or-gap
  // category (R's one probe per category), never per tag.
  static Iterable<ReportInsight> _r1(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    if (report.tense == ReportTense.past) return;
    final limits = <String, int>{
      for (final goal in report.goals)
        if (goal.target.kind == TargetKind.maxGap)
          goal.categoryId: goal.target.value,
    };
    for (final tag in report.tags) {
      final seen = tag.lastSeenDay;
      if (seen == null) continue;
      final profiled = [
        for (final id in tag.categoryIds)
          if (report.measures[id]?.profiled ?? false) id,
      ];
      if (profiled.isEmpty) continue;
      final since = report.today.difference(seen).inDays;
      final gapCategory = profiled.where(limits.containsKey).firstOrNull;
      final median = tag.medianGapDays;
      final int limit;
      if (gapCategory != null) {
        limit = limits[gapCategory]!;
      } else if (median != null) {
        limit = AnalyticsMetrics.tagGapMultiple * median;
      } else {
        continue;
      }
      if (since <= limit) continue;
      yield ReportInsight(
        rule: InsightRule.r1,
        severity: 2,
        categoryId: gapCategory ?? profiled.first,
        tagKey: tag.key,
        target: InsightTarget.tagRows,
        n1: since,
        n2: limit,
        alternate: gapCategory == null,
      );
    }
  }

  // R2: the span's most-seen tag across the People categories, by days —
  // "most evenings" — so a weekly dinner outranks two one-off evenings. A
  // tie keeps the tags' order.
  static Iterable<ReportInsight> _r2(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    final people = {
      for (final (measures, profile) in _profiled(report, profiles))
        if (profile.area == LifeArea.people) measures.categoryId,
    };
    if (people.isEmpty) return;
    ReportTag? best;
    String? categoryId;
    for (final tag in report.tags) {
      final inPeople = tag.categoryIds.where(people.contains).firstOrNull;
      if (inPeople == null || tag.count == 0) continue;
      if (best == null || tag.count > best.count) {
        best = tag;
        categoryId = inPeople;
      }
    }
    if (best == null) return;
    yield ReportInsight(
      rule: InsightRule.r2,
      severity: 0,
      categoryId: categoryId,
      tagKey: best.key,
      target: InsightTarget.tagRows,
      n1: best.count,
    );
  }

  // L1: Appointments or Social events booked at short notice.
  static Iterable<ReportInsight> _l1(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    for (final (measures, profile) in _profiled(report, profiles)) {
      final lead = measures.leadTimeDays;
      if ((profile.kind != CategoryKind.appointment &&
              profile.kind != CategoryKind.social) ||
          lead == null ||
          measures.leadTimeEvents < AnalyticsMetrics.leadTimeMinEvents ||
          lead >= AnalyticsMetrics.leadTimeShortDays) {
        continue;
      }
      yield ReportInsight(
        rule: InsightRule.l1,
        severity: 0,
        categoryId: measures.categoryId,
        target: InsightTarget.categoryGroup,
        n1: lead,
        n2: measures.leadTimeEvents,
      );
    }
  }

  // L2: Deadline one-offs left open past their day.
  static Iterable<ReportInsight> _l2(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    for (final group in report.missed) {
      if (!_profiledKind(
        report,
        profiles,
        group.categoryId,
        CategoryKind.deadline,
      )) {
        continue;
      }
      final open = {
        for (final row in group.rows)
          if (report.events[row.eventId] case final event?
              when shapeOf(event) == ReportShape.oneOff)
            row.eventId,
      };
      if (open.length < AnalyticsMetrics.deadlinesOpenMin) continue;
      yield ReportInsight(
        rule: InsightRule.l2,
        severity: 2,
        categoryId: group.categoryId,
        target: InsightTarget.categoryGroup,
        n1: open.length,
      );
    }
  }

  // A1: Anniversaries still to come in the span, counted as occurrences —
  // the header's count, never the rows, so an aggregate row is never one.
  static Iterable<ReportInsight> _a1(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    for (final group in _upcoming(report)) {
      if (group.count == 0 ||
          !_profiledKind(
            report,
            profiles,
            group.categoryId,
            CategoryKind.anniversary,
          )) {
        continue;
      }
      yield ReportInsight(
        rule: InsightRule.a1,
        severity: 0,
        categoryId: group.categoryId,
        target: InsightTarget.overviewDays,
        day: _remainderStart(report),
        dayEnd: report.span.end,
        n1: group.count,
      );
    }
  }

  // A2: the next Trip still to come in the span, across Trip categories. A
  // trip is a run of one event's consecutive days, read from every card's
  // dated rows (a routine's aggregate by its latest day), so a trip already
  // under way — begun today or before, "in 0 days" — is no next trip, and
  // the range ends on the trip's last day in the span.
  static Iterable<ReportInsight> _a2(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    final today = report.today;
    final daysOf = <String, Set<DateTime>>{};
    final categoryOf = <String, String>{};
    for (final group in [
      ...report.categories,
      ...report.missed,
      ...report.ahead,
    ]) {
      if (!_profiledKind(
        report,
        profiles,
        group.categoryId,
        CategoryKind.trip,
      )) {
        continue;
      }
      for (final row in group.rows) {
        final day = switch (row) {
          ReportDatedRow(:final day) => day,
          ReportRoutineRow(:final latestDay) => latestDay,
        };
        (daysOf[row.eventId] ??= {}).add(day);
        categoryOf[row.eventId] = group.categoryId;
      }
    }
    DateTime? first;
    String? eventId;
    for (final MapEntry(key: id, value: days) in daysOf.entries) {
      for (final day in days) {
        if (!day.isAfter(today) || days.contains(_addDays(day, -1))) continue;
        if (first == null ||
            day.isBefore(first) ||
            (day == first && id.compareTo(eventId!) < 0)) {
          first = day;
          eventId = id;
        }
      }
    }
    if (first == null || eventId == null) return;
    final days = daysOf[eventId]!;
    var last = first;
    while (days.contains(_addDays(last, 1))) {
      last = _addDays(last, 1);
    }
    yield ReportInsight(
      rule: InsightRule.a2,
      severity: 0,
      categoryId: categoryOf[eventId],
      eventId: eventId,
      target: InsightTarget.overviewDays,
      day: first,
      dayEnd: last,
      n1: first.difference(today).inDays,
    );
  }

  static DateTime _addDays(DateTime day, int days) =>
      DateTime.utc(day.year, day.month, day.day + days);

  /// The period of [goal] holding [today], or null when the span's periods
  /// do not reach it (a past span, a plan).
  static ReportGoalPeriod? _currentPeriod(ReportGoal goal, DateTime today) {
    for (final period in goal.periods) {
      if (!period.start.isAfter(today) && !period.end.isBefore(today)) {
        return period;
      }
    }
    return null;
  }

  /// The occurrences still to come in the span: Ahead in a current span, the
  /// whole plan in a future one, none in a past one.
  static List<ReportCategoryGroup> _upcoming(CalendarReport report) =>
      switch (report.tense) {
        ReportTense.current => report.ahead,
        ReportTense.future => report.categories,
        ReportTense.past => const [],
      };

  /// The first day of the span's remainder: today in a current span (its
  /// pending occurrences are still to come), the span's start in a plan.
  static DateTime _remainderStart(CalendarReport report) =>
      report.tense == ReportTense.future ? report.span.start : report.today;

  /// The profiled categories' measures with their profiles, in the
  /// measures' order.
  static Iterable<(ReportMeasures, EffectiveProfile)> _profiled(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
  ) sync* {
    for (final measures in report.measures.values) {
      if (!measures.profiled) continue;
      yield (measures, _profileOf(profiles, measures.categoryId));
    }
  }

  static bool _profiledKind(
    CalendarReport report,
    Map<String, EffectiveProfile> profiles,
    String categoryId,
    CategoryKind kind,
  ) =>
      (report.measures[categoryId]?.profiled ?? false) &&
      _profileOf(profiles, categoryId).kind == kind;

  static EffectiveProfile _profileOf(
    Map<String, EffectiveProfile> profiles,
    String categoryId,
  ) => profiles[categoryId] ?? EffectiveProfile.unprofiled;
}
