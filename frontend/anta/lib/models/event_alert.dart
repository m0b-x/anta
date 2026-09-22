import 'package:equatable/equatable.dart';

import '../constants/event_alerts.dart';
import '../l10n/app_localizations.dart';
import '../services/event_time_formatter.dart';
import 'calendar_event.dart';

/// The two tiers an alert can fire in.
///
/// [notify] is a notification: it respects silent mode and Focus, sits in the
/// shade and can be swiped away. [ring] keeps playing on the alarm stream
/// until it is stopped or snoozed.
///
/// Persisted by [name]; an unknown value decodes to [notify], the quieter of
/// the two, so a row written by a newer build can never surprise an older one
/// with noise.
enum AlertMode {
  notify,
  ring;

  static AlertMode fromName(String? raw) {
    for (final mode in AlertMode.values) {
      if (mode.name == raw) return mode;
    }
    return AlertMode.notify;
  }
}

/// One alert on one event: *when* the phone should speak up about an
/// occurrence, and *how*.
///
/// **Both offset sets are always carried.** [offsetMinutes] answers a timed
/// event, [daysBefore] + [dayMinute] answer an all-day one, and the planner
/// picks between them by `event.time == null` — the derived
/// [CalendarEvent.allDay], never the persisted mirror column. An event
/// switched from timed to all-day therefore keeps alerts that still mean
/// something, and switching back restores the reading it had.
///
/// [dayMinute] is nullable because `null` is a meaning of its own: *the
/// Calendar-settings default*, so changing that setting moves every alert
/// that never chose a time. [sound] is likewise `null` for "the default
/// sound", and applies to the alarm tier only.
///
/// A disabled alert is **kept** and never registered, so the hub switch
/// cannot lose what an alert said.
class EventAlert extends Equatable {
  final String id;
  final String eventId;
  final AlertMode mode;

  /// Minutes before the occurrence's start, for a timed event. `0` is
  /// "at start"; negative offsets are deliberately not modelled.
  final int offsetMinutes;

  /// Whole days before the occurrence, for an all-day event. `0` is
  /// "on the day".
  final int daysBefore;

  /// Minute of day an all-day alert fires at, or `null` for the settings
  /// default ([EventAlerts.defaultDayMinute]).
  final int? dayMinute;

  /// Alarm sound id, or `null` for the default. Alarm tier only.
  final String? sound;

  /// The hub switch. A disabled alert persists and registers nothing.
  final bool enabled;

  const EventAlert({
    required this.id,
    required this.eventId,
    this.mode = AlertMode.notify,
    this.offsetMinutes = 0,
    this.daysBefore = 0,
    this.dayMinute,
    this.sound,
    this.enabled = true,
  });

  bool get isAlarm => mode == AlertMode.ring;

