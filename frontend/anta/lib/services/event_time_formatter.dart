import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';

/// Presentation helpers for [EventTime].
///
/// Three entry points:
/// - [formatRange] — pure, locale-aware. Use anywhere you only have an
///   [AppLocalizations] (e.g., the day summary subtitle) and no
///   [BuildContext].
/// - [formatRangeOfContext] — uses Material's locale-aware time format
///   (12h / 24h depending on user's device setting). Prefer this in
///   widgets that already have a [BuildContext].
/// - [formatRangeFor] — what [formatRangeOfContext] writes, for a caller
///   that has a language and the phone's clock style but no [BuildContext].
///
/// All produce strings of the form `"9:30"` (no end), `"9:30 – 10:30"`
/// (start + end), or `"9:30 – 0:30 (+1)"` when the duration crosses
/// midnight.
abstract final class EventTimeFormatter {
  /// Formatted range using `intl`'s `jm` (12h) / `Hm` (24h) skeletons —
  /// callers cannot read the device's 12h/24h preference here, so we
  /// default to a 24-hour-ish neutral skeleton (`HH:mm`) which is the
  /// safest behavior for a planner-style app.
  static String formatRange(EventTime time, AppLocalizations l10n) =>
      _range(time, _format24h);

  /// Formatted range using Material's locale-aware time format. Honors
  /// the user's 12h/24h device preference. Use from widget code.
  static String formatRangeOfContext(EventTime time, BuildContext context) {
    final mat = MaterialLocalizations.of(context);
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    return _range(
      time,
      (minute) =>
          mat.formatTimeOfDay(_toTod(minute), alwaysUse24HourFormat: use24h),
    );
  }

  /// [formatRangeOfContext] with no [BuildContext]: the same line, for a
  /// service that knows the language and whether the phone is on the 24-hour
  /// clock. The alert labels are written this way — at arm time, in a
  /// scheduler — so that a notification and the alarm page read an event's
  /// time exactly as its detail sheet does.
  static String formatRangeFor(
    EventTime time, {
    required String localeName,
    required bool use24Hour,
  }) => _range(
    time,
    (minute) =>
        formatMinuteFor(minute, localeName: localeName, use24Hour: use24Hour),
  );

  /// [formatMinute] with no [BuildContext] — see [formatRangeFor].
  ///
  /// Material's rule, restated over `intl` because a `MaterialLocalizations`
  /// can only be had from a context: 24-hour when the phone says so, else
  /// whatever [localeName] itself writes, which is a day period in English
  /// and 24-hour in German and Romanian. `event_time_formatter_test.dart`
  /// holds the two to the same string in every language the app ships, so a
  /// new language whose Material format this does not reproduce fails there
  /// rather than on a notification.
  static String formatMinuteFor(
    int minute, {
    required String localeName,
    required bool use24Hour,
  }) {
    final wrapped = minute % EventTime.minutesPerDay;
    return _clockFormat(
      localeName,
      use24Hour,
    ).format(DateTime(2000, 1, 1, wrapped ~/ 60, wrapped % 60));
  }

  /// One minute of day as a bare `HH:mm`, with no [BuildContext] and no
  /// [AppLocalizations] — the same neutral skeleton [formatRange] uses.
  ///
  /// Exists for the alert labels, as the clock they fall back on. They write
  /// an entry's times on the phone's own clock ([formatMinuteFor]), inside
  /// the pass that arms it; where that cannot be written — a language whose
  /// date symbols are not loaded — the entry still has to say when it is due,
  /// and this needs nothing loaded.
  static String formatMinuteOfDay(int minute) =>
      _format24h(minute % EventTime.minutesPerDay);

  /// Formats a single minute-of-day using Material's locale-aware format.
  static String formatMinute(int minute, BuildContext context) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      _toTod(minute % EventTime.minutesPerDay),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  static String formatDuration(int minutes, AppLocalizations l10n) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return l10n.eventDurationMinutes(rest);
    if (rest == 0) return l10n.eventDurationHours(hours);
    return l10n.eventDurationHoursMinutes(hours, rest);
  }

  // ── internals ────────────────────────────────────────────────────────

  /// The one range grammar, over whichever clock the caller writes a minute
  /// of day with.
  static String _range(EventTime time, String Function(int minute) clock) {
    final start = clock(time.startMinute);
    final endMinute = time.endMinute;
    if (endMinute == null) return start;
    final wrapped = endMinute >= EventTime.minutesPerDay;
    final endLabel = clock(endMinute % EventTime.minutesPerDay);
    if (!wrapped) return '$start – $endLabel';
    final daysOver = endMinute ~/ EventTime.minutesPerDay;
    return '$start – $endLabel (+$daysOver)';
  }

  static final Map<String, DateFormat> _clockCache = {};

  /// The format [formatMinuteFor] writes with, parsed once per language and
  /// clock style.
  ///
  /// The 12-hour pattern is spelled out rather than taken from `jm`: `intl`
  /// puts a narrow no-break space before the day period where Material puts
  /// a plain one, and the two have to come out as one string.
  static DateFormat _clockFormat(String localeName, bool use24Hour) {
    final key = '$localeName|$use24Hour';
    final cached = _clockCache[key];
    if (cached != null) return cached;
    final dayPeriod =
        !use24Hour && (DateFormat.jm(localeName).pattern ?? '').contains('a');
    return _clockCache[key] = dayPeriod
        ? DateFormat('h:mm a', localeName)
        : DateFormat.Hm(localeName);
  }

  /// `DateFormat.Hm` parses its skeleton on construction; agenda rows build
  /// one per timed event, so the parsed formatter is cached per locale.
  static final Map<String, DateFormat> _hmCache = {};

  static String _format24h(int minute) {
    final hour = minute ~/ 60;
    final min = minute % 60;
    final dt = DateTime(2000, 1, 1, hour, min);
    final locale = Intl.getCurrentLocale();
    return (_hmCache[locale] ??= DateFormat.Hm(locale)).format(dt);
  }

  static TimeOfDay _toTod(int minute) {
    return TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
  }
}
