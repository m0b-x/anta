import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
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
