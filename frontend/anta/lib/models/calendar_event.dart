import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../constants/event_skips.dart';
import 'recurrence_rule.dart';

enum CalendarEventCategory {
  gym,
  cardio,
  rest,
  holiday,
  competition,
  measurement,
  mobility,
  birthday,
  other,
}

/// Stable id of the default built-in category assigned to brand-new events
/// and used as the reassignment target when a custom category is deleted.
const String kDefaultCategoryId = 'gym';

/// Stable id of the catch-all built-in category.
const String kFallbackCategoryId = 'other';

/// Stable id of the built-in birthday category. Selecting it in the editor
/// defaults a brand-new (still one-time) event to a yearly recurrence.
const String kBirthdayCategoryId = 'birthday';

/// Highest (most important) selectable event priority. Priorities read like
/// P1..P5: **lower numbers rank higher**, sort first in the day bars, the
/// day summary and the agenda, and win the limited day-cell bar slots.
const int kMinEventPriority = 1;

/// Lowest (least important) selectable event priority.
const int kMaxEventPriority = 5;

/// Neutral default priority assigned to brand-new events.
const int kDefaultEventPriority = 3;

/// How a counted occurrence ([CalendarEvent.countOccurrences]) is labelled.
enum OccurrenceCountStyle {
  /// "Day 1" / "Week 3" / "Year 2" — the start day is the first, numbering
  /// runs in the rule's own calendar unit (an every-2-days rule reads
  /// "Day 1, Day 3, Day 5"; a Mon/Wed/Fri weekly rule labels all three
  /// sessions of a week "Week N"). The training-program style, and the
  /// default.
  numbered,

  /// "30 years" / "6 months" — time elapsed since the start date. The
  /// birthday/anniversary style: with the birth date as start, each
  /// occurrence shows the age; the start day itself shows nothing.
  elapsed;

  /// Forward-compatible parsing: unknown/null names fall back to [numbered].
  static OccurrenceCountStyle fromName(String? name) {
    for (final style in values) {
      if (style.name == name) return style;
    }
    return numbered;
  }
}

/// Time-of-day annotation for a [CalendarEvent].
///
/// An event is considered **timed** iff it carries a non-null
/// [CalendarEvent.time]; otherwise it is **all-day**. This is the single
/// source of truth — the persisted `all_day` column in `calendar_events`
/// is derived from this on write and ignored on read.
///
/// [startMinute] is minutes since local midnight in `[0, 1440)`.
/// [durationMinutes] is optional. When `null` the event is a point in
/// time with no defined end; when set it must be `>= 1`. Values larger
/// than `1440 - startMinute` represent an event that crosses midnight —
/// allowed by the model, rendered by the UI.
class EventTime extends Equatable {
  /// Smallest legal start-of-day value (00:00, inclusive).
  static const int minStartMinute = 0;

  /// Smallest illegal start-of-day value (24:00, exclusive).
  static const int minutesPerDay = 1440;

  final int startMinute;
  final int? durationMinutes;

  const EventTime({required this.startMinute, this.durationMinutes})
    : assert(
        startMinute >= minStartMinute && startMinute < minutesPerDay,
        'startMinute must be in [0, 1440)',
      ),
      assert(
        durationMinutes == null || durationMinutes > 0,
        'durationMinutes must be positive when set',
      );

  /// Hour component of the start (`0..23`).
  int get startHour => startMinute ~/ 60;

  /// Minute component of the start (`0..59`).
  int get startMinuteOfHour => startMinute % 60;

  /// End offset in minutes since the same midnight, or `null` when no
  /// duration is set. May exceed `minutesPerDay` for events that span
  /// midnight; presentation is the caller's responsibility.
  int? get endMinute =>
      durationMinutes == null ? null : startMinute + durationMinutes!;

  EventTime copyWith({
    int? startMinute,
    int? durationMinutes,
    bool clearDuration = false,
  }) {
    return EventTime(
      startMinute: startMinute ?? this.startMinute,
      durationMinutes: clearDuration
          ? null
          : (durationMinutes ?? this.durationMinutes),
    );
  }

  @override
  List<Object?> get props => [startMinute, durationMinutes];
}

class CalendarEvent extends Equatable {
  final String id;
  final String title;

  /// Id of the owning [CalendarCategory] (persisted in `calendar_categories`).
  /// For built-in categories this is a stable name like `'gym'`; for custom
  /// categories it is a UUID. An unknown id resolves to a fallback category
  /// at render time, so deleting a category never corrupts its events.
  final String categoryId;

