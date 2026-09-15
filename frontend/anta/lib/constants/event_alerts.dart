import '../models/event_alert.dart';

/// Minute of day an all-day alert fires at when it carries no [dayMinute] of
/// its own — 09:00, which is what Apple and Google both default to.
///
/// The model has no anchor for an all-day event, so this is the anchor. It is
/// a *fallback*, never written onto a row: an alert with `dayMinute == null`
/// follows the Calendar-settings value, so changing that setting moves every
/// alert that never chose a time.
const int kDefaultAlertDayMinute = 540;

/// Ceiling on alerts per event. Google Calendar's cap, and the number the
/// editor stops offering "Add alert" at.
const int kMaxAlertsPerEvent = 5;

/// The JSON keys one alert round-trips through — the backup archive and, from
/// Session 6, the `alerts` blob on an event template.
///
/// Spelled once here so the two encodings cannot drift: an archive written by
/// one and read by the other is the whole point of having a codec at all.
abstract final class EventAlertKeys {
  static const String id = 'id';
  static const String eventId = 'eventId';
  static const String mode = 'mode';
  static const String offsetMinutes = 'offsetMinutes';
  static const String daysBefore = 'daysBefore';
  static const String dayMinute = 'dayMinute';
  static const String sound = 'sound';
  static const String enabled = 'enabled';
  static const String createdAtMs = 'createdAtMs';
  static const String updatedAtMs = 'updatedAtMs';
}

/// Synchronous, in-memory facade over the live rows of
/// `calendar_event_alerts`, published by `EventAlertService`.
///
/// Shaped exactly like [EventSkips] and [EventPresence], and read from the
/// same kind of hot paths: a day-panel or agenda row asks [hasAlarm] /
/// [hasReminder] while it is building, so both must be O(1) and allocation-free
/// — and, like every other facade here, an **unconfigured read is silent**. A
/// surface that reads this must live under `CalendarPageLoaded` or await
/// `EventAlertService` itself, or it will quietly draw an event with alerts as
/// an event with none.
///
/// Unlike [EventSkips] this is a *rendering* concern, not a membership one:
/// nothing about an alert changes which days an event occurs on. What it does
/// change is what the phone will do, which is why the scheduler awaits the
/// owning service rather than reading here.
abstract final class EventAlerts {
  static Map<String, List<EventAlert>> _byEvent = const {};
  static int _revision = 0;

  /// Bumped on every republish, so a page that renders badges can rebuild on
  /// it the way the calendar rebuilds on `EventSkips.revision`.
  static int get revision => _revision;

  /// Replaces the cache wholesale. Each list in [byEvent] must already be
  /// unmodifiable — [alertsFor] hands them straight out.
  static void updateCache({required Map<String, List<EventAlert>> byEvent}) {
    _byEvent = byEvent;
    _revision++;
  }

  /// Drops everything. Part of the `DatabaseLifecycle` reset contract: an
  /// alert leaked from a closed database would badge an event of the newly
  /// opened one that has no alerts at all.
  static void resetCache() {
    _byEvent = const {};
    _revision++;
  }

  /// Every alert of [eventId], enabled or not, in a stable order. O(1): one
  /// map probe, no allocation, and the returned list is unmodifiable.
  ///
  /// Disabled alerts are included because the editor and the hub both have to
  /// show what an event *says* — [hasAlarm] and [hasReminder] are the ones
  /// that answer what it will *do*.
  static List<EventAlert> alertsFor(String eventId) =>
      _byEvent[eventId] ?? const <EventAlert>[];

  /// Whether [eventId] will ring — at least one **enabled** alert in the
  /// [AlertMode.ring] tier. The day-panel and agenda badge read this.
  static bool hasAlarm(String eventId) => _anyEnabled(eventId, AlertMode.ring);

  /// Whether [eventId] will notify — at least one **enabled** alert in the
  /// [AlertMode.notify] tier.
  static bool hasReminder(String eventId) =>
      _anyEnabled(eventId, AlertMode.notify);

  static bool _anyEnabled(String eventId, AlertMode mode) {
    final alerts = _byEvent[eventId];
    if (alerts == null) return false;
    for (final alert in alerts) {
      if (alert.enabled && alert.mode == mode) return true;
    }
    return false;
  }
}
