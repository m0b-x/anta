import 'package:equatable/equatable.dart';

import '../constants/category_kinds.dart';
import 'calendar_appearance.dart';
import 'calendar_event.dart';
import 'category_profile.dart';
import 'date_range.dart';
import 'recurrence_rule.dart';

/// Where a report's span sits against today — it decides what the report can
/// say (T): a past or current span is graded, a future one is a plan.
enum ReportTense {
  /// The span ended before today: every day is counted, nothing is ahead.
  past,

  /// The span holds today: counted to today, the rest is ahead.
  current,

  /// The span starts after today: nothing has happened, nothing can be
  /// missed, so the tiles are Planned · Hours · Tasks.
  future,
}

/// The three shapes of event (§4.1), read from fields the event already
/// has; the shape decides what the report can say about it.
enum ReportShape {
  /// Recurring and tracked: attended and missed per day, aggregated into one
  /// row per event.
  routine,

  /// Recurring, not tracked: a dated row per happened day.
  repeat,

  /// One day or an explicit set of dates: a dated row per day.
  oneOff,
}

/// The shape of [event] (§4.1). Routine wins first, so a tracked set of
/// explicit dates is graded like any other routine (D31).
///
/// Not `EventPresence.appliesTo`, by design: since presence applies to every
/// shape, a tracked one-off would turn into a one-row routine aggregate. It
/// stays a dated one-off whose row may now be missed (the analytics record's
/// §6.5, "Shapes").
ReportShape shapeOf(CalendarEvent event) {
  if (event.tracksPresence && event.rule is! OneTimeRecurrence) {
    return ReportShape.routine;
  }
  final rule = event.rule;
  if (rule is OneTimeRecurrence || rule is SpecificDatesRecurrence) {
    return ReportShape.oneOff;
  }
  return ReportShape.repeat;
}

/// The stat tiles of the Totals card, in the order they are drawn.
enum ReportTile {
  /// What happened to today: kept occurrences, the missed ones excluded
  /// (D26), so the group headers sum to it.
  events,

  /// A future span's every occurrence (T).
  planned,

  /// Kept tracked occurrences of the tracked ones.
  attended,

  /// Missed tracked occurrences, never inside [events].
  missed,

  /// Minutes of the timed occurrences counted.
  hours,

  /// Ticked task items of all task items in the texts counted (D27).
  tasks,
}

/// Task progress in one or more description texts: ticked of total items.
class ReportTaskCount extends Equatable {
  /// Items whose box is `x` or `X`; every other state, custom ones included,
  /// is open.
  final int ticked;

  /// Every task item, whatever its state.
  final int total;

  const ReportTaskCount(this.ticked, this.total);

  @override
  List<Object?> get props => [ticked, total];
}

/// One tile's numbers, with the same measure over the previous period so
/// the page prints a delta without folding twice (D28).
class ReportTileValue extends Equatable {
  /// Which tile this is.
  final ReportTile tile;

  /// The tile's number; minutes for [ReportTile.hours].
  final int value;

  /// The denominator of "21 of 24" (attended) and "9 of 12" (tasks); null
  /// for a plain count.
  final int? of;

  /// [value] over the previous period, or null when there is none.
  final int? previous;

  /// [of] over the previous period, or null when there is none or the tile
  /// has no denominator.
  final int? previousOf;

  const ReportTileValue({
    required this.tile,
    required this.value,
    this.of,
    this.previous,
    this.previousOf,
  });

  @override
  List<Object?> get props => [tile, value, of, previous, previousOf];
}

/// Tense-agnostic counts over one counted range — the numbers every tile is
/// read from, folded once so the previous period's tiles are one more fold of
/// the same shape (D30).
class ReportTotals extends Equatable {
  /// Every occurrence in the range, missed ones included — a plan's count.
  final int occurrences;

  /// Occurrences that were not missed (D26).
  final int kept;

  /// Tracked occurrences marked or assumed missed.
  final int missed;

  /// Kept occurrences of tracked events.
  final int attended;

  /// Every occurrence of a tracked event.
  final int tracked;

  /// Minutes of the kept timed occurrences, plus the confirmed counts-as of
  /// the kept untimed ones (I), in the categories whose hours count.
  final int minutesKept;

  /// Minutes of every timed occurrence — the plan's minutes (D28) — plus
  /// every untimed one's confirmed counts-as, in the categories whose hours
  /// count.
  final int minutesAll;

