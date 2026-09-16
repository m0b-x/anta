import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../constants/calendar_categories.dart';
import '../constants/settings_keys.dart';
import 'event_alert.dart';

/// The JSON keys the payload round-trips through.
///
/// Short, because the whole map is handed to the platform as one string and
/// two backends copy it verbatim through a reboot; and spelled once, because
/// the alarm page decodes what the scheduler encoded across a process death
/// and a drifting key would show a blank page rather than fail.
abstract final class AlertPayloadKeys {
  static const String database = 'db';
  static const String eventId = 'eventId';
  static const String alertId = 'alertId';
  static const String dayUtcMs = 'dayUtcMs';
  static const String osId = 'osId';
  static const String mode = 'mode';
  static const String title = 'title';
  static const String timeLabel = 'timeLabel';
  static const String colorValue = 'colorValue';
  static const String iconKey = 'iconKey';
  static const String categoryId = 'categoryId';
  static const String removeAfterAlert = 'removeAfterAlert';
  static const String snooze = 'snooze';
  static const String snoozeMinutes = 'snoozeMin';
}

/// Everything a ring needs to draw itself, carried by the platform entry.
///
/// **Self-describing on purpose.** The alarm page renders from this alone and
/// never opens a database: an alarm that belongs to a database the user is not
/// currently in still has to show a title, a colour and a time (**A9**), and a
/// ring recovered after a reboot arrives in a process where nothing is loaded
/// yet. Reading the event instead would make both cases blank.
///
/// [database] is what scopes reconcile: a platform entry whose payload names
/// another database is never cancelled and never re-registered, so switching
/// databases cannot silently disarm the alarms of the one left behind.
///
/// [timeLabel] is formatted **at schedule time, on the UI thread**. The app
/// never sets `Intl.defaultLocale`, so formatting a time in a background
/// isolate — which is where a notification action runs — would render in the
/// system locale rather than the app's.
class AlertPayload extends Equatable {
  /// Active database name at schedule time.
  final String database;

  final String eventId;
  final String alertId;

  /// The occurrence day this fire belongs to, date-only UTC as epoch ms.
  final int dayUtcMs;

  /// The id the platform holds this entry under.
  final int osId;

  final AlertMode mode;

  final String title;

  /// Wall-clock label of the fire instant, pre-formatted. The alarm page shows
  /// it, and the "Missed" body quotes it.
  final String timeLabel;

  /// The event's own colour override, or null to resolve from the category.
  final int? colorValue;

  /// The event's own icon override, or null for the category's icon.
  final String? iconKey;

  final String categoryId;

  /// Whether acknowledging this alert deletes the event (**A3**).
  final bool removeAfterAlert;

  /// Whether this entry is a snooze rather than the planned occurrence.
  final bool snooze;

  /// How many minutes Snooze postpones this alert by.
  ///
  /// Carried rather than looked up because the reminder tier's Snooze action
  /// runs in a **background isolate**: it has no database, no settings service
  /// and no facade, and re-schedules from this map alone.
  final int snoozeMinutes;

  const AlertPayload({
    required this.database,
    required this.eventId,
    required this.alertId,
    required this.dayUtcMs,
    required this.osId,
    required this.mode,
    required this.title,
    required this.timeLabel,
    this.colorValue,
    this.iconKey,
    required this.categoryId,
    this.removeAfterAlert = false,
    this.snooze = false,
    this.snoozeMinutes = SettingsKeys.defaultAlertSnoozeMinutes,
  });

  /// The event id a **test alarm** carries (§5.7's `Test alarm in 10 s`).
  ///
  /// A sentinel rather than a flag of its own: a test ring has no event, no
  /// alert row and no occurrence, so every consumer that resolves one already
  /// has to cope with finding nothing. The alarm page reads [isTest] to title
  /// itself, and the scheduler records the registration as a snooze so the
  /// diff — which owns only what the plan produced — leaves it alone.
  static const String testEventId = '__anta_test_alarm__';

  /// Whether this is the settings page's test ring rather than a real alert.
  bool get isTest => eventId == testEventId;

  /// The occurrence day, rebuilt as the date-only UTC day it was stored as.
  DateTime get dayUtc => DateTime.fromMillisecondsSinceEpoch(
    dayUtcMs,
    isUtc: true,
  );

  bool get isAlarm => mode == AlertMode.ring;

