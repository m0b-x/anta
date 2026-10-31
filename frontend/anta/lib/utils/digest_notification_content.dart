import '../constants/alert_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_report.dart';
import '../models/event_digest.dart';
import '../services/recurrence_formatter.dart';
import 'alert_labels.dart';
import 'digest_planner.dart';
import 'event_agenda.dart';
import 'report_labels.dart';

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
///
/// [report] is the fold of a report cadence's span, or null while that span
/// has not ended — the scheduler arms two fires ahead, so the later one is
/// armed before anything it would count has happened.
DigestNotificationContent digestNotificationContent(
  PlannedDigest fire,
  AppLocalizations strings,
  AlertLabels labels, {
  required String Function(String categoryId) categoryLabel,
  required CalendarWeekStart weekStart,
  CalendarReport? report,
}) {
  if (fire.digest.cadence.isReport) {
    return _reportContent(
      fire.digest,
      strings,
      report,
      categoryLabel: categoryLabel,
    );
  }
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

/// A report digest's words (P): "Weekly report · Gym" over the summary line
/// and one line per category in the report's order, worded by the same
/// [ReportLabels] the page uses so the two never read a number two ways.
/// Without [report] the body is the one generic line — never a zero that
/// only means "not counted yet".
DigestNotificationContent _reportContent(
  EventDigest digest,
  AppLocalizations strings,
  CalendarReport? report, {
  required String Function(String categoryId) categoryLabel,
}) {
  final weekly = digest.cadence == DigestCadence.weeklyReport;
  final title = [
    weekly ? strings.digestReportWeeklyTitle : strings.digestReportMonthlyTitle,
    digestTitleOf(digest, strings, categoryLabel: categoryLabel),
  ].join(ReportLabels.separator);
  if (report == null) {
    return DigestNotificationContent(
      title: title,
      text: weekly
          ? strings.digestReportReadyWeek
          : strings.digestReportReadyMonth,
    );
  }
  final words = ReportLabels(strings);
  final all = [
    _reportSummary(
      report,
      words,
      // Every category is the facts alone: "Events — 12 events" read twice.
      categories: digest.categoryIds.isEmpty
          ? null
          : digestCategoriesLabel(
              digest.categoryIds,
              strings,
              categoryLabel: categoryLabel,
            ),
    ),
    for (final group in report.categories)
      _reportCategoryLine(
        group,
        report,
        words,
        name: categoryLabel(group.categoryId),
      ),
  ];
  return DigestNotificationContent(
    title: title,
    text: all.first,
    lines: all.take(kDigestMaxLines).toList(),
    summary: all.length > kDigestMaxLines
        ? strings.digestMoreCount(all.length - kDigestMaxLines)
        : null,
  );
}

/// "Gym — 5 of 6 attended · 6 h · 1 missed": attended of tracked when the
/// Attended tile counts something, else the events that happened — the
/// builder emits that tile for any routine in the selection, so a paused one
/// beside three birthdays would read "0 of 0 attended" and never name them.
/// Without [categories] (every category) the line is the facts alone.
String _reportSummary(
  CalendarReport report,
  ReportLabels words, {
  required String? categories,
}) {
  ReportTileValue? tileOf(ReportTile tile) {
    for (final value in report.tiles) {
      if (value.tile == tile) return value;
    }
    return null;
  }

  final l10n = words.l10n;
  final attended = tileOf(ReportTile.attended);
  final attendedOf = attended?.of;
  final minutes = tileOf(ReportTile.hours)?.value ?? 0;
  final missed = tileOf(ReportTile.missed)?.value ?? 0;
  final facts = [
    attendedOf != null && attendedOf > 0
        ? l10n.reportAttendedOf(attendedOf, attended!.value)
        : l10n.reportEventCount(tileOf(ReportTile.events)?.value ?? 0),
    if (minutes > 0) words.hours(minutes),
    if (missed > 0) l10n.dayListMissedCount(missed),
  ];
  final joined = facts.join(ReportLabels.separator);
  return categories == null
      ? joined
      : l10n.digestReportSummary(categories, joined);
}

/// One category's line, worded by the shape with the most occurrences in it
/// — a routine's are the days it ran, every dated row is one: "Gym · 4 of 4
/// · 5 h", "Birthday · 3 · Ana, Mihai, Ioana", "To do · 4 · 9 of 12 tasks"
/// or "Trips · 2 · 3 h".
String _reportCategoryLine(
  ReportCategoryGroup group,
  CalendarReport report,
  ReportLabels words, {
  required String name,
}) {
  final l10n = words.l10n;
  var routine = 0;
  var attended = 0;
  // The routine line's hours are its routines' alone, not the group's: a
  // timed one-off beside them would lend the line hours no routine kept.
  var routineMinutes = 0;
  var repeat = 0;
  var oneOff = 0;
  var ticked = 0;
  var tasks = 0;
  var hasTasks = false;
  // Ordered and unique: a daily repeat lists its title once, not seven times.
  final titles = <String>{};
  for (final row in group.rows) {
    switch (row) {
      case ReportRoutineRow():
        routine += row.total;
        attended += row.attended;
        routineMinutes += row.minutes;
      case ReportDatedRow():
        final event = report.events[row.eventId];
        if (event != null && shapeOf(event) == ReportShape.repeat) {
          repeat++;
          titles.add(event.title);
        } else {
          oneOff++;
        }
        final count = row.tasks;
        if (count != null) {
          hasTasks = true;
          ticked += count.ticked;
          tasks += count.total;
        }
    }
  }
  final facts = <String>[
    if (routine >= repeat && routine >= oneOff) ...[
      l10n.reportOfTotal(words.count(attended), words.count(routine)),
      if (routineMinutes > 0) words.hours(routineMinutes),
    ] else if (repeat >= oneOff) ...[
      words.count(group.count),
      titles.join(', '),
    ] else ...[
      words.count(group.count),
      if (hasTasks)
        l10n.reportTasksOf(tasks, ticked)
      else if (group.minutes > 0)
        words.hours(group.minutes),
    ],
  ];
  return [name, ...facts].join(ReportLabels.separator);
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
/// it, "last" for a report's span, which ended before it fires; a span that
/// is not the whole unit, such as a week from Wednesday or a month from the
/// 15th, is never called one.
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
    case DigestCadence.weeklyReport:
      if (start.weekday == weekStart.weekday) {
        return strings.digestPeriodLastWeek;
      }
    case DigestCadence.monthlyReport:
      if (start.day == 1) return strings.digestPeriodLastMonth;
  }
  return strings.digestPeriodSpan(
    labels.entryDateLabel(start),
    labels.entryDateLabel(spanEnd),
  );
}
