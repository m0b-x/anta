import '../models/calendar_event.dart';
import '../models/recurrence_rule.dart';

/// Static sync facade over per-occurrence absence marks (**v26**), mirroring
/// [OccurrenceDescriptions], `PublicHolidays` and `CalendarCategories`.
///
/// Exists as a static because the consumers are pure code that cannot await:
/// `EventDayBarProvider.barsFor` and `EventSummaryProvider` build inside
/// `build`, for every visible cell on every rebuild — the same reason
/// `RecurrenceRule.occursOn` reaches for `PublicHolidays.isHoliday` from the
/// model layer.
///
/// Holds **live marks only**; tombstones stay below `EventPresenceService`'s
/// waterline. Republished only by that service; never mutate it from a page or
/// a widget, or the cache and the table desync.
class EventPresence {
  EventPresence._();

  static Map<String, Set<DateTime>> _byEvent = const {};
  static int _revision = 0;

  /// Bumped on every republish. Surfaces that memoize rows by identity
  /// (`UpcomingAgendaView`'s memo over `buildAgendaRows`) fold this into their
  /// cache key — marking a day changes neither the event list nor which days
  /// it occurs on, so nothing else would tell them to rebuild.
  static int get revision => _revision;

  /// Replaces the cache wholesale. [byEvent]'s entries must already be
  /// date-only UTC.
  static void updateCache({required Map<String, Set<DateTime>> byEvent}) {
    _byEvent = byEvent;
    _revision++;
  }

  /// Drops everything. Part of the `DatabaseLifecycle` reset contract: without
  /// this the previous database's marks keep rendering after a switch.
  static void resetCache() {
    _byEvent = const {};
    _revision++;
  }

  /// Whether [event] participates in presence tracking at all.
  ///
  /// Opt-in per event, plus the same gate [OccurrenceDescriptions.appliesTo]
  /// uses: `rule is OneTimeRecurrence` and nothing else. An event that fires on
  /// exactly one day has no attendance to keep, while a
  /// `SpecificDatesRecurrence` — a set of explicit dates — is a list of
  /// distinct occasions and does participate. Never gate on the editor's
  /// `_RepeatMode`, which files specific-dates under `oneTime`.
  static bool appliesTo(CalendarEvent event) =>
      event.tracksPresence && event.rule is! OneTimeRecurrence;

  /// **The** entry point for "was this occurrence missed". Every surface goes
  /// through it, or the grid, the day panel, the agenda and the timeline drift
  /// apart about the same day. O(1): two map probes, no allocation.
  static bool isMissed(String eventId, DateTime day) {
    final forEvent = _byEvent[eventId];
    if (forEvent == null) return false;
    return forEvent.contains(DateTime.utc(day.year, day.month, day.day));
  }
}