  /// Ticked task items in the texts counted (D27).
  final int tasksTicked;

  /// Every task item in the texts counted (D27).
  final int tasksTotal;

  /// The counts-as part of [minutesKept] — flagged, because a number the
  /// owner set by rule must be told apart from one the clock measured (I).
  final int nominalKept;

  /// The counts-as part of [minutesAll].
  final int nominalAll;

  const ReportTotals({
    required this.occurrences,
    required this.kept,
    required this.missed,
    required this.attended,
    required this.tracked,
    required this.minutesKept,
    required this.minutesAll,
    required this.tasksTicked,
    required this.tasksTotal,
    this.nominalKept = 0,
    this.nominalAll = 0,
  });

  /// A range with nothing in it.
  static const ReportTotals empty = ReportTotals(
    occurrences: 0,
    kept: 0,
    missed: 0,
    attended: 0,
    tracked: 0,
    minutesKept: 0,
    minutesAll: 0,
    tasksTicked: 0,
    tasksTotal: 0,
  );

  @override
  List<Object?> get props => [
    occurrences,
    kept,
    missed,
    attended,
    tracked,
    minutesKept,
    minutesAll,
    tasksTicked,
    tasksTotal,
    nominalKept,
    nominalAll,
  ];
}

/// One row under a category group. The rows carry ids and facts, never
/// words: the title, time, duration and count label are read from the event
/// at render time, so the page, the digest and the share word them alike.
sealed class ReportRow extends Equatable {
  /// The event the row stands for; a key into [CalendarReport.events].
  final String eventId;

  const ReportRow(this.eventId);
}

/// A routine's aggregate over the counted range ("Gym · 8 of 10 attended ·
/// 8 h") — one row however many days it ran, so a daily routine never makes
/// a thirty-row group.
final class ReportRoutineRow extends ReportRow {
  /// Kept occurrences to the counted end.
  final int attended;

  /// Every occurrence to the counted end.
  final int total;

  /// Minutes of the kept occurrences.
  final int minutes;

  /// The date-only UTC day the row's tap opens (V): the latest attended day
  /// of the counted range, or the latest counted one when none was — the
  /// aggregate stands for many days, and the sheet needs one.
  final DateTime latestDay;

  const ReportRoutineRow({
    required String eventId,
    required this.attended,
    required this.total,
    required this.minutes,
    required this.latestDay,
  }) : super(eventId);

  @override
  List<Object?> get props => [eventId, attended, total, minutes, latestDay];
}

/// One occurrence on one day — a repeat or one-off in the counted range, any
/// shape in a plan, in Ahead or in Missed.
final class ReportDatedRow extends ReportRow {
  /// The occurrence's date-only UTC day.
  final DateTime day;

  /// Whether the occurrence was missed; the page fades the row and offers
  /// the presence button (G).
  final bool missed;

  /// The task progress of the text this row shows (D27), or null when it
  /// holds no task item.
  final ReportTaskCount? tasks;

  const ReportDatedRow({
    required String eventId,
    required this.day,
    this.missed = false,
    this.tasks,
  }) : super(eventId);

  @override
  List<Object?> get props => [eventId, day, missed, tasks];
}

/// One category's share of a card (W): the header's numbers and the rows
/// under it. Categories, Missed and Ahead are all lists of these, so one
/// widget draws all three.
class ReportCategoryGroup extends Equatable {
  /// The category the sampler resolved for the group's events
  /// ([ReportInput.categoryOf]); an event absent from that map groups under
  /// its stored id.
  final String categoryId;

  /// The header's count: in Categories the kept occurrences (D26), so the
  /// headers sum to the Events tile; in Missed and Ahead the rows.
  final int count;

  /// The header's minutes: in Categories the kept occurrences' minutes; in
  /// Ahead the planned minutes; in Missed always 0 — nothing was spent on a
  /// missed day.
  final int minutes;

  /// The header's " · n missed": in Categories the group's missed
  /// occurrences; in Missed every row; in Ahead always 0.
  final int missed;

  /// The group's rows in display order.
  final List<ReportRow> rows;

  const ReportCategoryGroup({
    required this.categoryId,
    required this.count,
    required this.minutes,
    required this.missed,
    required this.rows,
  });

  @override
  List<Object?> get props => [categoryId, count, minutes, missed, rows];
}

/// One column of the Over time chart, by span length (D29).
enum ReportTrendUnit { day, week, month }