  AlertPayload copyWith({
    int? osId,
    String? timeLabel,
    bool? snooze,
    bool? removeAfterAlert,
    int? snoozeMinutes,
  }) {
    return AlertPayload(
      database: database,
      eventId: eventId,
      alertId: alertId,
      dayUtcMs: dayUtcMs,
      osId: osId ?? this.osId,
      mode: mode,
      title: title,
      timeLabel: timeLabel ?? this.timeLabel,
      colorValue: colorValue,
      iconKey: iconKey,
      categoryId: categoryId,
      removeAfterAlert: removeAfterAlert ?? this.removeAfterAlert,
      snooze: snooze ?? this.snooze,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
    AlertPayloadKeys.database: database,
    AlertPayloadKeys.eventId: eventId,
    AlertPayloadKeys.alertId: alertId,
    AlertPayloadKeys.dayUtcMs: dayUtcMs,
    AlertPayloadKeys.osId: osId,
    AlertPayloadKeys.mode: mode.name,
    AlertPayloadKeys.title: title,
    AlertPayloadKeys.timeLabel: timeLabel,
    AlertPayloadKeys.colorValue: colorValue,
    AlertPayloadKeys.iconKey: iconKey,
    AlertPayloadKeys.categoryId: categoryId,
    AlertPayloadKeys.removeAfterAlert: removeAfterAlert,
    AlertPayloadKeys.snooze: snooze,
    AlertPayloadKeys.snoozeMinutes: snoozeMinutes,
  };

  /// Decodes one payload, or `null` when the map carries no usable identity.
  ///
  /// Everything but the four identity fields falls back to a default rather
  /// than rejecting the entry: an entry written by a newer build, or one whose
  /// title the platform truncated, is still an alarm that has to be stoppable.
  static AlertPayload? fromJson(Map<String, dynamic> map) {
    final database = map[AlertPayloadKeys.database];
    final eventId = map[AlertPayloadKeys.eventId];
    final alertId = map[AlertPayloadKeys.alertId];
    final osId = map[AlertPayloadKeys.osId];
    final dayUtcMs = map[AlertPayloadKeys.dayUtcMs];
    if (database is! String || database.isEmpty) return null;
    if (eventId is! String || eventId.isEmpty) return null;
    if (alertId is! String || alertId.isEmpty) return null;
    if (osId is! int || dayUtcMs is! int) return null;
    return AlertPayload(
      database: database,
      eventId: eventId,
      alertId: alertId,
      dayUtcMs: dayUtcMs,
      osId: osId,
      mode: AlertMode.fromName(map[AlertPayloadKeys.mode] as String?),
      title: map[AlertPayloadKeys.title] is String
          ? map[AlertPayloadKeys.title] as String
          : '',
      timeLabel: map[AlertPayloadKeys.timeLabel] is String
          ? map[AlertPayloadKeys.timeLabel] as String
          : '',
      colorValue: map[AlertPayloadKeys.colorValue] is int
          ? map[AlertPayloadKeys.colorValue] as int
          : null,
      iconKey: map[AlertPayloadKeys.iconKey] is String
          ? map[AlertPayloadKeys.iconKey] as String
          : null,
      // The same fallback every other unresolvable category id takes, rather
      // than a second literal that could drift from it.
      categoryId: map[AlertPayloadKeys.categoryId] is String
          ? map[AlertPayloadKeys.categoryId] as String
          : CalendarCategories.fallback.id,
      removeAfterAlert:
          map[AlertPayloadKeys.removeAfterAlert] == true,
      snooze: map[AlertPayloadKeys.snooze] == true,
      snoozeMinutes: map[AlertPayloadKeys.snoozeMinutes] is int
          ? (map[AlertPayloadKeys.snoozeMinutes] as int).clamp(
              SettingsKeys.minAlertSnoozeMinutes,
              SettingsKeys.maxAlertSnoozeMinutes,
            )
          : SettingsKeys.defaultAlertSnoozeMinutes,
    );
  }

  /// The wire form the platform stores.
  String encode() => jsonEncode(toJson());

  /// Inverse of [encode]. Returns `null` for anything that is not a JSON
  /// object carrying an identity — a truncated or foreign payload must read as
  /// "not ours" rather than throw inside a notification callback.
  static AlertPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  @override
  List<Object?> get props => [
    database,
    eventId,
    alertId,
    dayUtcMs,
    osId,
    mode,
    title,
    timeLabel,
    colorValue,
    iconKey,
    categoryId,
    removeAfterAlert,
    snooze,
    snoozeMinutes,
  ];
}
