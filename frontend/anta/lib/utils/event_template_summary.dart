import '../constants/calendar_categories.dart';
import '../l10n/app_localizations.dart';
import '../models/event_template.dart';
import '../models/recurrence_rule.dart';
import '../services/event_time_formatter.dart';
import '../services/recurrence_formatter.dart';

/// One-line description of what [template] will stamp out: category, then
/// schedule, then time. Joined with the same `·` separator the day panel and
/// agenda rows use, so a template row reads like the event it produces.
///
/// Shared by the templates page and the quick-add picker rather than written
/// twice — the two surfaces describing the same template differently is
/// exactly the drift this avoids.
String templateSummary(
  EventTemplate template,
  AppLocalizations l10n,
  String localeName,
) {
  final category = CalendarCategories.resolve(template.categoryId);
  final time = template.time;
  final parts = <String>[
    CalendarCategories.labelOf(category, l10n),
    if (template.rule is! OneTimeRecurrence)
      RecurrenceFormatter.format(
        template.rule,
        l10n,
        localeName,
        retroactive: template.retroactive,
      ),
    if (time != null)
      EventTimeFormatter.formatRange(time, l10n)
    else
      l10n.eventAllDay,
  ];
  return parts.join(' · ');
}
