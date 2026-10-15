import 'package:equatable/equatable.dart';

import '../constants/event_alerts.dart';
import 'event_alert.dart';

/// One alert on one calendar category (**v42**), inherited at read time by
/// every event in it — "remind me before each birthday", set once.
///
/// The [EventAlert] row minus the event: both offset sets are carried and the
/// planner picks by the event's `time == null`, so one category alert serves
/// a category that mixes timed and all-day events. [dayMinute] `null` is the
/// Calendar-settings default, [sound] `null` the default sound (Alarm tier
/// only), [enabled] the category's own switch for this alert.
///
/// Never copied onto an event: [toEventAlert] projects it whenever
/// `EventAlerts.effectiveFor` is asked, so membership is always the event's
/// current category.
class CategoryAlert extends Equatable {
  final String id;
  final String categoryId;
  final AlertMode mode;
  final int offsetMinutes;
  final int daysBefore;
  final int? dayMinute;
  final String? sound;
  final bool enabled;

  const CategoryAlert({
    required this.id,
    required this.categoryId,
    this.mode = AlertMode.notify,
    this.offsetMinutes = 0,
    this.daysBefore = 0,
    this.dayMinute,
    this.sound,
    this.enabled = true,
  });

  /// [alert] as [categoryId]'s own — the way back from [toEventAlert], for
  /// the category editor, whose rows are edited in the event alert's sheet.
  /// The id is kept: a new alert arrives from that sheet's draft with a
  /// fresh one, and `replaceForCategory` refuses an id another category owns.
  factory CategoryAlert.fromEventAlert(
    EventAlert alert, {
    required String categoryId,
  }) => CategoryAlert(
    id: alert.id,
    categoryId: categoryId,
    mode: alert.mode,
    offsetMinutes: alert.offsetMinutes,
    daysBefore: alert.daysBefore,
    dayMinute: alert.dayMinute,
    sound: alert.sound,
    enabled: alert.enabled,
  );

  bool get isAlarm => mode == AlertMode.ring;

  CategoryAlert copyWith({
    String? id,
    String? categoryId,
    AlertMode? mode,
    int? offsetMinutes,
    int? daysBefore,
    int? dayMinute,
    String? sound,
    bool? enabled,
    bool clearSound = false,
    bool clearDayMinute = false,
  }) {
    return CategoryAlert(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      mode: mode ?? this.mode,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      daysBefore: daysBefore ?? this.daysBefore,
      dayMinute: clearDayMinute ? null : (dayMinute ?? this.dayMinute),
      sound: clearSound ? null : (sound ?? this.sound),
      enabled: enabled ?? this.enabled,
    );
  }

  /// This alert as it applies to [eventId]: the same id, timing, sound and
  /// switch, tagged with [categoryId] so every reader downstream can tell an
  /// inherited alert from the event's own.
  EventAlert toEventAlert(String eventId) => EventAlert(
    id: id,
    eventId: eventId,
    mode: mode,
    offsetMinutes: offsetMinutes,
    daysBefore: daysBefore,
    dayMinute: dayMinute,
    sound: sound,
    enabled: enabled,
    categoryId: categoryId,
  );

  Map<String, dynamic> toJson() => {
    EventAlertKeys.id: id,
    EventAlertKeys.categoryId: categoryId,
    EventAlertKeys.mode: mode.name,
    EventAlertKeys.offsetMinutes: offsetMinutes,
    EventAlertKeys.daysBefore: daysBefore,
    EventAlertKeys.dayMinute: dayMinute,
    EventAlertKeys.sound: sound,
    EventAlertKeys.enabled: enabled,
  };

  /// Decodes one alert, or `null` when the map carries no usable identity —
  /// [EventAlert.fromJson]'s rules: every other field falls back to its
  /// default rather than rejecting the row.
  static CategoryAlert? fromJson(Map<String, dynamic> map) {
    final id = map[EventAlertKeys.id];
    final categoryId = map[EventAlertKeys.categoryId];
    if (id is! String || id.isEmpty) return null;
    if (categoryId is! String || categoryId.isEmpty) return null;
    final dayMinute = map[EventAlertKeys.dayMinute];
    return CategoryAlert(
      id: id,
      categoryId: categoryId,
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

  static int _nonNegative(Object? raw) => raw is int && raw > 0 ? raw : 0;

  static int _clampMinute(int raw) =>
      raw.clamp(0, EventAlert.minutesPerDay - 1);

  @override
  List<Object?> get props => [
    id,
    categoryId,
    mode,
    offsetMinutes,
    daysBefore,
    dayMinute,
    sound,
    enabled,
  ];
}