/// One column of the Over time chart.
class ReportTrendBucket extends Equatable {
  /// The first day the column covers, date-only UTC — the span's start for
  /// a partial first week or month.
  final DateTime start;

  /// Kept occurrences in the column.
  final int happened;

  /// Missed occurrences in the column.
  final int missed;

  const ReportTrendBucket({
    required this.start,
    required this.happened,
    required this.missed,
  });

  @override
  List<Object?> get props => [start, happened, missed];
}

/// The Over time card's series and its caption facts (D29).
class ReportTrend extends Equatable {
  /// What one column covers.
  final ReportTrendUnit unit;

  /// Columns over the whole span; the ones after today stay at zero, so the
  /// month so far reads as a month.
  final List<ReportTrendBucket> buckets;

  /// The `DateTime.weekday` with the most kept occurrences, or null on a
  /// tie — a caption never names one of two equal days.
  final int? busiestWeekday;

  /// The median start minute of the kept timed occurrences, or null below
  /// the band's threshold.
  final int? usualStartMinute;

  /// The median end minute of those with a duration, or null when none has
  /// one or the start is null.
  final int? usualEndMinute;

  const ReportTrend({
    required this.unit,
    required this.buckets,
    this.busiestWeekday,
    this.usualStartMinute,
    this.usualEndMinute,
  });

  @override
  List<Object?> get props => [
    unit,
    buckets,
    busiestWeekday,
    usualStartMinute,
    usualEndMinute,
  ];
}

/// One category's eleven measures over the span (analytics H, §6.3), folded
/// from the same samples as the groups, whatever its primary — so a goal, an
/// insight or a card can read any of them without a second fold.
///
/// "Kept" is the Categories card's rule: neither missed nor pending (D26,
/// D31); in a plan, every occurrence. "To today" stops at the fold's today.
class ReportMeasures extends Equatable {
  /// The resolved category id the measures are folded under.
  final String categoryId;

  /// The measure that leads: the profile's, else Auto's pick over the
  /// selection's events, after the fallback.
  final ReportMeasure primary;

  /// Whether [primary] is a fallback: the chosen measure had no source over
  /// the span (no task item, no linked note).
  final bool fallbackApplied;

  /// Kept occurrence-days; a multi-day one-off counts a day per day.
  final int count;

  /// Distinct events with a kept day.
  final int events;

  /// Minutes of the kept days: the timed ones' durations plus [nominalMinutes].
  final int minutes;

  /// The confirmed counts-as part of [minutes] (I), never a kind's hint.
  final int nominalMinutes;

  /// Kept tracked days to today, of [tracked].
  final int attended;

  /// Tracked days to today, the missed ones included — [attended]'s
  /// denominator.
  final int tracked;

  /// Cancelled days to today, of [planned].
  final int cancelled;

  /// Occurrence-days to today plus [cancelled] — [cancelled]'s denominator.
  final int planned;

  /// Ticked task items in the texts counted (D27), of [tasksTotal].
  final int tasksTicked;

  /// Every task item in the texts counted.
  final int tasksTotal;

  /// Cents spent: the absolute sum of the negative nets of the linked notes
  /// whose event starts in the span, once per event (P).
  final int spentCents;

  /// Cents received: the sum of the positive nets, once per event.
  final int receivedCents;

  /// Whether any event of the category has an entry in the money the
  /// sampler read — a linked note whose ledger is cached. A `noteId` alone
  /// is not enough: with the money toggle off the ledger holds nothing and
  /// Money falls back to its fallback, never a column of zeros.
  final bool hasMoney;

  /// The latest kept day to today — after a past span from the lookahead
  /// to today, else in the span, else from the lookback before it; null
  /// when none is known. Today's happened or kept day counts: a day marked
  /// kept this morning was seen today. Date-only UTC.
  final DateTime? lastSeenDay;

  /// Days from [lastSeenDay] to today; null with it.
  final int? lastSeenDays;

  /// The lower median of days from a one-off's creation to its first day
  /// (Q); null when no one-off in the span carries its creation day.
  final int? leadTimeDays;

  /// The lower median start minute of the kept timed days; null when none.
  final int? medianStartMinute;

  /// Kept timed days ending after `AnalyticsMetrics.workLateMinute`.
  final int lateDays;

  /// Kept days per weekday, seven bins, index 0 the app's week start —
  /// every kept day, timed or not, unlike Timing's minutes.
  final List<int> weekdayHistogram;