  final DateTime startDate;
  final RecurrenceRule rule;

  /// Optional inclusive upper bound for [rule] occurrences. When non-null
  /// and [day] is strictly after this date (date-only UTC), [occursOn]
  /// returns false regardless of the rule. `null` means "no end".
  ///
  /// Ignored for one-time events (their start *is* their end).
  final DateTime? endDate;

  /// Optional time-of-day annotation. When `null`, the event is treated as
  /// **all-day** (this is also what [allDay] returns). When non-null, the
  /// event is **timed** with the start and optional duration described by
  /// [EventTime].
  final EventTime? time;

  /// Whether [rule] also produces occurrences **before** [startDate]. `false`
  /// (the default, and every pre-v19 event) keeps the classic forward-only
  /// behaviour; `true` extends the rule's periodic phase backwards, so a
  /// yearly event added today also shows in previous years.
  ///
  /// Meaningless for rules whose membership is exact (one-time, explicit date
  /// sets) — see [RecurrenceRule.supportsRetroactive]. [endDate] still clamps
  /// the forward side either way.
  final bool retroactive;

  /// Display-only: when `true`, each occurrence of a periodic rule carries a
  /// count label derived from [startDate], shaped by [countStyle]. Resolved
  /// through [RecurrenceRule.elapsedPeriods]; meaningless (and never
  /// rendered) for rules without a periodic unit. Never affects occurrence
  /// math.
  final bool countOccurrences;

  /// Label shape for counted occurrences — see [OccurrenceCountStyle].
  /// Ignored while [countOccurrences] is `false`.
  final OccurrenceCountStyle countStyle;

  /// Opt-in for presence tracking: skipped occurrences are marked in
  /// `calendar_event_absences` and rendered faded or hidden. Attendance is
  /// implicit, so only the exceptions are stored.
  ///
  /// Never affects occurrence math — a missed day still occurs, still numbers
  /// into [countOccurrences] labels and still exports. Meaningless for a rule
  /// with a single occurrence: the gate every surface uses is
  /// `EventPresence.appliesTo`, i.e. this flag **and**
  /// `rule is! OneTimeRecurrence`.
  final bool tracksPresence;

  /// Inverts the presence default (**v37**): unmarked occurrences read as
  /// **missed** until the user deliberately marks them present, instead of the
  /// implicit attendance [tracksPresence] shipped with.
  ///
  /// Only an explicit `calendar_event_absences` row outranks it, and it never
  /// touches occurrence math — a day still occurs, still counts and still
  /// exports. Meaningless while [tracksPresence] is off; the editor and the
  /// template both clear it in that case rather than letting it linger.
  final bool assumeAbsent;

  /// Optional date-only UTC lower bound for [assumeAbsent]. `null` means the
  /// whole event; a date means the inverted default applies on and after that
  /// day only, so flipping an existing event does not rewrite the meaning of
  /// the history before it.
  ///
  /// Ignored while [assumeAbsent] is `false`. See [assumesAbsentOn].
  final DateTime? assumeAbsentFrom;

  /// Opt-in for per-day description scope: [description] becomes a template
  /// and `calendar_event_occurrences` holds only the days that differ. Off (the
  /// default) means one shared description that edits everywhere at once.
  ///
  /// Replaces the single global setting descriptions shipped behind in v24, so
  /// one event can keep a different note per day while another keeps one. Like
  /// [tracksPresence] it is meaningless for a rule with a single occurrence:
  /// the gate every surface uses is `OccurrenceDescriptions.appliesTo`, i.e.
  /// this flag **and** `rule is! OneTimeRecurrence`. Turning it off never
  /// deletes a day's row — the rows are the user's data and return with the
  /// flag.
  final bool perOccurrenceDescriptions;

  /// Per-event override for membership in the day-cell rail — the calendar's
  /// second presence channel, which unlike the single-event tint can show
  /// every tracked commitment on a day at once.
  ///
  /// Tri-state on purpose. `null` (the default) means *auto*: the event is in
  /// the rail exactly when `EventPresence.appliesTo` holds, so no existing
  /// event changes behaviour and nothing needed a backfill. `true` forces it
  /// in, `false` forces it out. The recurrence guard lives in the shared
  /// `eventInDayRail` predicate rather than here, so `true` on a one-time
  /// event still stays out.
  final bool? showInDayRail;

