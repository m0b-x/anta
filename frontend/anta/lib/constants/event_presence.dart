import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/calendar_event.dart';
import '../models/recurrence_rule.dart';

/// What an explicit `calendar_event_absences` row says about one occurrence
/// (**v37**).
///
/// Before v37 a live row could only mean "missed" and its absence meant
/// "present", which made attendance implicit. With per-event assume-absent
/// defaults the two readings are no longer complements, so the row carries the
/// answer outright and an explicit mark always wins over the event's default.
enum PresenceStatus {
  /// The occurrence was scheduled and not attended.
  missed,

  /// The occurrence was deliberately confirmed as attended.
  present;

  /// Forward-compatible parsing, the [OccurrenceCountStyle.fromName] shape:
  /// unknown or null names fall back to [missed], which is what every pre-v37
  /// row meant. Never throws — a startup `_load` that did would silently clear
  /// every mark in the database.
  static PresenceStatus fromName(String? name) {
    for (final status in values) {
      if (status.name == name) return status;
    }
    return missed;
  }
}

/// Static sync facade over per-occurrence presence marks (**v26**, statuses
/// since **v37**), mirroring [OccurrenceDescriptions], `PublicHolidays` and
/// `CalendarCategories`.
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

  static Map<String, Map<DateTime, PresenceStatus>> _byEvent = const {};
  static int _revision = 0;

  /// Bumped on every republish. Surfaces that memoize rows by identity
  /// (`UpcomingAgendaView`'s memo over `buildAgendaRows`) fold this into their
  /// cache key — marking a day changes neither the event list nor which days
  /// it occurs on, so nothing else would tell them to rebuild.
  static int get revision => _revision;

  /// Replaces the cache wholesale. [byEvent]'s keys must already be date-only
  /// UTC.
  static void updateCache({
    required Map<String, Map<DateTime, PresenceStatus>> byEvent,
  }) {
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
  /// apart about the same day. O(1): two map probes, no allocation — [day]
  /// must already be date-only UTC (the debug assert catches callers that
  /// forget).
  ///
  /// An explicit mark always wins. With none, the answer is the event's own
  /// default via [CalendarEvent.assumesAbsentOn] — `false` for the classic
  /// implicit-attendance event, `true` once assume-absent covers [day]. Never
  /// reads the wall clock: an unconfirmed future day of an assume-absent event
  /// is missed exactly like a past one.
  static bool isMissed(CalendarEvent event, DateTime day) {
    assert(
      day == DateTime.utc(day.year, day.month, day.day),
      'isMissed requires a date-only UTC day',
    );
    final forEvent = _byEvent[event.id];
    final mark = forEvent == null ? null : forEvent[day];
    if (mark != null) return mark == PresenceStatus.missed;
    return event.assumesAbsentOn(day);
  }

  /// Every explicit mark of [eventId], date-only UTC — the [EventSkips.daysFor]
  /// parallel. Exposed for the **5.5** publish-sharing guard, which has to
  /// compare published map *identity*: value equality cannot tell a shared
  /// entry from a deep copy that happens to match.
  @visibleForTesting
  static Map<DateTime, PresenceStatus> marksFor(String eventId) =>
      _byEvent[eventId] ?? const <DateTime, PresenceStatus>{};
}
