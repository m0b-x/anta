import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/alert_payload.dart';
import '../models/calendar_event.dart';
import '../services/event_time_formatter.dart';

/// Writes the times and days an alert entry carries as text.
///
/// **Written once, when the entry is armed, on the UI isolate.** An alert is
/// drawn where nothing can format: a notification is text the platform froze
/// at arm time, and a reminder's Snooze re-posts from a background isolate
/// that has no date symbols loaded and no settings to read a language from.
/// So every clock time and every day name a payload shows is written here,
/// in the app's language and on the clock the phone is on, and everything
/// downstream only places strings.
///
/// One instance per pass, read by the scheduler through
/// `AlertGateway.labels`: that seam is what lets the platform binding answer
/// with the phone's own clock while every suite and the no-op binding keep
/// [fixed].
class AlertLabels {
  /// Labels in [strings]' language, on the 24-hour clock when [use24Hour] and
  /// on that language's own otherwise.
  AlertLabels({required AppLocalizations strings, required bool use24Hour})
    : this._(strings, strings.localeName, use24Hour);

  AlertLabels._(this._strings, this._dateLocale, this.use24Hour);

  /// 24-hour English, whatever the phone and the app say — what the no-op
  /// binding and the scheduler's suite stamp with.
  ///
  /// Written for `en_US` rather than `en`: it is the one locale `intl`
  /// answers for with no date symbols loaded, and most suites that reach the
  /// scheduler never load any.
  static final AlertLabels fixed = AlertLabels._(
    lookupAppLocalizations(const Locale('en')),
    'en_US',
    true,
  );

  final AppLocalizations _strings;

  /// The `intl` locale times and days are formatted for.
  final String _dateLocale;

  /// Whether the phone is on the 24-hour clock.
  final bool use24Hour;

  late final DateFormat _dayFormat = DateFormat.MMMEd(_dateLocale);

  /// The language these labels are written in, which a payload records as
  /// the language of every string it carries.
  String get languageCode => _strings.localeName;

  /// The clock time an entry is due at, on the phone's clock like every
  /// other label here.
  ///
  /// It was held on the neutral 24-hour skeleton for as long as nothing
  /// re-armed a standing entry when the phone's clock style changed: an entry
  /// armed today would have read "6:00 PM" beside yesterday's "18:00". The
  /// arm context names the clock style and the language now
  /// (`alertArmContext`), so every planned entry is written again when either
  /// moves.
  String timeLabel(DateTime fireAt) => _clock(fireAt.hour * 60 + fireAt.minute);

  /// The event's own time, for an entry of its occurrence on [day] (date-only
  /// UTC) that is due at [fireAt].
  ///
  /// The line the detail sheet writes — a range, a single time, or "All day"
  /// — followed by the day when the occurrence is not on the day the entry
  /// is due: an alert a day ahead has to say which day it is about.
  ///
  /// **Empty when it would only repeat the due time**: a point in time, on
  /// the due day, at the due minute. Compared as minutes, never as text, so
  /// the answer cannot change with the clock style either line is written
  /// in.
  String whenLabel({
    required EventTime? time,
    required DateTime day,
    required DateTime fireAt,
  }) {
    final onDueDay = _sameDay(day, fireAt);
    if (time != null &&
        time.endMinute == null &&
        onDueDay &&
        time.startMinute == fireAt.hour * 60 + fireAt.minute) {
      return '';
    }
    return _written('', () {
      final line = time == null
          ? _strings.eventAllDay
          : EventTimeFormatter.formatRangeFor(
              time,
              localeName: _dateLocale,
              use24Hour: use24Hour,
            );
      return onDueDay ? line : _strings.alertsWhenOnDay(line, _dayOf(day));
    });
  }

  /// The day an upcoming notice names beside its alarm's time, or null while
  /// the alarm is due on the day the notice is posted.
  ///
  /// Not a payload field: it needs the notice's own instant, which only the
  /// binding that arms the notice holds.
  String? dayLabel({required DateTime fireAt, required DateTime noticeAt}) {
    if (_sameDay(fireAt, noticeAt)) return null;
    return _written(null, () => _dayOf(fireAt));
  }

  /// The clock time a session ends at, for the session chip.
  ///
  /// Not a payload field either: the end is the session's, known only once
  /// its alarm has been acknowledged.
  String untilLabel(DateTime endsAt) =>
      _clock(endsAt.hour * 60 + endsAt.minute);

