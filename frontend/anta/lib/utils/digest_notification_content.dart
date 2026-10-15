import '../constants/alert_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/event_digest.dart';
import '../services/recurrence_formatter.dart';
import 'alert_labels.dart';
import 'digest_planner.dart';
import 'event_agenda.dart';

/// The words of one digest notification, written when it is armed.
class DigestNotificationContent {
  const DigestNotificationContent({
    required this.title,
    required this.text,
    this.lines = const <String>[],
    this.summary,
  });

  final String title;

  /// The collapsed line: the count and the span, then the first occurrences
  /// inline by date and title — the platform cuts what does not fit.
  final String text;

  /// The expanded list, at most [kDigestMaxLines], one occurrence each.
  final List<String> lines;

  /// "+N more" under [lines] when the span holds more than they list.
  final String? summary;
}

/// The words of [fire]'s notification, in [strings]' language with every day
/// written by [labels] (§3.6 of `docs/category-alerts-and-digests-roadmap.md`).
///
/// **Called on the UI isolate when the digest is armed**, never where it is
/// posted: its words are a list of days and titles that no payload field can
/// carry unwritten, and nothing formats a date in the background isolate.
/// The payload then carries these strings, and `alertNotificationContent`
/// only places them.
///
/// [categoryLabel] names a category for a digest titled after the one it
/// lists; [weekStart] is the app's week start, which decides whether a weekly
/// span is "this week" — the calendar never reads the locale's first weekday,
/// and neither does this.
DigestNotificationContent digestNotificationContent(
  PlannedDigest fire,
  AppLocalizations strings,
  AlertLabels labels, {
  required String Function(String categoryId) categoryLabel,
  required CalendarWeekStart weekStart,
}) {
  final title = digestTitleOf(
    fire.digest,
    strings,
    categoryLabel: categoryLabel,
  );

  final entries = fire.entries;
  final count = entries.length;
  final shown = entries.take(kDigestMaxLines);
  final lines = [
    for (final occurrence in shown) _lineOf(occurrence, strings, labels),
  ];
  // The collapsed row is one line the platform cuts: the date without its
  // weekday and the title, so more of them fit before it does.
  final inline = [
    for (final occurrence in shown)
      strings.alertsDayThenWhen(
        labels.entryDateLabel(occurrence.day),
        occurrence.event.title,
      ),
  ];
  final head = strings.digestCountPeriod(
    count,
    digestPeriodOf(
      fire.digest,
      spanStart: fire.spanStart,
      spanEnd: fire.spanEnd,
      strings: strings,
      labels: labels,
      weekStart: weekStart,
    ),
  );
  return DigestNotificationContent(
    title: title,
    text: inline.isEmpty ? head : '$head · ${inline.join(', ')}',
    lines: lines,
    summary: count > kDigestMaxLines
        ? strings.digestMoreCount(count - kDigestMaxLines)
        : null,
  );
}

/// What a digest is called wherever it is named — the notification's title,
/// the hub's rows, the sheet's hint: its name, else what it lists.
///
/// One rule for every surface, so the row the owner switches off and the
/// notification it stops can never disagree about what it is called.
String digestTitleOf(
  EventDigest digest,
  AppLocalizations strings, {
  required String Function(String categoryId) categoryLabel,
}) {
  final name = digest.name.trim();
  if (name.isNotEmpty) return name;
  return digestCategoriesLabel(
    digest.categoryIds,
    strings,
    categoryLabel: categoryLabel,
  );
}

/// What an allowlist lists, in [digestTitleOf]'s words: one category's
/// label, "Events" for every category (an empty allowlist), else the count.
String digestCategoriesLabel(
  Set<String> categoryIds,
  AppLocalizations strings, {
  required String Function(String categoryId) categoryLabel,
}) {
  if (categoryIds.isEmpty) return strings.digestAllCategories;
  if (categoryIds.length == 1) return categoryLabel(categoryIds.single);
  return strings.digestCategoriesCount(categoryIds.length);
}

/// "Sat 4 Oct · Ana", and its count where the event counts its occurrences
/// ("· Year 30") — the one count formatter, so the line reads as the
/// overview's row does.
String _lineOf(
  EventOccurrence occurrence,
  AppLocalizations strings,
  AlertLabels labels,
) {
  final event = occurrence.event;
  final day = occurrence.day;
  final line = strings.alertsDayThenWhen(
    labels.entryDayLabel(day),
    event.title,
  );
  final countLabel = RecurrenceFormatter.countLabel(event, day, strings);
  return countLabel == null ? line : '$line · $countLabel';
}

/// The span as a word where one names it exactly — the day, the calendar
/// week from the app's week start, the calendar month — else "from {start}
/// to {end}", the dates without their weekdays.
///
/// "This" when the digest fires inside the span, "next" when it fires before
/// it; a span that is not the whole unit, such as a week from Wednesday or a
/// month from the 15th, is never called one.
///
/// Public for the hub's fire rows and the digest sheet's caption, which say
/// the count the notification will say in the same words.
String digestPeriodOf(
  EventDigest digest, {
  required DateTime spanStart,
  required DateTime spanEnd,
  required AppLocalizations strings,
  required AlertLabels labels,
  required CalendarWeekStart weekStart,
}) {
  final lead = digest.leadDays;
  final start = spanStart;
  switch (digest.cadence) {
    case DigestCadence.daily:
      if (lead == 0) return strings.digestPeriodToday;
      if (lead == 1) return strings.digestPeriodTomorrow;
    case DigestCadence.weekly:
      if (start.weekday == weekStart.weekday) {
        return lead == 0
            ? strings.digestPeriodThisWeek
            : strings.digestPeriodNextWeek;
      }
    case DigestCadence.monthly:
      if (start.day == 1) {
        return lead == 0
            ? strings.digestPeriodThisMonth
            : strings.digestPeriodNextMonth;
      }
  }
  return strings.digestPeriodSpan(
    labels.entryDateLabel(start),
    labels.entryDateLabel(spanEnd),
  );
}
