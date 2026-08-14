import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';

/// Presentation helpers for [EventTime].
///
/// Two entry points:
/// - [formatRange] — pure, locale-aware. Use anywhere you only have an
///   [AppLocalizations] (e.g., the day summary subtitle) and no
///   [BuildContext].
/// - [formatRangeOfContext] — uses Material's locale-aware time format
///   (12h / 24h depending on user's device setting). Prefer this in
///   widgets that already have a [BuildContext].
///
/// Both produce strings of the form `"9:30"` (no end), `"9:30 – 10:30"`
/// (start + end), or `"9:30 – 0:30 (+1)"` when the duration crosses
/// midnight.
abstract final class EventTimeFormatter {
  /// Formatted range using `intl`'s `jm` (12h) / `Hm` (24h) skeletons —
  /// callers cannot read the device's 12h/24h preference here, so we
  /// default to a 24-hour-ish neutral skeleton (`HH:mm`) which is the
  /// safest behavior for a planner-style app.
  static String formatRange(EventTime time, AppLocalizations l10n) {
    final start = _format24h(time.startMinute);
    final endMinute = time.endMinute;
    if (endMinute == null) return start;
    final wrapped = endMinute >= EventTime.minutesPerDay;
    final endLabel = _format24h(endMinute % EventTime.minutesPerDay);
    if (!wrapped) return '$start – $endLabel';
    final daysOver = endMinute ~/ EventTime.minutesPerDay;
    return '$start – $endLabel (+$daysOver)';
  }

  /// Formatted range using Material's locale-aware time format. Honors
  /// the user's 12h/24h device preference. Use from widget code.
  static String formatRangeOfContext(EventTime time, BuildContext context) {
    final mat = MaterialLocalizations.of(context);
    final start = mat.formatTimeOfDay(_toTod(time.startMinute));
    final endMinute = time.endMinute;
    if (endMinute == null) return start;
    final wrapped = endMinute >= EventTime.minutesPerDay;
    final endLabel = mat.formatTimeOfDay(
      _toTod(endMinute % EventTime.minutesPerDay),
    );
    if (!wrapped) return '$start – $endLabel';
    final daysOver = endMinute ~/ EventTime.minutesPerDay;
    return '$start – $endLabel (+$daysOver)';
  }

  /// Formats a single minute-of-day using Material's locale-aware format.
  static String formatMinute(int minute, BuildContext context) {
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(_toTod(minute % EventTime.minutesPerDay));
  }

  // ── internals ────────────────────────────────────────────────────────

  static String _format24h(int minute) {
    final hour = minute ~/ 60;
    final min = minute % 60;
    final dt = DateTime(2000, 1, 1, hour, min);
    return DateFormat.Hm().format(dt);
  }

  static TimeOfDay _toTod(int minute) {
    return TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
  }
}
