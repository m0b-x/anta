import '../constants/fasting_calendar.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/public_holidays.dart';
import '../models/calendar_event.dart';
import '../models/recurrence_rule.dart';
import '../models/upcoming_agenda_filters.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;

/// One dated occurrence of a [CalendarEvent] inside an agenda range.
///
/// A recurring event produces one [EventOccurrence] per matching day, so the
/// same [event] instance can appear many times under different [day] values.
class EventOccurrence {
  final CalendarEvent event;

  /// Date-only UTC day this occurrence falls on, matching the normalization
  /// used by [CalendarEvent.occursOn] and the calendar bloc.
  final DateTime day;

  const EventOccurrence({required this.event, required this.day});
}

/// Expands recurrence rules across a date range into a flat, ordered agenda.
///
/// Deliberately kept out of `CalendarBloc`: the bloc's per-day cache backs
/// `TableCalendar.eventLoader` and must stay O(1), while an agenda query is a
/// one-shot O(days x events) scan driven by user input. Every day check is the
/// same O(1) [CalendarEvent.occursOn] the day cache uses, so the two surfaces
/// can never disagree about which days an event falls on.
abstract final class EventAgenda {
  /// Upper bound on how many days a single query may span. Bounds the scan
  /// regardless of what range a caller (or a custom date picker) asks for.
  static const int maxRangeDays = 366;