  /// Days from today to [nextDay]; null with it.
  final int? daysUntil;

  /// The first occurrence still to come in the span: today's pending one
  /// (an Expiry due today reads 0 days), else the first after today; null
  /// when none.
  final DateTime? nextDay;

  const ReportMeasures({
    required this.categoryId,
    required this.primary,
    this.fallbackApplied = false,
    this.count = 0,
    this.events = 0,
    this.minutes = 0,
    this.nominalMinutes = 0,
    this.attended = 0,
    this.tracked = 0,
    this.cancelled = 0,
    this.planned = 0,
    this.tasksTicked = 0,
    this.tasksTotal = 0,
    this.spentCents = 0,
    this.receivedCents = 0,
    this.hasMoney = false,
    this.lastSeenDay,
    this.lastSeenDays,
    this.leadTimeDays,
    this.medianStartMinute,
    this.lateDays = 0,
    this.weekdayHistogram = const [0, 0, 0, 0, 0, 0, 0],
    this.daysUntil,
    this.nextDay,
  });

  @override
  List<Object?> get props => [
    categoryId,
    primary,
    fallbackApplied,
    count,
    events,
    minutes,
    nominalMinutes,
    attended,
    tracked,
    cancelled,
    planned,
    tasksTicked,
    tasksTotal,
    spentCents,
    receivedCents,
    hasMoney,
    lastSeenDay,
    lastSeenDays,
    leadTimeDays,
    medianStartMinute,
    lateDays,
    weekdayHistogram,
    daysUntil,
    nextDay,
  ];
}

/// One `#tag` over the span's kept days (Y, §6.9): the people, places and
/// things the owner named, folded from the same samples as the measures.
class ReportTag extends Equatable {
  /// The tag lower-cased, without `#` — what folds `#Ana` and `#ana` into one.
  final String key;

  /// The tag as first typed in the fold's order, without `#`.
  final String label;

  /// Distinct events with a kept day carrying the tag.
  final int events;

  /// Kept days carrying the tag, once per day however often it is typed.
  final int count;

  /// Minutes of those days, timed or counts-as.
  final int minutes;

  /// Cents spent by the tagged events' linked notes, once per event.
  final int spentCents;

  /// Cents received by them, once per event.
  final int receivedCents;

  /// The latest tagged kept day to today; null when every one is ahead of
  /// it (a plan). Date-only UTC.
  final DateTime? lastSeenDay;

  /// The resolved categories of the tagged events, in first-seen order.
  final List<String> categoryIds;

  /// The tagged kept days as dated rows, oldest first, at most
  /// `ReportMetrics.maxListRows`.
  final List<ReportDatedRow> rows;

  const ReportTag({
    required this.key,
    required this.label,
    required this.events,
    required this.count,
    required this.minutes,
    this.spentCents = 0,
    this.receivedCents = 0,
    this.lastSeenDay,
    required this.categoryIds,
    required this.rows,
  });

  @override
  List<Object?> get props => [
    key,
    label,
    events,
    count,
    minutes,
    spentCents,
    receivedCents,
    lastSeenDay,
    categoryIds,
    rows,
  ];
}

/// Where one goal period stands (§6.6, K): pace for the current period, one
/// word for a closed one.
enum GoalState {
  /// *At least*: the target reached. *At most* and *budget*, closed: the
  /// value stayed within it.
  met,

  /// Current: an *at least* value at or past the even-rate expectation, or
  /// an *at most* value at or under it.
  onPace,

  /// Current: an *at least* value under the expectation, or an *at most*
  /// value past it while still within the target.
  behind,

  /// *At most* and *budget*: the value past the target, current or closed.
  over,

  /// Closed *at least*: the target not reached.
  missed,

  /// The current period's first day with nothing in it yet — no pace to read.
  notDue,

  /// The period starts after today: a plan's.
  future,
}

/// One period of a periodic goal (§6.6).
class ReportGoalPeriod extends Equatable {
  /// The period's first day, date-only UTC: the app's week start, a month's
  /// 1st, a year's 1 January, or the day itself.
  final DateTime start;

  /// The period's last day, inclusive, date-only UTC.
  final DateTime end;

  /// The goal's measure over the whole period, in its unit — occurrence
  /// days, events, minutes, attended days, ticked tasks or cents — counting
  /// what was kept to today, or in a [GoalState.future] period what is
  /// planned in it; the days before the span come from the lookback, and a
  /// past span's last period that runs past the span's end takes its later
  /// days from the lookahead, so it is exact to today.
  final int value;