  /// Whether acknowledging this event's first alert deletes the event
  /// (**v40**).
  ///
  /// A statement about the event's *purpose* — a quick alarm exists only until
  /// it rings — which is why it lives on the event rather than on one of its
  /// alerts. Off by default, offered by the editor only while the event is
  /// one-time and has an alert, and set by the quick-alarm sheet.
  ///
  /// Nothing on the rendering path reads it: [occursOn], the grid, the agenda,
  /// presence and skips are all unaware. The alarm page's Stop and the
  /// reminder's Done are the only readers, and they act through
  /// `CalendarEventService.deleteById`, which tombstones — so the removal
  /// syncs and survives an Undo.
  final bool removeAfterAlert;

  /// Optional free-form description / notes for the event (e.g., "focus on
  /// hamstrings, drop sets on the third exercise"). `null` or empty means
  /// no description. Stored verbatim as markdown source — rendering happens
  /// at display time, nothing pre-rendered is ever persisted.
  final String? description;

  /// Optional link to a workout note (`notes.id`). `null` means the event
  /// has no linked note. Only the id is stored; the note's folder is
  /// resolved at navigation time so the link keeps working if the note is
  /// moved. Opening the note uses the standard editor, so it works whether
  /// the note is viewed in code-editing or markdown-preview mode.
  final String? noteId;

  /// Optional explicit icon override (a key into the `CalendarIcons` catalog).
  /// When `null`, the icon falls back to the category default.
  final String? iconKey;

  /// Optional explicit color override (a 32-bit ARGB value). When `null`, the
  /// event uses its category color. Applies to the whole event, so a recurring
  /// rule colors every occurrence and a multi-date one-time event colors all
  /// its dates. Always tints the day-cell bar; the icon is tinted only when
  /// [tintIcon] is also `true`.
  final int? colorValue;

  /// Whether [colorValue] should also tint the event's icon (day summary).
  /// Ignored when [colorValue] is `null`. Defaults to `true` so a chosen
  /// color affects both the bar and the icon unless the user opts out.
  final bool tintIcon;

  /// Display priority in `[kMinEventPriority, kMaxEventPriority]`, read
  /// like P1..P5: **lower values rank higher**, sort first in the day bars /
  /// day summary / agenda and are kept when the day cell can only show a
  /// limited number of bars.
  final int priority;

  CalendarEvent({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.startDate,
    this.rule = const OneTimeRecurrence(),
    this.endDate,
    this.retroactive = false,
    this.countOccurrences = false,
    this.countStyle = OccurrenceCountStyle.numbered,
    this.tracksPresence = false,
    this.assumeAbsent = false,
    this.assumeAbsentFrom,
    this.perOccurrenceDescriptions = false,
    this.showInDayRail,
    this.removeAfterAlert = false,
    this.time,
    this.description,
    this.noteId,
    this.iconKey,
    this.colorValue,
    this.tintIcon = true,
    this.priority = kDefaultEventPriority,
  });

  /// Derived: `true` iff this event has no [time] annotation. This is the
  /// canonical answer; the persisted `all_day` column is a write-time
  /// mirror used only for SQL filtering, never trusted on read.
  bool get allDay => time == null;

  /// The exact days a one-time or pinned-dates event fires on, or null for a
  /// periodic rule.
  Set<DateTime>? get explicitDates => switch (rule) {
    OneTimeRecurrence() => {startDateUtc},
    SpecificDatesRecurrence(:final dates) => dates,
    _ => null,
  };

  /// This event pinned to exactly [dates]: the earliest becomes the start, one
  /// date is a one-time rule, and a single date drops the flags only a series
  /// can carry — the editor's own save guards, so the two write paths agree.
  CalendarEvent withExplicitDates(Set<DateTime> dates) {
    final sorted =
        dates.map((d) => DateTime.utc(d.year, d.month, d.day)).toSet().toList()
          ..sort();
    if (sorted.isEmpty) return this;
    final single = sorted.length == 1;
    final keepsPresence = !single && tracksPresence;
    final keepsAssumeAbsent = keepsPresence && assumeAbsent;
    return copyWith(
      startDate: sorted.first,
      rule: single
          ? const OneTimeRecurrence()
          : SpecificDatesRecurrence(dates: Set.unmodifiable(sorted.toSet())),
      clearEndDate: true,
      retroactive: false,
      countOccurrences: false,
      tracksPresence: keepsPresence,
      assumeAbsent: keepsAssumeAbsent,
      clearAssumeAbsentFrom: !keepsAssumeAbsent,
      clearShowInDayRail: single,
      perOccurrenceDescriptions: !single && perOccurrenceDescriptions,
      removeAfterAlert: single && removeAfterAlert,
    );
  }