  /// Occurrences between [from] and [to] inclusive, ordered by day and then
  /// by the same rules the day summary panel uses within a day.
  ///
  /// Filters are applied to the event set once, before the day scan:
  /// [hiddenCategoryIds] mirrors the calendar's category filter,
  /// [priorities] keeps only the selected priorities (**empty means every
  /// priority** — the filter is off, not "nothing matches"), and [query]
  /// matches case- and diacritic-insensitively against title and
  /// description (via [normalizeForSearch], the same fold the note search
  /// uses, so "sarbatoare" finds "Sărbătoare" here too).
  static List<EventOccurrence> occurrencesInRange({
    required List<CalendarEvent> events,
    required DateTime from,
    required DateTime to,
    Set<String> hiddenCategoryIds = const {},
    Set<int> priorities = const {},
    String query = '',
    AgendaEventType eventType = AgendaEventType.all,
  }) {
    // The events layer is hidden — no event occurrences, so the scan is skipped
    // entirely and only the annotation rows (holidays/fasting) interleave.
    if (eventType == AgendaEventType.none) return const [];
    final range = resolveRange(from, to);
    if (range == null) return const [];
    final (start, end) = range;

    final needle = normalizeForSearch(query.trim());
    // Ids whose **title** matches. A title belongs to the event, not to one of
    // its days, so these need no per-day narrowing below — which also keeps
    // the title normalization to once per event instead of once per
    // (event, day).
    final titleMatched = <String>{};
    final candidates = <CalendarEvent>[];
    for (final event in events) {
      final isOneTime = event.rule is OneTimeRecurrence;
      if (eventType == AgendaEventType.recurring && isOneTime) continue;
      if (eventType == AgendaEventType.oneTime && !isOneTime) continue;
      if (priorities.isNotEmpty && !priorities.contains(event.priority)) {
        continue;
      }
      if (hiddenCategoryIds.contains(event.categoryId)) continue;
      if (needle.isEmpty) {
        candidates.add(event);
        continue;
      }
      final byTitle = normalizeForSearch(event.title).contains(needle);
      if (byTitle) titleMatched.add(event.id);
      if (byTitle || _descriptionCandidate(event, needle)) {
        candidates.add(event);
      }
    }
    if (candidates.isEmpty) return const [];

    // Prune candidates that provably cannot occur inside [start, end] before
    // the O(days x candidates) scan — a narrow window against a large store
    // leaves only a small fraction in play. Every survivor is still validated
    // through `occursOnUtcDay`, so this only ever drops non-occurrences.
    //
    // One-time events occur on exactly one day, so they are bucketed by it and
    // never enter the per-day scan: a one-time event is never skipped and its
    // rule is a bare `day == start`, so once the (rare) end-date clamp is
    // honoured its placement on that day is certain.
    final recurring = <CalendarEvent>[];
    final oneTimeByDay = <DateTime, List<CalendarEvent>>{};
    for (final event in candidates) {
      final endUtc = event.endDateUtc;
      // endDate clamps every rule at the model layer, so a series that ended
      // before the window has nothing left inside it.
      if (endUtc != null && endUtc.isBefore(start)) continue;
      final rule = event.rule;
      if (rule is OneTimeRecurrence) {
        final day = event.startDateUtc;
        if (day.isBefore(start) || day.isAfter(end)) continue;
        if (endUtc != null && day.isAfter(endUtc)) continue;
        (oneTimeByDay[day] ??= <CalendarEvent>[]).add(event);
        continue;
      }
      // Only the start-guarded rules can be pruned by their start.
      // `SpecificDatesRecurrence` has no pre-start guard — its dates may fall
      // before `startDate` — so it stays in the scan, where its
      // allocation-free set lookup is already cheap.
      if (rule is! SpecificDatesRecurrence &&
          !event.retroactive &&
          event.startDateUtc.isAfter(end)) {
        continue;
      }
      recurring.add(event);
    }
    if (recurring.isEmpty && oneTimeByDay.isEmpty) return const [];

    final result = <EventOccurrence>[];
    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      List<CalendarEvent>? onDay;
      for (final event in recurring) {
        if (event.occursOnUtcDay(day) &&
            (needle.isEmpty ||
                titleMatched.contains(event.id) ||
                _dayDescriptionMatches(event, day, needle))) {
          (onDay ??= <CalendarEvent>[]).add(event);
        }
      }
      final oneTimeToday = oneTimeByDay[day];
      if (oneTimeToday != null) {
        for (final event in oneTimeToday) {
          // The occurrence here is certain; only the search query narrows it,
          // and a one-time event's description never varies by day.
          if (needle.isEmpty ||
              titleMatched.contains(event.id) ||
              _dayDescriptionMatches(event, day, needle)) {
            (onDay ??= <CalendarEvent>[]).add(event);
          }
        }
      }
      if (onDay == null) continue;
      onDay.sort(compareWithinDay);
      for (final event in onDay) {
        result.add(EventOccurrence(event: event, day: day));
      }
    }
    return List.unmodifiable(result);
  }

  /// Public holidays falling inside the range, in ascending order.
  ///
  /// Kept separate from [occurrencesInRange] because a holiday is a property
  /// of the day rather than an event: it has no id, no category and nothing
  /// to edit. Callers that opt in merge the two lists when grouping by day.
  static List<DateTime> holidayDaysInRange({
    required DateTime from,
    required DateTime to,
  }) {
    final range = resolveRange(from, to);
    if (range == null) return const [];
    final (start, end) = range;
    final days = <DateTime>[];
    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      if (PublicHolidays.isHoliday(day)) days.add(day);
    }
    return days;
  }

  /// Fasting days falling inside the range, in ascending order. Empty when no
  /// fasting tradition is configured ([FastingCalendar.isEnabled] false), so a
  /// caller that toggles it on pays nothing until the user opts in. Mirrors
  /// [holidayDaysInRange]; both are properties of the day, not events.
  static List<DateTime> fastingDaysInRange({
    required DateTime from,
    required DateTime to,
  }) {
    if (!FastingCalendar.isEnabled) return const [];
    final range = resolveRange(from, to);
    if (range == null) return const [];
    final (start, end) = range;
    final days = <DateTime>[];
    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      if (FastingCalendar.isFastingDay(day)) days.add(day);
    }
    return days;
  }

  /// Normalizes and clamps a requested range, or `null` when it is empty.
  /// Shared so the event scan and the holiday scan can never disagree about
  /// which days are in view.
  static (DateTime, DateTime)? resolveRange(DateTime from, DateTime to) {
    final start = dateOnly(from);
    final requestedEnd = dateOnly(to);
    if (requestedEnd.isBefore(start)) return null;
    final maxEnd = start.add(const Duration(days: maxRangeDays - 1));
    return (start, requestedEnd.isAfter(maxEnd) ? maxEnd : requestedEnd);
  }

  /// Ordering of two events falling on the same day: higher priority first —
  /// P1 before P5, so **ascending** on the stored number (matching the
  /// day-cell bar stack) — then all-day before timed, then by start time,
  /// then by title so the order is stable across rebuilds.
  ///
  /// The **single comparator** for same-day event order — the agenda sorts
  /// occurrences with it and `EventSummaryProvider` emits day-panel entries
  /// through it, so the two surfaces cannot disagree.
  static int compareWithinDay(CalendarEvent a, CalendarEvent b) {
    final byPriority = a.priority.compareTo(b.priority);
    if (byPriority != 0) return byPriority;
    final aTime = a.time;
    final bTime = b.time;
    if (aTime == null && bTime != null) return -1;
    if (aTime != null && bTime == null) return 1;
    if (aTime != null && bTime != null) {
      final byStart = aTime.startMinute.compareTo(bTime.startMinute);
      if (byStart != 0) return byStart;
    }
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
  }

  /// Date-only UTC normalization, matching `CalendarBloc._dateOnly`.
  static DateTime dateOnly(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  /// Description half of the candidate pre-filter, run once per event
  /// **before the day is known** (the title half is inlined at the call site
  /// so a title hit can be remembered).
  ///
  /// Deliberately a *superset* test: with per-occurrence descriptions an event
  /// may match only through text living on one specific day, so dropping it
  /// here would make that text unfindable. Whatever this admits is narrowed
  /// per day by [_dayDescriptionMatches] inside the scan.
  ///
  /// [needle] must already be folded through [normalizeForSearch].
  static bool _descriptionCandidate(CalendarEvent event, String needle) {
    final description = event.description;
    if (description != null &&
        normalizeForSearch(description).contains(needle)) {
      return true;
    }
    // Cheap existence probe — the per-day pass decides which days actually
    // match. Without it, an event whose only hit is a single day's override
    // never reaches the scan.
    return OccurrenceDescriptions.appliesTo(event) &&
        OccurrenceDescriptions.hasAnyOverride(event.id);
  }

  /// Whether this event's description **on this day** matches, so an override
  /// on one day cannot drag the event's every other occurrence into the
  /// results — and, symmetrically, a day whose override no longer mentions the
  /// needle drops out even though the template still does.
  ///
  /// Only reached for candidates whose title did not already match, so no
  /// title normalization happens per day.
  static bool _dayDescriptionMatches(
    CalendarEvent event,
    DateTime day,
    String needle,
  ) {
    final description = OccurrenceDescriptions.descriptionFor(event, day);
    return description != null &&
        normalizeForSearch(description).contains(needle);
  }
}
