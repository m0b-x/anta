import '../models/calendar_event.dart';

/// Synchronous, in-memory facade over the cancelled occurrences in
/// `calendar_event_skips`, published by `EventSkipService`.
///
/// Shaped exactly like [EventPresence], and read from the same kind of hot
/// paths — but one layer deeper. A missed occurrence is a *rendering*
/// concern, so presence is probed by the surfaces that draw. A skipped
/// occurrence does not exist at all, so this is probed by
/// [CalendarEvent.occursOn] itself, which is what makes every surface —
/// grid, day panel, agenda, timeline, date pickers, `.ics` — agree without
/// any of them knowing skips are a thing.
///
/// That is the deliberate inverse of the hidden-category filter, which is
/// "render-time only, forever": hiding a category changes what you look at,
/// cancelling an occurrence changes what is there.
abstract final class EventSkips {
  static Map<String, Set<DateTime>> _byEvent = const {};
  static int _revision = 0;

  /// Bumped on every republish. Unlike [EventPresence.revision], a change here
  /// changes **membership**, so consumers must rescan rather than repaint —
  /// `CalendarBloc` mirrors it into `membershipRevision` for exactly that.
  static int get revision => _revision;

  /// Replaces the cache wholesale. [byEvent]'s entries must already be
  /// date-only UTC.
  static void updateCache({required Map<String, Set<DateTime>> byEvent}) {
    _byEvent = byEvent;
    _revision++;
  }

  /// Drops everything. Part of the `DatabaseLifecycle` reset contract, and
  /// more urgent here than for presence: a leaked skip from a closed database
  /// **hides** occurrences of the newly-opened one.
  static void resetCache() {
    _byEvent = const {};
    _revision++;
  }

  /// Whether [event] can have occurrences cancelled at all.
  ///
  /// Always, since decision B of the analytics record ("one mark for every
  /// shape"): a cancelled appointment or bill is not a deleted one — it keeps
  /// its title, its notes and its place in the Report's cancelled count, and an
  /// unskip brings it back. A one-off's day is its start day (its days, for a
  /// multi-day event), keyed by event id and UTC day like any other row.
  ///
  /// Kept as a method so its call sites stay the one place to ask.
  static bool appliesTo(CalendarEvent event) => true;

  /// **The** entry point for "was this occurrence cancelled". O(1): two map
  /// probes, no allocation — it runs inside [CalendarEvent.occursOnUtcDay],
  /// called for every event on every visible day, so [day] must already be
  /// date-only UTC (the debug assert catches callers that forget).
  static bool isSkipped(String eventId, DateTime day) {
    assert(
      day == DateTime.utc(day.year, day.month, day.day),
      'isSkipped requires a date-only UTC day',
    );
    final forEvent = _byEvent[eventId];
    if (forEvent == null) return false;
    return forEvent.contains(day);
  }

  /// Every cancelled day of [eventId], date-only UTC. Used by the editor's
  /// "skipped days" picker; empty when the event has none.
  static Set<DateTime> daysFor(String eventId) =>
      _byEvent[eventId] ?? const <DateTime>{};
}