  /// The target at an even rate to today, rounded up — `ceil(target ×
  /// elapsed / days)`, today counted as elapsed; the target itself for a
  /// closed period and 0 for a future one.
  final int expected;

  final GoalState state;

  const ReportGoalPeriod({
    required this.start,
    required this.end,
    required this.value,
    required this.expected,
    required this.state,
  });

  @override
  List<Object?> get props => [start, end, value, expected, state];
}

/// How a gap target reads today (§6.6): within the limit, inside its last
/// `AnalyticsMetrics.gapDueFraction`, or past it.
enum GapState { within, due, overdue }

/// A *max gap* target's reading (§6.6, O).
class ReportGapState extends Equatable {
  /// Days from the last kept day to today — `ReportMeasures.lastSeenDays`;
  /// `AnalyticsMetrics.lookbackDays` when the category occurred but no kept
  /// day lies in the window read, with [beyondLookback] set.
  final int daysSince;

  /// The most days allowed between two kept days: the target's value.
  final int limit;

  /// Overdue past [limit], due from `limit × (1 − gapDueFraction)` days,
  /// within otherwise. A limit of `lookbackDays` or more can never read
  /// overdue beyond the lookback, since [daysSince] is a floor there.
  final GapState state;

  /// Whether [daysSince] is a floor — "over a year": the last kept day lies
  /// before the lookback, or there never was one, while the category has
  /// occurred. A car service last done 400 days ago still goes overdue.
  final bool beyondLookback;

  const ReportGapState({
    required this.daysSince,
    required this.limit,
    required this.state,
    this.beyondLookback = false,
  });

  @override
  List<Object?> get props => [daysSince, limit, state, beyondLookback];
}

/// One category's target judged over the span (§6.6, J, K).
class ReportGoal extends Equatable {
  /// The resolved category id.
  final String categoryId;

  /// The unit the target counts: the category's resolved primary (AD).
  /// Count, Events, Hours, Attendance, Tasks and Money have a period value
  /// of their own; any other primary counts kept days.
  final ReportMeasure measure;

  final ReportTarget target;

  /// The periods overlapping the span's counted range, oldest first — the
  /// current one included; one period when the span is shorter than it, as
  /// a week seen under a monthly target. Empty for a *max gap* target.
  final List<ReportGoalPeriod> periods;

  /// Consecutive closed periods met, counted back from the last closed one,
  /// over the whole periods of the 366-day lookback and the span's own
  /// closed periods, a past span's last one included (valued from the
  /// lookahead) — never a period before the category's first event; 0 when
  /// the last closed one was not met and for a *max gap* target.
  final int streak;

  /// The gap reading of a *max gap* target; null for every other kind, and
  /// for a *max gap* whose category has not occurred at all up to today —
  /// nothing to measure.
  final ReportGapState? gap;

  const ReportGoal({
    required this.categoryId,
    required this.measure,
    required this.target,
    this.periods = const [],
    this.streak = 0,
    this.gap,
  });

  @override
  List<Object?> get props => [
    categoryId,
    measure,
    target,
    periods,
    streak,
    gap,
  ];
}

/// What put a row on the Due soon card (§6.8, O).
enum ReportDueKind {
  /// A *max gap* goal due or overdue.
  gap,

  /// An Expiry-kind event's day ahead or passed unmarked.
  expiry,

  /// A Bill or Deadline day passed with no kept mark.
  unmarked,

  /// A Bill's day in a plan.
  upcoming,
}

/// A Due soon row's urgency, the card's first order key.
enum ReportDueState { overdue, due, unmarked, upcoming }

/// One row of the Due soon card (§6.8).
class ReportDueRow extends Equatable {
  /// The resolved category id.
  final String categoryId;

  /// The event the row opens: the occurrence's, or for a gap the event kept
  /// last.
  final String eventId;

  /// The day the row is about, date-only UTC: the occurrence's, or for a gap
  /// the limit's last day (the last kept day plus the limit).
  final DateTime day;

  final ReportDueKind kind;
  final ReportDueState state;

  /// Days, never negative: past the limit (overdue gap), left inside it (due
  /// gap), since the day (overdue Expiry, unmarked) or until it (upcoming).
  final int days;

  /// A gap row's `ReportGapState.beyondLookback`: [days] counts from the
  /// lookback's floor, so the card says "over a year" rather than a number.
  final bool beyondLookback;

