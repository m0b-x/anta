import 'package:equatable/equatable.dart';

import '../constants/event_presence.dart';
import 'calendar_appearance.dart';
import 'calendar_event.dart';
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

/// The shape of [event] (§4.1). Routine wins first, through the same gate
/// presence uses everywhere, so a tracked set of explicit dates is graded
/// like any other routine.
ReportShape shapeOf(CalendarEvent event) {
  if (EventPresence.appliesTo(event)) return ReportShape.routine;
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

  /// Minutes of the kept timed occurrences.
  final int minutesKept;

  /// Minutes of every timed occurrence — the plan's minutes (D28).
  final int minutesAll;

  /// Ticked task items in the texts counted (D27).
  final int tasksTicked;

  /// Every task item in the texts counted (D27).
  final int tasksTotal;

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

  const ReportRoutineRow({
    required String eventId,
    required this.attended,
    required this.total,
    required this.minutes,
  }) : super(eventId);

  @override
  List<Object?> get props => [eventId, attended, total, minutes];
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
  ];
}
