import '../constants/event_priorities.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/recurrence_rule.dart';
import 'event_time_formatter.dart';
import 'recurrence_formatter.dart';

/// The localized text an agenda row **displays** beyond its title, its
/// description and its category label — the recurrence pattern, the time (or
/// the explicit "All day" badge) and the priority word.
///
/// Exists so the agenda's search can honour the one principle that makes it
/// predictable: if a row shows the text, typing that text finds the row.
/// `EventAgenda` cannot build this itself — it is deliberately
/// `AppLocalizations`-free, which is why the scan takes it as a closure the way
/// it already takes the category labels as a map.
///
/// Composition mirrors `EventSummaryProvider._subtitleFor` segment for segment,
/// with one deliberate omission: `RecurrenceFormatter.countLabel` is a function
/// of *(event, day)*, so folding it here would make the per-event fold a lie
/// and push the work onto the per-(event, day) path the scan exists to keep
/// empty.
abstract final class AgendaSearchText {
  /// Same separator the rows render with, so a query can be typed straight off
  /// the screen either way — the terms are AND-ed independently regardless.
  static const String separator = ' \u00b7 ';

  static String forEvent(CalendarEvent event, AppLocalizations l10n) {
    final time = event.time;
    final parts = <String>[
      if (event.rule is! OneTimeRecurrence)
        RecurrenceFormatter.format(
          event.rule,
          l10n,
          l10n.localeName,
          retroactive: event.retroactive,
        ),
      if (time != null)
        EventTimeFormatter.formatRange(time, l10n)
      else
        l10n.eventAllDay,
      // The row hides the badge at the neutral middle, so folding the word
      // there would find rows showing no priority at all.
      if (event.priority != kDefaultEventPriority)
        EventPriorities.labelOf(event.priority, l10n),
    ];
    return parts.join(separator);
  }
}