  const ReportDueRow({
    required this.categoryId,
    required this.eventId,
    required this.day,
    required this.kind,
    required this.state,
    required this.days,
    this.beyondLookback = false,
  });

  @override
  List<Object?> get props => [
    categoryId,
    eventId,
    day,
    kind,
    state,
    days,
    beyondLookback,
  ];
}

/// The When heatmap's facts (§6.10): the minutes of the kept timed days by
/// weekday and hour.
class ReportWhen extends Equatable {
  static const int hoursPerDay = 24;
  static const int cellCount = 7 * hoursPerDay;

  /// [cellCount] minutes, row-major: row 0 is the app's week start, column
  /// the hour 0–23. An occurrence adds the minutes it covers inside each
  /// hour, and one running past midnight continues on the next weekday's
  /// row (the week's last row wraps to its first).
  final List<int> cells;

  /// The kept samples with a duration that filled [cells]; a time with no
  /// duration covers no minute and is not counted.
  final int timedDays;

  /// The row (0–6 from the week start) with the most minutes, the earliest
  /// on a tie; null under `AnalyticsMetrics.whenMinTimedSamples` timed days.
  final int? busiestWeekday;

  /// The hour (0–23) with the most minutes over every row, the earliest on
  /// a tie; null with [busiestWeekday].
  final int? busiestHour;

  const ReportWhen({
    required this.cells,
    required this.timedDays,
    this.busiestWeekday,
    this.busiestHour,
  });

  @override
  List<Object?> get props => [cells, timedDays, busiestWeekday, busiestHour];
}

/// The report of one span over one selection — the one model the page, the
/// report digest's words and the Markdown share all read (U), so a number
/// can never disagree between them.
class CalendarReport extends Equatable {
  /// The period reported on, inclusive.
  final DateRange span;

  /// The day the report was folded on, date-only UTC.
  final DateTime today;

  /// Where [span] sits against [today].
  final ReportTense tense;

  /// The last day counted: today in a current span, the span's end otherwise
  /// — the caption's "To 30 October".
  final DateTime countedTo;

  /// The span the deltas compare against, or null when there is none.
  final DateRange? previousSpan;

  /// The part of [previousSpan] the deltas counted (D28): the whole of it in
  /// the past and future tenses, its first days in the current one. The
  /// caption names this, not the whole previous period, when they differ —
  /// "against Sep 1 – 15" beside a month so far (D36.3).
  final DateRange? previousCounted;

  /// Every event of the selection by id, so a row is worded from its event.
  final Map<String, CalendarEvent> events;

  /// The Totals card's tiles in display order; decided by the selection, not
  /// the period (D15), so stepping never reshuffles the grid.
  final List<ReportTileValue> tiles;

  /// Skipped days in the counted range (`span.start .. countedTo`), never
  /// one after today — the caption's "2 skipped"; they are never
  /// occurrences.
  final int skippedDays;

  /// Occurrences after today in the span, plus today's pending ones (D31) —
  /// the caption's "2 ahead".
  final int aheadCount;

  /// One group per category that has an occurrence counted, by count.
  final List<ReportCategoryGroup> categories;

  /// The Over time series, or null when there is too little to chart or the
  /// span is a plan.
  final ReportTrend? trend;

  /// The missed days to today, grouped by category; empty in a plan.
  final List<ReportCategoryGroup> missed;

  /// The occurrences [aheadCount] counts, grouped by category; empty in a
  /// plan, whose Categories groups already are the plan.
  final List<ReportCategoryGroup> ahead;

  /// The eleven measures (H) of every category with an event in the
  /// selection, whether or not it occurs in the span, in the catalogue's
  /// order.
  final Map<String, ReportMeasures> measures;

  /// The top tags (Y), at most `AnalyticsMetrics.tagRows`: the most events
  /// first, then the most days, then the key.
  final List<ReportTag> tags;

  /// The counts-as minutes inside the Hours tile's value (I) — its "incl.
  /// 6 h counted as" footnote; 0 when nothing was counted by rule.
  final int nominalMinutes;

  /// Monday-to-Friday days of [span] that are no public holiday (T); 0 when
  /// the caller did not resolve them.
  final int workingDays;

  /// Public holidays in [span] (T); 0 when the caller did not resolve them.
  final int publicHolidays;

