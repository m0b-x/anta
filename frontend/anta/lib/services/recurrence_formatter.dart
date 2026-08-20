import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/recurrence_rule.dart';

/// Locale-aware human-readable label for a [RecurrenceRule].
abstract final class RecurrenceFormatter {
  /// Human-readable rule label, optionally suffixed with the scope marker
  /// when [retroactive] — the caller passes the event's flag so summary and
  /// agenda rows can say the rule reaches back before its start date.
  static String format(
    RecurrenceRule rule,
    AppLocalizations l10n,
    String localeName, {
    bool retroactive = false,
  }) {
    final label = _ruleLabel(rule, l10n, localeName);
    if (!retroactive || !rule.supportsRetroactive) return label;
    return l10n.recurrenceScopeAlwaysSuffix(label);
  }

  /// Label for the "does this rule reach before its start date" control.
  /// Yearly rules get the natural "Every year" phrasing; everything else
  /// reads as "Always".
  static String scopeAlwaysLabel(RecurrenceRule rule, AppLocalizations l10n) {
    return switch (rule) {
      YearlyRecurrence() => l10n.recurrenceScopeEveryYear,
      _ => l10n.recurrenceScopeAlways,
    };
  }

  /// Occurrence-count label for the occurrence of [event] on [day], or
  /// `null` when the event does not count, the rule has no periodic unit,
  /// or nothing renders for this day under the chosen style. [day] must be
  /// date-only UTC, matching [RecurrenceRule.elapsedPeriods].
  ///
  /// The two styles ([OccurrenceCountStyle]) differ **only in where counting
  /// starts** — that is the whole user-facing choice, and the wording of each
  /// follows from it:
  /// - `numbered` (from 1) — "Day 1" / "Week 3": the start day is the first
  ///   occurrence, which is how a training block reads.
  /// - `elapsed` (from 0) — "0 years" / "26 years": the start day is zero, so
  ///   a birth-date anchor makes every later occurrence the age.
  ///
  /// Both render on the start day and both suppress only genuinely pre-start
  /// days (retroactive occurrences), so the origin is the single difference.
  static String? countLabel(
    CalendarEvent event,
    DateTime day,
    AppLocalizations l10n,
  ) {
    if (!event.countOccurrences) return null;
    final rule = event.rule;
    final elapsed = rule.elapsedPeriods(day, event.startDate);
    if (elapsed == null) return null;
    return switch (event.countStyle) {
      OccurrenceCountStyle.numbered =>
        elapsed < 0
            ? null
            : switch (rule) {
                DailyRecurrence() => l10n.eventNumberedDays(elapsed + 1),
                WeeklyRecurrence() => l10n.eventNumberedWeeks(elapsed + 1),
                MonthlyRecurrence() => l10n.eventNumberedMonths(elapsed + 1),
                YearlyRecurrence() => l10n.eventNumberedYears(elapsed + 1),
                _ => null,
              },
      OccurrenceCountStyle.elapsed =>
        elapsed < 0
            ? null
            : switch (rule) {
                DailyRecurrence() => l10n.eventElapsedDays(elapsed),
                WeeklyRecurrence() => l10n.eventElapsedWeeks(elapsed),
                MonthlyRecurrence() => l10n.eventElapsedMonths(elapsed),
                YearlyRecurrence() => l10n.eventElapsedYears(elapsed),
                _ => null,
              },
    };
  }

  static String _ruleLabel(
    RecurrenceRule rule,
    AppLocalizations l10n,
    String localeName,
  ) {
    return switch (rule) {
      OneTimeRecurrence() => l10n.recurrenceNone,
      SpecificDatesRecurrence(:final dates) => l10n.recurrenceSpecificDates(
        dates.length,
      ),
      DailyRecurrence(:final interval) => l10n.recurrenceEveryDays(interval),
      WeeklyRecurrence(:final weekdays, :final interval) =>
        weekdays.isEmpty
            ? l10n.recurrenceEveryWeeks(interval)
            : l10n.recurrenceEveryWeeksOn(
                interval,
                formatWeekdays(weekdays, localeName),
              ),
      MonthlyRecurrence(:final interval) => l10n.recurrenceEveryMonths(
        interval,
      ),
      YearlyRecurrence(:final interval) => l10n.recurrenceEveryYears(interval),
      WorkdaysRecurrence() => l10n.recurrenceWorkdays,
      WeekendsRecurrence() => l10n.recurrenceWeekends,
      PublicHolidaysOnlyRecurrence() => l10n.recurrenceHolidaysOnly,
    };
  }

  /// "Mon, Wed, Fri" (locale-aware abbreviated weekday names).
  static String formatWeekdays(Set<int> weekdays, String localeName) {
    final sorted = weekdays.toList()..sort();
    return sorted.map((d) => weekdayShort(d, localeName)).join(', ');
  }

  /// 1=Mon..7=Sun → locale-specific short weekday label.
  static String weekdayShort(int weekday, String localeName) {
    // 2024-01-01 was a Monday; offset by (weekday-1) days to land on it.
    final anchor = DateTime(2024, 1, 1).add(Duration(days: weekday - 1));
    return DateFormat.E(localeName).format(anchor);
  }
}