  CalendarEvent copyWith({
    String? id,
    String? title,
    String? categoryId,
    DateTime? startDate,
    RecurrenceRule? rule,
    DateTime? endDate,
    bool? retroactive,
    bool? countOccurrences,
    OccurrenceCountStyle? countStyle,
    bool? tracksPresence,
    bool? assumeAbsent,
    DateTime? assumeAbsentFrom,
    bool? perOccurrenceDescriptions,
    bool? showInDayRail,
    bool? removeAfterAlert,
    EventTime? time,
    String? description,
    String? noteId,
    String? iconKey,
    int? colorValue,
    bool? tintIcon,
    int? priority,
    bool clearEndDate = false,
    bool clearTime = false,
    bool clearDescription = false,
    bool clearNoteId = false,
    bool clearIconKey = false,
    bool clearColorValue = false,
    bool clearShowInDayRail = false,
    bool clearAssumeAbsentFrom = false,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      categoryId: categoryId ?? this.categoryId,
      startDate: startDate ?? this.startDate,
      rule: rule ?? this.rule,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      retroactive: retroactive ?? this.retroactive,
      countOccurrences: countOccurrences ?? this.countOccurrences,
      countStyle: countStyle ?? this.countStyle,
      tracksPresence: tracksPresence ?? this.tracksPresence,
      assumeAbsent: assumeAbsent ?? this.assumeAbsent,
      assumeAbsentFrom: clearAssumeAbsentFrom
          ? null
          : (assumeAbsentFrom ?? this.assumeAbsentFrom),
      perOccurrenceDescriptions:
          perOccurrenceDescriptions ?? this.perOccurrenceDescriptions,
      showInDayRail: clearShowInDayRail
          ? null
          : (showInDayRail ?? this.showInDayRail),
      removeAfterAlert: removeAfterAlert ?? this.removeAfterAlert,
      time: clearTime ? null : (time ?? this.time),
      description: clearDescription ? null : (description ?? this.description),
      noteId: clearNoteId ? null : (noteId ?? this.noteId),
      iconKey: clearIconKey ? null : (iconKey ?? this.iconKey),
      colorValue: clearColorValue ? null : (colorValue ?? this.colorValue),
      tintIcon: tintIcon ?? this.tintIcon,
      priority: priority ?? this.priority,
    );
  }

  /// Date-only UTC of [startDate], computed once. Derived, so it is not a
  /// [props] member and never affects equality — it exists only to spare
  /// [occursOnUtcDay] a `DateTime.utc` allocation on the calendar's hot loop.
  late final DateTime startDateUtc = DateTime.utc(
    startDate.year,
    startDate.month,
    startDate.day,
  );

  /// Date-only UTC of [endDate], or null when unbounded. Derived; not in
  /// [props].
  late final DateTime? endDateUtc = endDate == null
      ? null
      : DateTime.utc(endDate!.year, endDate!.month, endDate!.day);

  /// Date-only UTC of [assumeAbsentFrom], or null when the inverted default
  /// covers the whole event. Derived; not in [props].
  late final DateTime? assumeAbsentFromUtc = assumeAbsentFrom == null
      ? null
      : DateTime.utc(
          assumeAbsentFrom!.year,
          assumeAbsentFrom!.month,
          assumeAbsentFrom!.day,
        );

  /// Folded [title], computed once. Derived, so it is not a [props] member
  /// and never affects equality — it exists only to spare
  /// `EventAgenda.compareWithinDay` a `toLowerCase()` allocation on its
  /// title tie-break, which every sorted-events surface (the day cache, the
  /// day bars/summary resolvers, the agenda scan) runs on every equal-
  /// priority, equal-time pair.
  late final String titleFold = title.toLowerCase();

  /// `'event:<id>'`, computed once. Derived, so it is not a [props] member
  /// and never affects equality — it exists only to spare
  /// `DayBarsResolver.EventDayBarProvider.barsFor` a string interpolation
  /// per event, per cell, per frame across a 42-cell grid. The `'event:'`
  /// prefix keeps this keyspace disjoint from the resolver's other
  /// well-known keys (`'weekend'`, `'holiday'`, `'fasting:<tradition>'`,
  /// `'money'`) — none of them carry a colon-prefixed variable id, so no
  /// event id can ever collide with one.
  late final String barKey = 'event:$id';

