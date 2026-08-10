import '../constants/occurrence_descriptions.dart';
import '../constants/public_holidays.dart';
import '../models/calendar_event.dart';
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
  }) {
    final range = resolveRange(from, to);
    if (range == null) return const [];
    final (start, end) = range;

    final needle = normalizeForSearch(query.trim());
    final candidates = <CalendarEvent>[
      for (final event in events)
        if ((priorities.isEmpty || priorities.contains(event.priority)) &&
            !hiddenCategoryIds.contains(event.categoryId) &&
            _matches(event, needle))
          event,
    ];
    if (candidates.isEmpty) return const [];

    final result = <EventOccurrence>[];
    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      final onDay = <CalendarEvent>[
        for (final event in candidates)
          if (event.occursOn(day) && _matchesOnDay(event, day, needle)) event,
      ];
      if (onDay.isEmpty) continue;
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

  /// Candidate pre-filter, run once per event **before the day is known**.
  ///
  /// Deliberately a *superset* test: with per-occurrence descriptions an event
  /// may match only through text that lives on one specific day, so dropping
  /// it here would make that text unfindable. Anything this admits is narrowed
  /// per day by [_matchesOnDay] inside the scan.
  ///
  /// [needle] must already be folded through [normalizeForSearch].
  static bool _matches(CalendarEvent event, String needle) {
    if (needle.isEmpty) return true;
    if (normalizeForSearch(event.title).contains(needle)) return true;
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

  /// Narrows a [_matches] candidate to the days that really match, so an
  /// override on one day cannot drag the event's every other occurrence into
  /// the results. Short-circuits on the no-query and title-hit paths so the
  /// common case allocates nothing.
  static bool _matchesOnDay(CalendarEvent event, DateTime day, String needle) {
    if (needle.isEmpty) return true;
    if (normalizeForSearch(event.title).contains(needle)) return true;
    final description = OccurrenceDescriptions.descriptionFor(event, day);
    return description != null &&
        normalizeForSearch(description).contains(needle);
  }
}