  EventAlert copyWith({
    String? id,
    String? eventId,
    AlertMode? mode,
    int? offsetMinutes,
    int? daysBefore,
    int? dayMinute,
    String? sound,
    bool? enabled,
    bool clearSound = false,
    bool clearDayMinute = false,
  }) {
    return EventAlert(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      mode: mode ?? this.mode,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      daysBefore: daysBefore ?? this.daysBefore,
      dayMinute: clearDayMinute ? null : (dayMinute ?? this.dayMinute),
      sound: clearSound ? null : (sound ?? this.sound),
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    EventAlertKeys.id: id,
    EventAlertKeys.eventId: eventId,
    EventAlertKeys.mode: mode.name,
    EventAlertKeys.offsetMinutes: offsetMinutes,
    EventAlertKeys.daysBefore: daysBefore,
    EventAlertKeys.dayMinute: dayMinute,
    EventAlertKeys.sound: sound,
    EventAlertKeys.enabled: enabled,
  };

  /// Decodes one alert, or `null` when the map carries no usable identity.
  ///
  /// Every other field falls back to its default rather than rejecting the
  /// row: an archive written by a newer build may carry fields this one does
  /// not know, and an alert that loses its sound is still the alert the user
  /// set.
  static EventAlert? fromJson(Map<String, dynamic> map) {
    final id = map[EventAlertKeys.id];
    final eventId = map[EventAlertKeys.eventId];
    if (id is! String || id.isEmpty) return null;
    if (eventId is! String || eventId.isEmpty) return null;
    final dayMinute = map[EventAlertKeys.dayMinute];
    return EventAlert(
      id: id,
      eventId: eventId,
      mode: AlertMode.fromName(map[EventAlertKeys.mode] as String?),
      offsetMinutes: _nonNegative(map[EventAlertKeys.offsetMinutes]),
      daysBefore: _nonNegative(map[EventAlertKeys.daysBefore]),
      dayMinute: dayMinute is int ? _clampMinute(dayMinute) : null,
      sound: map[EventAlertKeys.sound] is String
          ? map[EventAlertKeys.sound] as String
          : null,
      enabled: map[EventAlertKeys.enabled] is bool
          ? map[EventAlertKeys.enabled] as bool
          : true,
    );
  }

  /// **The** formatter for an alert's timing — "10 min before", "At start",
  /// "On the day, 09:00", "The day before, 20:00".
  ///
  /// The editor card, the detail row, the hub row and the notification body
  /// all read this one method; a second switch somewhere would be a second
  /// answer, and the two would drift the first time a unit changed.
  ///
  /// [event] is what decides which offset set is being described, through the
  /// derived [CalendarEvent.allDay] — so an event flipped to all-day is
  /// described by its all-day offsets without either set being rewritten.
  String describe(AppLocalizations l10n, CalendarEvent event) {
    if (event.allDay) {
      final label = EventTimeFormatter.formatRange(
        EventTime(startMinute: dayMinute ?? EventAlerts.defaultDayMinute),
        l10n,
      );
      if (daysBefore <= 0) return l10n.eventAlertAllDayOnDay(label);
      if (daysBefore == 1) return l10n.eventAlertAllDayDayBefore(label);
      return l10n.eventAlertAllDayDaysBefore(daysBefore, label);
    }
    if (offsetMinutes <= 0) return l10n.eventAlertAtStart;
    if (offsetMinutes % minutesPerDay == 0) {
      return l10n.eventAlertDaysBefore(offsetMinutes ~/ minutesPerDay);
    }
    if (offsetMinutes % Duration.minutesPerHour == 0) {
      return l10n.eventAlertHoursBefore(
        offsetMinutes ~/ Duration.minutesPerHour,
      );
    }
    return l10n.eventAlertMinutesBefore(offsetMinutes);
  }

  static const int minutesPerDay = Duration.minutesPerHour * 24;

  static int _nonNegative(Object? raw) => raw is int && raw > 0 ? raw : 0;

  static int _clampMinute(int raw) => raw.clamp(0, minutesPerDay - 1);

  @override
  List<Object?> get props => [
    id,
    eventId,
    mode,
    offsetMinutes,
    daysBefore,
    dayMinute,
    sound,
    enabled,
  ];
}

/// The default alert a new **timed** event is seeded with, decoded from
/// `alert_default_timed`. `null` there means "no default", so a new event
/// starts with no alerts at all.
typedef TimedAlertDefault = ({AlertMode mode, int offsetMinutes});

/// The same for an **all-day** event, decoded from `alert_default_all_day`.
typedef AllDayAlertDefault = ({AlertMode mode, int daysBefore, int dayMinute});

/// Every event-alert option, as `SettingsService.getAlertSettings` hands it
/// back. Permission state is not here: it is per device and can change in
/// Android's settings between two frames, so the gateway is asked live.
typedef AlertSettings = ({
  TimedAlertDefault? timedDefault,
  AllDayAlertDefault? allDayDefault,
  String sound,
  int snoozeMinutes,
  int silenceAfterMinutes,
  int noticeLeadMinutes,
});
