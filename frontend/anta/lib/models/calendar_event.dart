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

  /// Optional explicit icon override (a key into `CalendarIcons.palette`).
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
    this.perOccurrenceDescriptions = false,
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
    bool? perOccurrenceDescriptions,
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
      perOccurrenceDescriptions:
          perOccurrenceDescriptions ?? this.perOccurrenceDescriptions,
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

  /// Folded [title], computed once. Derived, so it is not a [props] member
  /// and never affects equality — it exists only to spare
  /// `EventAgenda.compareWithinDay` a `toLowerCase()` allocation on its
  /// title tie-break, which every sorted-events surface (the day cache, the
  /// day bars/summary resolvers, the agenda scan) runs on every equal-
  /// priority, equal-time pair.
  late final String titleFold = title.toLowerCase();

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
    perOccurrenceDescriptions,
    time,
    description,
    noteId,
    iconKey,
    colorValue,
    tintIcon,
    priority,
  ];
}