  /// One minute of the day as the phone writes a time — or, where that
  /// cannot be written, on the neutral 24-hour skeleton: a time is the one
  /// label an entry cannot do without.
  String _clock(int minute) => _written(
    EventTimeFormatter.formatMinuteOfDay(minute),
    () => EventTimeFormatter.formatMinuteFor(
      minute,
      localeName: _dateLocale,
      use24Hour: use24Hour,
    ),
  );

  /// [payload] as it reads once its entry is due at [fireAt] instead — a
  /// snooze taken from the payload alone, or a ring the platform moved.
  ///
  /// The due time is rewritten. And where the payload said nothing of the
  /// event's own time because that time *was* the due time, the old line
  /// becomes it: left empty, the one time the event starts at would vanish
  /// from every surface the moment its ring is put off.
  ///
  /// Three payloads keep an empty line. One that names no language was
  /// armed before these labels existed, and its silence means the event's
  /// time was never known — the old due time of a "10 minutes before" alert
  /// is not it. A test ring has no event to have a time. And a move inside
  /// the same minute, which is what a ring the platform deferred by seconds
  /// is, leaves the due time reading as it did.
  ///
  /// **The same minute is decided on the two instants, never on the two
  /// labels.** The old label is whatever clock style and language the entry
  /// was armed in and the new one is this instance's: "18:00" against
  /// "6:00 PM" would read as a move that never happened, and take the due
  /// time for the event's own.
  ///
  /// The line, taken over or carried, then answers to the rule [whenLabel]
  /// writes by: put off past midnight, the entry is due on a day that is no
  /// longer the occurrence's, and "23:55" under tomorrow's date would read as
  /// tomorrow's.
  AlertPayload moved(AlertPayload payload, DateTime fireAt) {
    final dueBefore = payload.fireAtMs;
    final rescued =
        payload.languageCode != null &&
        !payload.isTest &&
        payload.whenLabel.isEmpty &&
        (dueBefore == null ||
            !_sameMinute(dueBefore, fireAt.millisecondsSinceEpoch));
    return payload.copyWith(
      fireAtMs: fireAt.millisecondsSinceEpoch,
      timeLabel: timeLabel(fireAt),
      whenLabel: _onItsDay(
        rescued ? payload.timeLabel : payload.whenLabel,
        payload,
        fireAt,
      ),
    );
  }

  /// [line] followed by the occurrence's day once [payload]'s entry is due,
  /// at [fireAt], on another one.
  ///
  /// Only a line written for an entry that was due on the occurrence's day
  /// gains it: one written for any other day already ends in it, and a
  /// second snooze would say the day twice. The reverse is left alone — a
  /// line that names its day and is put off into that very day keeps the
  /// name, because the day cannot be told from the time inside a string and
  /// a date said once too often is still the right date.
  String _onItsDay(String line, AlertPayload payload, DateTime fireAt) {
    if (line.isEmpty) return line;
    final day = payload.dayUtc;
    if (_sameDay(day, fireAt)) return line;
    final dueBefore = payload.fireAtMs;
    if (dueBefore != null &&
        !_sameDay(day, DateTime.fromMillisecondsSinceEpoch(dueBefore))) {
      return line;
    }
    return _written(line, () => _strings.alertsWhenOnDay(line, _dayOf(day)));
  }

  String _dayOf(DateTime day) =>
      _dayFormat.format(DateTime(day.year, day.month, day.day));

  /// A date-only UTC day and a local instant are compared by their calendar
  /// fields: the day says which date, the instant says when on the wall
  /// clock, and converting either into the other moves the date by the zone
  /// offset.
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Whether two instants, as epoch milliseconds, fall inside one minute of
  /// the clock. Counted from the epoch rather than read off the wall clock:
  /// every zone sits a whole number of minutes from it, and the hour a clock
  /// change repeats is two instants that read alike.
  static bool _sameMinute(int a, int b) =>
      a ~/ Duration.millisecondsPerMinute ==
      b ~/ Duration.millisecondsPerMinute;

  /// A label is never worth an alarm. Every write runs inside the pass that
  /// arms, or inside the callback that announces a ring, and one that threw
  /// — date symbols not loaded for a language — would take the entry or the
  /// ring page down with it.
  static T _written<T>(T fallback, T Function() write) {
    try {
      return write();
    } catch (e) {
      debugPrint('[AlertLabels] label left out: $e');
      return fallback;
    }
  }
}
