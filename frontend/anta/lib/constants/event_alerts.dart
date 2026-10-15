import '../models/calendar_event.dart';
import '../models/category_alert.dart';
import '../models/event_alert.dart';
import 'calendar_categories.dart';

/// Minute of day an all-day alert fires at when it carries no [dayMinute] of
/// its own — 09:00, which is what Apple and Google both default to.
///
/// The model has no anchor for an all-day event, so this is the anchor. It is
/// a *fallback*, never written onto a row: an alert with `dayMinute == null`
/// follows the Calendar-settings value, so changing that setting moves every
/// alert that never chose a time. Everything that *shows* such an alert reads
/// [EventAlerts.defaultDayMinute], which is that setting; this constant is
/// only what the setting itself starts at.
const int kDefaultAlertDayMinute = 540;

/// Minutes before the start a hand-added **timed** alert opens on when the
/// Calendar settings name no default — which is how the app ships. Only ever
/// a draft's starting chip: nothing is seeded onto an event from it.
const int kDraftAlertOffsetMinutes = 10;

/// Ceiling on alerts per event. Google Calendar's cap, and the number the
/// editor stops offering "Add alert" at.
const int kMaxAlertsPerEvent = 5;

/// Ceiling on alerts per category (D6) — the event cap, so an event inherits
/// at most as many as it can hold of its own and carries ten at the most.
const int kMaxAlertsPerCategory = kMaxAlertsPerEvent;

/// The JSON keys one alert round-trips through — the backup archive and, from
/// Session 6, the `alerts` blob on an event template.
///
/// Spelled once here so the two encodings cannot drift: an archive written by
/// one and read by the other is the whole point of having a codec at all. A
/// category alert (**v42**) is the same map with [categoryId] in place of
/// [eventId].
abstract final class EventAlertKeys {
  static const String id = 'id';
  static const String eventId = 'eventId';
  static const String categoryId = 'categoryId';
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
/// `calendar_event_alerts` and, since **v42**, `calendar_category_alerts`,
/// both published by `EventAlertService`.
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
  static Map<String, List<CategoryAlert>> _byCategory = const {};
  static int _revision = 0;
  static int _defaultDayMinute = kDefaultAlertDayMinute;

  /// Minute of day an all-day alert with no `dayMinute` of its own fires at —
  /// the Calendar-settings default, published by `SettingsService` whenever it
  /// reads or writes the alert settings.
  ///
  /// The planner is handed the same number through its `defaults`, and that is
  /// the point: the editor card, the detail row, the hub and the `.ics` export
  /// used to fall back to 09:00 on their own, so after the setting was moved
  /// an alert said 09:00 and rang at the new time.
  static int get defaultDayMinute => _defaultDayMinute;

  /// `null` is "no all-day default", which leaves the shipped 09:00 anchor.
  static void configureDefaultDayMinute(int? minute) {
    final next = minute ?? kDefaultAlertDayMinute;
    if (next == _defaultDayMinute) return;
    _defaultDayMinute = next;
    _revision++;
  }

  /// Bumped on every republish, so a page that renders badges can rebuild on
  /// it the way the calendar rebuilds on `EventSkips.revision`.
  static int get revision => _revision;

  /// Replaces the cache wholesale. Each list in [byEvent] must already be
  /// unmodifiable — [alertsFor] hands them straight out.
  static void updateCache({required Map<String, List<EventAlert>> byEvent}) {
    _byEvent = byEvent;
    _revision++;
  }

  /// Replaces the category half wholesale (**v42**), bumping [revision] like
  /// an event write: one category alert changes what every event in the
  /// category will do. Each list must already be unmodifiable —
  /// [categoryAlertsFor] hands them straight out.
  static void updateCategoryCache({
    required Map<String, List<CategoryAlert>> byCategory,
  }) {
    _byCategory = byCategory;
    _revision++;
  }