  /// One goal per category of the selection whose effective profile has a
  /// target, in [measures]' order; empty when none has (§6.6).
  final List<ReportGoal> goals;

  /// The Due soon rows (§6.8): overdue, due, unmarked, then upcoming, each
  /// by [ReportDueRow.days], at most `AnalyticsMetrics.dueSoonRows`.
  final List<ReportDueRow> dueSoon;

  /// The Due soon rows beyond the cap — the card's "n more".
  final int dueSoonMore;

  /// Minutes per life area (§6.10, M): each category whose effective profile
  /// counts hours adds its `ReportMeasures.minutes`, counts-as included, to
  /// its area; only areas with minutes, in [LifeArea]'s order.
  final Map<LifeArea, int> balance;

  /// The When heatmap's facts (§6.10); every fold sets it, null only in a
  /// report built by hand.
  final ReportWhen? when;

  const CalendarReport({
    required this.span,
    required this.today,
    required this.tense,
    required this.countedTo,
    this.previousSpan,
    this.previousCounted,
    required this.events,
    required this.tiles,
    required this.skippedDays,
    required this.aheadCount,
    required this.categories,
    this.trend,
    required this.missed,
    required this.ahead,
    this.measures = const {},
    this.tags = const [],
    this.nominalMinutes = 0,
    this.workingDays = 0,
    this.publicHolidays = 0,
    this.goals = const [],
    this.dueSoon = const [],
    this.dueSoonMore = 0,
    this.balance = const {},
    this.when,
  });

  /// Whether the span holds no occurrence at all — the page dims Totals and
  /// says so in one caption.
  bool get isEmpty => categories.isEmpty && aheadCount == 0;

  /// Where [span] sits against [today] (T) — the one rule the fold and its
  /// sampler share, so a previous period is counted the way the report is.
  /// Both days date-only UTC.
  static ReportTense tenseOf({
    required DateRange span,
    required DateTime today,
  }) {
    if (span.end.isBefore(today)) return ReportTense.past;
    if (span.start.isAfter(today)) return ReportTense.future;
    return ReportTense.current;
  }

  /// The last day a fold of [span] counts: today when the span holds it, the
  /// span's end otherwise — a past span is counted whole, and a plan counts
  /// its every occurrence. Both days date-only UTC.
  static DateTime countedToOf({
    required DateRange span,
    required DateTime today,
  }) {
    return tenseOf(span: span, today: today) == ReportTense.current
        ? today
        : span.end;
  }

  @override
  List<Object?> get props => [
    span,
    today,
    tense,
    countedTo,
    previousSpan,
    previousCounted,
    events,
    tiles,
    skippedDays,
    aheadCount,
    categories,
    trend,
    missed,
    ahead,
    measures,
    tags,
    nominalMinutes,
    workingDays,
    publicHolidays,
    goals,
    dueSoon,
    dueSoonMore,
    balance,
    when,
  ];
}

/// One occurrence handed to the builder — the boundary between the facades
/// and the pure fold (§4.7), so the builder never reads a static cache.
class ReportSample extends Equatable {
  /// The occurring event.
  final String eventId;

  /// The occurrence's date-only UTC day; skipped days never arrive.
  final DateTime day;

  /// Whether the occurrence was missed; the sampler sets it only for tracked
  /// days up to today.
  final bool missed;

  /// Whether this is a tracked event's occurrence on today with no explicit
  /// presence mark (D31) — the sampler decides it from
  /// `EventPresence.marksFor(eventId)[today] == null`. An assume-absent
  /// default treats today like a past day, so without it a morning report
  /// would count tonight's session as missed before it could happen: a past
  /// or current fold reads a pending sample as ahead; a plan ignores it.
  final bool pending;

  const ReportSample({
    required this.eventId,
    required this.day,
    this.missed = false,
    this.pending = false,
  });

  @override
  List<Object?> get props => [eventId, day, missed, pending];
}

/// Everything one fold reads — the sampler's output, so the builder takes
/// no clock, no service and no formatter.
class ReportInput extends Equatable {
  /// The period reported on, inclusive, date-only UTC.
  final DateRange span;

  /// The day of the fold, date-only UTC.
  final DateTime today;

  /// The app's week start, for week-aligned trend columns.
  final CalendarWeekStart weekStart;

  /// Every event in the chosen categories, whether or not it occurs in the
  /// span — the tile set is decided by the selection (D15).
  final Map<String, CalendarEvent> events;

