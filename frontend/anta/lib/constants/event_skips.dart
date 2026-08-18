import '../models/calendar_event.dart';
import '../models/recurrence_rule.dart';

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
  /// No per-event opt-in, unlike presence: any recurring event has occurrences
  /// to cancel. A one-time event is excluded because cancelling its only
  /// occurrence is a delete, which the UI offers separately — and because that
  /// gate is what stops a stale row from ever hiding a one-time event.
  static bool appliesTo(CalendarEvent event) =>
      event.rule is! OneTimeRecurrence;

  /// **The** entry point for "was this occurrence cancelled". O(1): two map
  /// probes, no allocation — it runs inside [CalendarEvent.occursOn], which is
  /// called for every event on every visible day.
  static bool isSkipped(String eventId, DateTime day) {
    final forEvent = _byEvent[eventId];
    if (forEvent == null) return false;
    return forEvent.contains(DateTime.utc(day.year, day.month, day.day));
  }

  /// Every cancelled day of [eventId], date-only UTC. Used by the editor's
  /// "skipped days" picker; empty when the event has none.
  static Set<DateTime> daysFor(String eventId) =>
      _byEvent[eventId] ?? const <DateTime>{};
}
