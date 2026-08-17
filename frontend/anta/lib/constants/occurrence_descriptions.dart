import '../models/calendar_event.dart';
import '../models/recurrence_rule.dart';

/// Static sync facade over per-occurrence description overrides (**v24**,
/// opted into per event since **v28**), mirroring [EventPresence],
/// `PublicHolidays` and `CalendarCategories.updateCache`.
///
/// Exists as a static because the consumers are pure code that cannot await:
/// `EventSummaryProvider` builds rows inside `build`, and `EventAgenda` is a
/// top-level utility whose signature is shared by every call site — the same
/// reason `RecurrenceRule.occursOn` reaches for `PublicHolidays.isHoliday`
/// from the model layer.
///
/// Holds **live overrides only**; tombstones stay below
/// `EventOccurrenceService`'s waterline. Republished only by that service;
/// never mutate it from a page or a widget, or the cache and the table desync.
class OccurrenceDescriptions {
  OccurrenceDescriptions._();

  static Map<String, Map<DateTime, String>> _byEvent = const {};
  static int _revision = 0;

  /// Bumped on every republish. Surfaces that memoize rows built from resolved
  /// descriptions (`UpcomingAgendaView`'s memo over `buildAgendaRows`) fold
  /// this into their cache key — the occurrence *set* is unchanged by a text
  /// edit, so nothing else would tell them to rebuild.
  static int get revision => _revision;

  /// Replaces the cache wholesale. [byEvent]'s inner keys must already be
  /// date-only UTC.
  static void updateCache({
    required Map<String, Map<DateTime, String>> byEvent,
  }) {
    _byEvent = byEvent;
    _revision++;
  }

  /// Drops everything. Part of the `DatabaseLifecycle` reset contract: without
  /// this the previous database's overrides keep rendering after a switch.
  static void resetCache() {
    _byEvent = const {};
    _revision++;
  }

  /// Whether [event] participates in per-occurrence descriptions at all.
  ///
  /// Opt-in per event via [CalendarEvent.perOccurrenceDescriptions] (v28 — the
  /// global switch v24 shipped behind is gone), plus the same gate
  /// [EventPresence.appliesTo] uses: `rule is OneTimeRecurrence` and nothing
  /// else. An event that fires on exactly one day has nothing to separate,
  /// while a `SpecificDatesRecurrence` — a set of explicit dates — is a list of
  /// distinct occasions and does participate. Never gate on the editor's
  /// `_RepeatMode`, which files specific-dates under `oneTime`.
  ///
  /// Because [descriptionFor] calls this internally, the detail sheet, the
  /// day-panel badge, the agenda narrowing and both row surfaces follow the
  /// event's flag with no edit of their own.
  static bool appliesTo(CalendarEvent event) =>
      event.perOccurrenceDescriptions && event.rule is! OneTimeRecurrence;

  /// This day's override, or null when the day has none.
  ///
  /// A **live** row always wins, **including when its text is empty** — that is
  /// what keeps a deliberately blanked day blank instead of falling back to the
  /// template. Only a missing row yields null, and "reset this day" gets there
  /// by **tombstoning** the row rather than writing `''`.
  static String? overrideFor(String eventId, DateTime day) {
    final forEvent = _byEvent[eventId];
    if (forEvent == null) return null;
    return forEvent[DateTime.utc(day.year, day.month, day.day)];
  }

  /// Whether [event] has any override at all. Used by the agenda's candidate
  /// pre-filter, which runs before the day is known and so must not drop an
  /// event whose match lives in one day's text.
  static bool hasAnyOverride(String eventId) {
    final forEvent = _byEvent[eventId];
    return forEvent != null && forEvent.isNotEmpty;
  }

  /// **The** entry point for "what description does this event show on this
  /// day". Every surface goes through it so the template fallback can never
  /// drift between the day panel, the agenda, the detail sheet and search.
  static String? descriptionFor(CalendarEvent event, DateTime day) {
    if (!appliesTo(event)) return event.description;
    return overrideFor(event.id, day) ?? event.description;
  }
}