  /// The resolved category id per event id, filled by the sampler from the
  /// catalogue so the fold never reads the static one; an event missing here
  /// groups under its stored id.
  final Map<String, String> categoryOf;

  /// The span's occurrences.
  final List<ReportSample> samples;

  /// Every per-day description text of the scoped events, on every day —
  /// not only the span's — by event id and date-only UTC day, the
  /// `OccurrenceDescriptions` shape. All days, because the Tasks tile is
  /// decided by the selection (D15) and its gate must see them all; rows and
  /// totals look a text up by their own day.
  final Map<String, Map<DateTime, String>> overrides;

  /// Skipped days in the counted range (`span.start .. countedTo`), never
  /// one after today, passed through to the caption.
  final int skippedDays;

  /// The catalogue's category order, breaking ties between equal groups.
  final List<String> categoryOrder;

  /// The whole previous period the deltas compare against — the one the
  /// caption names ("vs September") — or null when there is none.
  final DateRange? previousSpan;

  /// The part of [previousSpan] [previousTotals] were folded over, passed
  /// through to the caption; null when there is no previous period.
  final DateRange? previousCounted;

  /// The previous period's totals, folded by the caller with
  /// `CalendarReportBuilder.foldTotals` over (D28): in the past tense the
  /// whole [previousSpan]; in the current tense `previousSpan.start ..
  /// previousSpan.start + (countedTo − span.start)`, clamped to
  /// `previousSpan.end`, so a month so far meets the same days of the month
  /// before; in the future tense the whole [previousSpan], of which the fold
  /// reads only `occurrences`, `minutesAll`, `tasksTicked` and `tasksTotal`.
  /// Null when there is no previous period.
  final ReportTotals? previousTotals;

  /// Each resolved category's effective profile, resolved by the sampler so
  /// the fold never reads the facade; a category absent here folds as
  /// [EffectiveProfile.unprofiled] — today's report.
  final Map<String, EffectiveProfile> profiles;

  /// The skipped days [skippedDays] counts, as samples, so Cancelled folds
  /// per category; never one after today.
  final List<ReportSample> cancelled;

  /// The linked note's net cents by event id, only for events whose note's
  /// ledger is cached (P); an event absent here has no money to read.
  final Map<String, int> money;

  /// The last kept day before [span] by resolved category id, date-only UTC,
  /// from the sampler's lookback — present only for the categories whose
  /// profile reads a gap (R).
  final Map<String, DateTime> lastSeenBefore;

  /// The kept and missed samples of the `AnalyticsMetrics.lookbackDays`
  /// before [span], never past today, by resolved category id — present
  /// only for the categories whose profile has a target or reads a gap (R).
  /// Cancelled days and today's pending ones never arrive. The goals read
  /// them for their streaks and for a period that starts before the span.
  final Map<String, List<ReportSample>> lookback;

  /// The kept and missed samples after a past [span] — `span.end + 1` to
  /// [today] — by resolved category id, for the categories [lookback]
  /// holds; empty when the span reaches today. Cancelled days and today's
  /// pending ones never arrive. Without them a Last-month report would read
  /// a category kept last week as unseen since the month, and judge a goal
  /// period running past the span's end on its first days alone.
  final Map<String, List<ReportSample>> lookahead;

  /// Monday-to-Friday days of [span] that are no public holiday (T); 0 when
  /// not resolved.
  final int workingDays;

  /// Public holidays in [span] (T); 0 when not resolved.
  final int publicHolidays;

  const ReportInput({
    required this.span,
    required this.today,
    required this.weekStart,
    required this.events,
    required this.categoryOf,
    required this.samples,
    this.overrides = const {},
    this.skippedDays = 0,
    required this.categoryOrder,
    this.previousSpan,
    this.previousCounted,
    this.previousTotals,
    this.profiles = const {},
    this.cancelled = const [],
    this.money = const {},
    this.lastSeenBefore = const {},
    this.lookback = const {},
    this.lookahead = const {},
    this.workingDays = 0,
    this.publicHolidays = 0,
  });

  @override
  List<Object?> get props => [
    span,
    today,
    weekStart,
    events,
    categoryOf,
    samples,
    overrides,
    skippedDays,
    categoryOrder,
    previousSpan,
    previousCounted,
    previousTotals,
    profiles,
    cancelled,
    money,
    lastSeenBefore,
    lookback,
    lookahead,
    workingDays,
    publicHolidays,
  ];
}