  /// Counts [occursOnUtcDay] invocations — every [occursOn] routes through it.
  /// Incremented inside an `assert`, so both the statement and its closure are
  /// stripped from profile and release builds and cost nothing there.
  /// Recurrence expansion is the calendar's hot loop and the model has no
  /// injection seam, so this is what lets a test assert a work budget the way
  /// `StatementCounter` does for SQL.
  @visibleForTesting
  static int debugOccursOnCalls = 0;

  /// Returns true if this event has an occurrence on [day].
  ///
  /// All edge cases (Feb 29 yearly, day 31 monthly, pre-start dates, public
  /// holidays for the workdays/holidays-only rules) are owned by the
  /// underlying [RecurrenceRule]. The [endDate] upper bound, if any, is
  /// applied at this layer because it is orthogonal to the rule shape — and
  /// it applies to [retroactive] events too, which are unbounded only
  /// backwards.
  ///
  /// Cancelled occurrences (**v30**) are subtracted here, and only here. This
  /// is the one choke point every surface already goes through — the day
  /// cache, the agenda scans, the month net, the detail sheet's upcoming
  /// chips, the date pickers — so a skip reaches all of them without any of
  /// them knowing skips exist. Reading a static facade from the model layer
  /// follows the precedent already set by [RecurrenceRule.occursOn], which
  /// consults `PublicHolidays` for the workdays and holidays-only rules.
  ///
  /// Note the deliberate contrast with the hidden-category filter, which is
  /// render-time only, forever: hiding a category changes what you are looking
  /// at, while cancelling an occurrence changes what is there. The
  /// [OneTimeRecurrence] gate keeps a stale row from ever hiding a one-time
  /// event — cancelling its only occurrence is a delete, which the UI offers
  /// separately.
  ///
  /// This normalizes [day] and delegates to [occursOnUtcDay]; a caller that
  /// already holds a date-only UTC day should call that directly.
  bool occursOn(DateTime day) =>
      occursOnUtcDay(DateTime.utc(day.year, day.month, day.day));

  /// [occursOn] for callers that already hold a date-only UTC [day] — the day
  /// cache and the agenda scan both do. Skips the per-call re-normalization of
  /// [day] and of [startDate]/[endDate] (both cached in [startDateUtc] /
  /// [endDateUtc]), which is the calendar hot loop's dominant constant factor.
  /// [day] **must** be date-only UTC; the debug assert catches callers that
  /// forget, and [occursOn] is the normalizing entry point for everyone else.
  bool occursOnUtcDay(DateTime day) {
    assert(() {
      debugOccursOnCalls++;
      return true;
    }());
    assert(
      day == DateTime.utc(day.year, day.month, day.day),
      'occursOnUtcDay requires a date-only UTC day; call occursOn to normalize',
    );
    final end = endDateUtc;
    if (end != null && day.isAfter(end)) return false;
    if (rule is! OneTimeRecurrence && EventSkips.isSkipped(id, day)) {
      return false;
    }
    return rule.occursOn(day, startDateUtc, retroactive: retroactive);
  }

  /// Whether an **unmarked** occurrence on [day] reads as missed (**v37**).
  ///
  /// `assumeAbsent && (assumeAbsentFromUtc == null || !day.isBefore(from))`.
  /// Never reads the wall clock: an unconfirmed future day is absent exactly
  /// like a past one, which is what keeps every read path free of a clock and
  /// of a midnight rollover. Allocation-free, on the same hot path as
  /// [occursOnUtcDay] — [day] must already be date-only UTC.
  ///
  /// Says nothing about explicit marks; `EventPresence.isMissed` is the entry
  /// point that resolves those first and falls through to this.
  bool assumesAbsentOn(DateTime day) {
    if (!assumeAbsent) return false;
    final from = assumeAbsentFromUtc;
    return from == null || !day.isBefore(from);
  }

  @override
  List<Object?> get props => [
    id,
    title,
    categoryId,
    startDate,
    rule,
    endDate,
    retroactive,
    countOccurrences,
    countStyle,
    tracksPresence,
    assumeAbsent,
    assumeAbsentFrom,
    perOccurrenceDescriptions,
    showInDayRail,
    removeAfterAlert,
    time,
    description,
    noteId,
    iconKey,
    colorValue,
    tintIcon,
    priority,
  ];
}
