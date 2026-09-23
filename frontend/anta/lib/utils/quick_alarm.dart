import 'package:equatable/equatable.dart';

import '../models/calendar_event.dart';
import '../models/event_alert.dart';
import '../models/recurrence_rule.dart';

/// The icon a quick alarm's event carries — a key into `CalendarIcons`.
const String kQuickAlarmIconKey = 'alarm';

/// The "Tonight" chip's minute of day, 21:00.
const int kQuickAlarmTonightMinute = 21 * 60;

/// A moment on a day: a date-only UTC [day] and a local minute of day, the
/// pair every planner and every event time in the calendar is written in.
typedef QuickAlarmMoment = ({DateTime day, int minute});

/// What the quick-alarm sheet reports on Save (parent roadmap §5.8, Session
/// 6): the moment, the name, the tier and whether the event should go once
/// the alarm has been acknowledged.
///
/// A draft rather than an event: the page mints the ids and dispatches, so
/// the sheet stays a pure form and the builders below are testable without a
/// widget tree.
class QuickAlarmDraft extends Equatable {
  /// Date-only UTC, like every other day in the calendar.
  final DateTime day;

  /// Minute of local day, `[0, 1440)`.
  final int startMinute;

  final String name;

  final AlertMode mode;

  /// Honoured for the alarm tier only — a reminder cannot be what deletes an
  /// event, the editor's own rule.
  final bool removeAfterAlert;

  const QuickAlarmDraft({
    required this.day,
    required this.startMinute,
    required this.name,
    this.mode = AlertMode.ring,
    this.removeAfterAlert = true,
  });

  bool get isAlarm => mode == AlertMode.ring;

  @override
  List<Object?> get props => [day, startMinute, name, mode, removeAfterAlert];
}

DateTime _utcDayOf(DateTime local) =>
    DateTime.utc(local.year, local.month, local.day);

int _minuteOf(DateTime local) => local.hour * 60 + local.minute;

QuickAlarmMoment _momentOf(DateTime local) => (
  day: _utcDayOf(local),
  minute: _minuteOf(local),
);

/// The moment the sheet opens on: the next quarter hour strictly after [now]
/// (10:00:00 → 10:15, 10:14 → 10:15, 23:50 → 00:00 the next day).
///
/// Built in the constructor form, which normalises a minute past midnight
/// into the next day and keeps wall-clock time on a day the clocks change.
QuickAlarmMoment quickAlarmDefaultFor(DateTime now) {
  final minute = (_minuteOf(now) ~/ 15 + 1) * 15;
  return _momentOf(DateTime(now.year, now.month, now.day, 0, minute));
}

/// [now] plus [offset], rounded **up** to the whole minute so the alarm is
/// never less than [offset] away.
QuickAlarmMoment quickAlarmAfter(DateTime now, Duration offset) {
  var at = now.add(offset);
  if (at.second > 0 || at.millisecond > 0 || at.microsecond > 0) {
    at = at.add(const Duration(minutes: 1));
  }
  return _momentOf(DateTime(at.year, at.month, at.day, at.hour, at.minute));
}

/// Tonight at [kQuickAlarmTonightMinute], or null once that has passed.
QuickAlarmMoment? quickAlarmTonightFor(DateTime now) {
  final at = DateTime(now.year, now.month, now.day, 0, kQuickAlarmTonightMinute);
  return at.isAfter(now) ? _momentOf(at) : null;
}

/// The day an alarm at [minute] lands on when the sheet was opened for [day]:
/// that day while the moment is still ahead, else the first day on which it
/// is — today if [minute] is still to come, tomorrow otherwise. A quick alarm
/// for a time already gone is what a clock app rolls forward too.
DateTime quickAlarmDayFor({
  required DateTime day,
  required int minute,
  required DateTime now,
}) {
  final onDay = DateTime(day.year, day.month, day.day, 0, minute);
  if (onDay.isAfter(now)) return _utcDayOf(day);
  final today = DateTime(now.year, now.month, now.day, 0, minute);
  if (today.isAfter(now)) return _utcDayOf(today);
  return _utcDayOf(DateTime(now.year, now.month, now.day + 1, 0, minute));
}

/// The one-time event a quick alarm is: the fallback category, the alarm
/// icon, a point in time, and the remove-after flag for the alarm tier.
CalendarEvent buildQuickAlarmEvent(QuickAlarmDraft draft, {required String id}) {
  return CalendarEvent(
    id: id,
    title: draft.name,
    categoryId: kFallbackCategoryId,
    startDate: draft.day,
    rule: const OneTimeRecurrence(),
    iconKey: kQuickAlarmIconKey,
    time: EventTime(startMinute: draft.startMinute),
    removeAfterAlert: draft.isAlarm && draft.removeAfterAlert,
  );
}

/// Its one alert: at start, in the draft's tier, with the default sound.
EventAlert buildQuickAlarmAlert(
  QuickAlarmDraft draft, {
  required String eventId,
  required String id,
}) {
  return EventAlert(id: id, eventId: eventId, mode: draft.mode);
}