  /// Drops everything. Part of the `DatabaseLifecycle` reset contract: an
  /// alert leaked from a closed database would badge an event of the newly
  /// opened one that has no alerts at all.
  static void resetCache() {
    _byEvent = const {};
    _byCategory = const {};
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

  /// Every alert of [categoryId], enabled or not, in the category's order.
  /// O(1) and unmodifiable, [alertsFor]'s contract.
  static List<CategoryAlert> categoryAlertsFor(String categoryId) =>
      _byCategory[categoryId] ?? const <CategoryAlert>[];

  /// What [event] says, inherited alerts included (D2): its own alerts, then
  /// — unless the event opted out through [CalendarEvent.categoryAlerts] —
  /// its category's, projected onto it in the category's order.
  ///
  /// The category is the one the event is drawn in,
  /// `CalendarCategories.resolve` — an id that no longer resolves is `other`,
  /// whether it went stale through a `deleteCategory` reassignment the event
  /// cache has not re-read yet or through a restore that lacked the category,
  /// so an event drawn as Other inherits Other's alerts.
  ///
  /// An inherited alert that would fire at the same instant as one of the
  /// event's own is dropped (D4): the own one wins, with its id and its sound,
  /// because two fires at one instant for one occurrence are a defect.
  /// Disabled alerts on either side stay in the list, as they do in
  /// [alertsFor]; [hasAlarm] and [hasReminder] answer what will happen.
  ///
  /// The own list is handed back as is when nothing is inherited, so the
  /// common event costs two map probes and no allocation.
  static List<EventAlert> effectiveFor(CalendarEvent event) {
    final own = alertsFor(event.id);
    final inherited = _inheritedBy(event);
    if (inherited.isEmpty) return own;
    return List.unmodifiable([
      ...own,
      for (final alert in inherited)
        if (!_shadowed(alert, own, event)) alert.toEventAlert(event.id),
    ]);
  }

  /// [effectiveFor]'s tail on its own: the alerts [event] inherits, projected
  /// onto it, less the ones an own alert shadows (D4).
  ///
  /// [own] stands for the event's stored alerts when the caller holds a newer
  /// set — the editor's flow, before the bloc has written it. [ignoreOptOut]
  /// answers as if the event inherited: the Alerts hub lists an opted-out
  /// event's inherited alerts with their switch off, which is the way back.
  static List<EventAlert> inheritedFor(
    CalendarEvent event, {
    List<EventAlert>? own,
    bool ignoreOptOut = false,
  }) {
    final inherited = ignoreOptOut
        ? categoryAlertsFor(CalendarCategories.resolve(event.categoryId).id)
        : _inheritedBy(event);
    if (inherited.isEmpty) return const <EventAlert>[];
    final ownAlerts = own ?? alertsFor(event.id);
    return [
      for (final alert in inherited)
        if (!_shadowed(alert, ownAlerts, event)) alert.toEventAlert(event.id),
    ];
  }

  /// Whether [event] will ring — at least one **enabled** alert in the
  /// [AlertMode.ring] tier among [effectiveFor]'s. The day-panel and agenda
  /// badge read this.
  static bool hasAlarm(CalendarEvent event) =>
      _anyEnabled(event, AlertMode.ring);

  /// Whether [event] will notify — at least one **enabled** alert in the
  /// [AlertMode.notify] tier among [effectiveFor]'s.
  static bool hasReminder(CalendarEvent event) =>
      _anyEnabled(event, AlertMode.notify);

  /// [effectiveFor]'s answer without building its list: a badge asks this for
  /// every row it draws.
  static bool _anyEnabled(CalendarEvent event, AlertMode mode) {
    final own = alertsFor(event.id);
    for (final alert in own) {
      if (alert.enabled && alert.mode == mode) return true;
    }
    for (final alert in _inheritedBy(event)) {
      if (alert.enabled &&
          alert.mode == mode &&
          !_shadowed(alert, own, event)) {
        return true;
      }
    }
    return false;
  }

  /// The alerts [event] inherits: its resolved category's, or none when it
  /// opted out.
  static List<CategoryAlert> _inheritedBy(CalendarEvent event) {
    if (!event.categoryAlerts) return const <CategoryAlert>[];
    return categoryAlertsFor(CalendarCategories.resolve(event.categoryId).id);
  }

  /// Whether one of [own] fires at the instant [inherited] would on [event]
  /// (D4) — compared on the offset set the event uses, because both are
  /// always stored and the unused one says nothing: a timed event by its
  /// minutes before the start, an all-day one by its days before and time of
  /// day, a `null` time read as the settings default it fires at.
  static bool _shadowed(
    CategoryAlert inherited,
    List<EventAlert> own,
    CalendarEvent event,
  ) {
    for (final alert in own) {
      if (alert.mode != inherited.mode) continue;
      if (!event.allDay) {
        if (alert.offsetMinutes == inherited.offsetMinutes) return true;
        continue;
      }
      if (alert.daysBefore == inherited.daysBefore &&
          (alert.dayMinute ?? defaultDayMinute) ==
              (inherited.dayMinute ?? defaultDayMinute)) {
        return true;
      }
    }
    return false;
  }
}
