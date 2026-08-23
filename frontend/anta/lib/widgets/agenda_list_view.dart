import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/calendar_colors.dart';
import '../constants/fasting_calendar.dart';
import '../constants/event_priorities.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/day_summary_entry.dart';
import '../utils/markdown_color_syntax.dart';
import 'markdown_inline_text.dart';
import '../services/day_summary_resolver.dart';
import '../utils/event_agenda.dart';

/// Flattens an occurrence list into month separators, day headers and entry
/// rows so a single `ListView.builder` can render the grouped agenda.
///
/// Holiday days are merged into the same ascending walk, so a day that is
/// only a holiday still gets a header and a row. Within a day, events come
/// first and the holiday last — matching the day summary panel, where the
/// holiday entry's higher `priority` value sinks it below the events.
///
/// Fasting arrives one of three ways, mutually exclusive at the call site:
/// [fastingDays] lists every fasting day, [fastingRuns] carries whole periods
/// already collapsed to one row each, and [fastingSummaries] digests the whole
/// window into one card per tradition. A run's entries are the provider's own
/// with the subtitle swapped for the period's span; a summary's entry is
/// synthesized here outright — agenda-only presentation either way, so
/// `FastingSummaryProvider` and the day panel it also feeds stay untouched.
///
/// Summary cards are emitted **before** the first month or day header, because
/// they describe the window rather than a day inside it. They are
/// [AgendaFastingSummaryRow]s and not [AgendaEntryRow]s, so a caller counting
/// entries leaves them out with no extra logic — a card summarizes entries
/// rather than being one.
///
/// Month separators appear only when the emitted rows actually span two or
/// more months, so a one-month window looks exactly as it did.
///
/// Missed occurrences are dropped here in hidden mode, before the day's
/// header is emitted — so a day left with nothing produces no header either,
/// and the per-day entry count stays honest. That is also why the count the
/// panel header shows must be derived from these rows rather than from the
/// scan: only here is it known what survives.
///
/// Pure *given the `EventPresence` / `OccurrenceDescriptions` facades* — both
/// are static caches read while the rows are built, so any memo over this
/// function must key `occurrenceRevision` as well as its arguments.
List<AgendaRow> buildAgendaRows({
  required List<EventOccurrence> occurrences,
  required List<DateTime> holidayDays,
  required List<DateTime> fastingDays,
  required AppLocalizations l10n,
  required bool showRecurrenceLabels,
  required CalendarMissedDisplay missedDisplay,
  List<FastingRun> fastingRuns = const [],
  List<FastingSummary> fastingSummaries = const [],
}) {
  final hideMissed = missedDisplay == CalendarMissedDisplay.hidden;
  final eventProvider = EventSummaryProvider(
    l10n,
    showRecurrence: showRecurrenceLabels,
  );
  final holidayProvider = PublicHolidaySummaryProvider(l10n);
  final fastingProvider = FastingSummaryProvider(l10n);

  // One cursor shape for both fasting modes, so the merge walk below does not
  // branch: a collapsed run is placed on its first in-window day. Several runs
  // can share that day (one per tradition/period), so the cursor is consumed
  // as a group rather than one entry at a time.
  final fasting = fastingRuns.isNotEmpty
      ? [for (final run in fastingRuns) (day: run.day, run: run)]
      : [for (final day in fastingDays) (day: day, run: null)];

  final groups = <({DateTime day, List<AgendaEntryRow> rows})>[];
  var index = 0;
  var holidayIndex = 0;
  var fastingIndex = 0;

  while (index < occurrences.length ||
      holidayIndex < holidayDays.length ||
      fastingIndex < fasting.length) {
    final nextEventDay = index < occurrences.length
        ? occurrences[index].day
        : null;
    final nextHolidayDay = holidayIndex < holidayDays.length
        ? holidayDays[holidayIndex]
        : null;
    final nextFastingDay = fastingIndex < fasting.length
        ? fasting[fastingIndex].day
        : null;

    // Earliest of the (up to) three cursors, without allocating a list.
    DateTime? earliest = nextEventDay;
    if (nextHolidayDay != null &&
        (earliest == null || nextHolidayDay.isBefore(earliest))) {
      earliest = nextHolidayDay;
    }
    if (nextFastingDay != null &&
        (earliest == null || nextFastingDay.isBefore(earliest))) {
      earliest = nextFastingDay;
    }
    final day = earliest!;

    final dayEvents = <CalendarEvent>[];
    // How many occurrences each of the day's events stands for — 1 unless the
    // collapse pass folded its other days into this one.
    final dayCounts = <String, int>{};
    while (index < occurrences.length && occurrences[index].day == day) {
      final occurrence = occurrences[index];
      dayEvents.add(occurrence.event);
      dayCounts[occurrence.event.id] = occurrence.occurrenceCountInWindow;
      index++;
    }
    final isHoliday = nextHolidayDay == day;
    if (isHoliday) holidayIndex++;
    // Every run starting on this day, not just the first: two traditions (or
    // an overlapping period) legitimately open on the same date, and stopping
    // at one would strand the rest on later days they do not belong to.
    final dayRuns = <FastingRun>[];
    var perDayFasting = false;
    while (fastingIndex < fasting.length && fasting[fastingIndex].day == day) {
      final run = fasting[fastingIndex].run;
      if (run != null) {
        dayRuns.add(run);
      } else {
        perDayFasting = true;
      }
      fastingIndex++;
    }

    final entries = <DaySummaryEntry>[
      for (final entry in eventProvider.summaryFor(day, dayEvents))
        if (!hideMissed || !entry.missed) entry,
      if (isHoliday) ...holidayProvider.summaryFor(day, dayEvents),
      if (perDayFasting) ...fastingProvider.summaryFor(day, dayEvents),
      for (final run in dayRuns)
        ..._fastingEntries(fastingProvider, day, dayEvents, run, l10n),
    ];
    if (entries.isEmpty) continue;
    groups.add((
      day: day,
      rows: [
        for (final entry in entries)
          AgendaEntryRow(
            day: day,
            entry: entry,
            occurrenceCount: dayCounts[entry.event?.id] ?? 1,
          ),
      ],
    ));
  }

  // Built before the day groups are flattened, not appended after them: a
  // summary describes the whole window, so it leads the list.
  final rows = <AgendaRow>[
    for (final summary in fastingSummaries)
      AgendaFastingSummaryRow(
        summary: summary,
        entry: _fastingSummaryEntry(summary, l10n),
      ),
  ];
  if (groups.isEmpty) return rows;

  final firstDay = groups.first.day;
  final lastDay = groups.last.day;
  final multiMonth =
      firstDay.year != lastDay.year || firstDay.month != lastDay.month;
  final crossesYear = firstDay.year != lastDay.year;

  int? currentMonth;
  for (final group in groups) {
    if (multiMonth) {
      final key = group.day.year * 12 + group.day.month;
      if (key != currentMonth) {
        currentMonth = key;
        rows.add(
          AgendaMonthHeaderRow(
            month: DateTime.utc(group.day.year, group.day.month, 1),
            showYear: crossesYear,
          ),
        );
      }
    }
    rows.add(AgendaDayHeaderRow(day: group.day, count: group.rows.length));
    rows.addAll(group.rows);
  }
  return rows;
}

/// One collapsed run's rows: the provider's entry **for that run's tradition**,
/// with the day's regime subtitle replaced by the period's span.
///
/// The tradition filter is what keeps two runs opening on the same day from
/// each rendering the other's entry — the provider answers for the whole day,
/// while a run speaks for one tradition.
///
/// A run of one marked day keeps the regime: a "Nov 15 – Nov 15 · 1 day"
/// subtitle says less than "Fish allowed".
Iterable<DaySummaryEntry> _fastingEntries(
  FastingSummaryProvider provider,
  DateTime day,
  List<CalendarEvent> dayEvents,
  FastingRun run,
  AppLocalizations l10n,
) {
  final key = 'fasting:${run.tradition.name}';
  final entries = provider
      .summaryFor(day, dayEvents)
      .where((entry) => entry.key == key);
  if (run.dayCount <= 1) return entries;
  final span =
      '${AgendaListView.rangeLabel(l10n.localeName, run.start, run.end)}'
      ' · ${l10n.upcomingFastingSpanDays(run.dayCount)}';
  return [
    for (final entry in entries)
      DaySummaryEntry(
        key: entry.key,
        icon: entry.icon,
        color: entry.color,
        title: entry.title,
        subtitle: span,
        description: entry.description,
        priority: entry.priority,
      ),
  ];
}

/// Two months. Exact dates stay readable up to roughly that span, and beyond
/// it the month is the useful unit — nobody reads "Mar 2 – Dec 24" as a shape.
const int _exactSpanMaxDays = 62;

/// The card standing in for a whole window of one tradition's fasting.
///
/// Synthesized here rather than taken from [FastingSummaryProvider]: the
/// provider answers for a *day*, and this row deliberately has none. Every
/// input is still the tradition's own — the same `styleOf` / `colorOf` /
/// `iconFor` a run row resolves through — so a summary card and a period row
/// read as the same tradition.
///
/// The title prefers the user's override, then the window's single named fast
/// (a Nativity-Fast-only window should say so), and falls back to the
/// tradition's name once several named fasts, or none, are in play.
DaySummaryEntry _fastingSummaryEntry(
  FastingSummary summary,
  AppLocalizations l10n,
) {
  final style = FastingCalendar.styleOf(summary.tradition);
  return DaySummaryEntry(
    key: 'fasting:${summary.tradition.name}',
    icon: FastingCalendar.iconFor(summary.tradition),
    color: FastingCalendar.colorOf(summary.tradition),
    title:
        style.titleOverride ??
        (summary.spanPeriods.length == 1
            ? FastingCalendar.periodNameOf(summary.spanPeriods.single, l10n)
            : FastingCalendar.traditionNameOf(summary.tradition, l10n)),
    subtitle: _fastingSummarySubtitle(summary, l10n),
    description: style.description,
    priority: style.priority,
  );
}

/// "Wed, Fri · Mar 2 – Apr 18 · 14 days" — which days, over what stretch, how
/// many. The whole point of the summary card is that these three fragments
/// replace the rows they stand for, so each has to survive on its own.
String _fastingSummarySubtitle(FastingSummary summary, AppLocalizations l10n) {
  final span =
      summary.last.difference(summary.first).inDays <= _exactSpanMaxDays
      ? AgendaListView.rangeLabel(l10n.localeName, summary.first, summary.last)
      : AgendaListView.monthRangeLabel(
          l10n.localeName,
          summary.first,
          summary.last,
        );
  return [
    _weekdayPattern(summary.weekdays, l10n),
    span,
    l10n.upcomingFastingSpanDays(summary.dayCount),
  ].join(' · ');
}

/// The weekday fragment: the three patterns that already have a name, else the
/// abbreviated weekday names in Monday-first order.
///
/// Joined with ', ' and never with a conjunction — "and"/"und"/"și" placement
/// is locale-dependent, and a list this short does not need one.
String _weekdayPattern(Set<int> weekdays, AppLocalizations l10n) {
  if (weekdays.length == 7) return l10n.recurrenceDaily;
  if (weekdays.length == 5 &&
      !weekdays.contains(DateTime.saturday) &&
      !weekdays.contains(DateTime.sunday)) {
    return l10n.recurrenceWorkdays;
  }
  if (weekdays.length == 2 &&
      weekdays.contains(DateTime.saturday) &&
      weekdays.contains(DateTime.sunday)) {
    return l10n.recurrenceWeekends;
  }
  final sorted = weekdays.toList()..sort();
  return [
    for (final weekday in sorted)
      AgendaListView.weekdayLabel(l10n.localeName, weekday),
  ].join(', ');
}

/// Grouped agenda list: a day header followed by one card per occurrence.
///
/// A pure renderer over rows built by [buildAgendaRows]: the owner holds the
/// memo, so the count it prints above this list and the rows drawn in it come
/// from one computation and can never disagree.
///
/// Rows are rendered from [EventSummaryProvider] entries rather than from the
/// events directly, so the agenda inherits the day summary panel's icon,
/// tint and subtitle resolution and the two surfaces cannot drift apart.
class AgendaListView extends StatelessWidget {
  /// The flattened rows to draw, in order.
  final List<AgendaRow> rows;

  /// Called when a row is tapped — typically to focus the calendar on the
  /// occurrence's day.
  final ValueChanged<DateTime> onDaySelected;

  /// Carries the row's occurrence day so the editor can scope to it (v24).
  final void Function(CalendarEvent event, DateTime day) onEditEvent;
  final ValueChanged<CalendarEvent> onOpenNote;

  final String emptyTitle;
  final String emptyHint;
  final EdgeInsets padding;

  /// Palette for `{name:text}` runs inside event descriptions, mirroring the
  /// day summary panel so both surfaces render a description identically.
  final MarkdownColorPalette colorPalette;

  /// Optional external scroll controller. The owner uses it to reset the list
  /// to the top when the window's anchor day changes, so the tapped day
  /// becomes the first row instead of the old offset surviving against a
  /// now-shorter list. Ignored in [sliver] mode — the ancestor
  /// `CustomScrollView` owns the controller there.
  final ScrollController? controller;

  /// When true, builds a `SliverList` (wrapped in the same [padding] via
  /// `SliverPadding`) for use inside a `CustomScrollView`, instead of a
  /// self-contained `ListView`. Both stay lazily built — only the shell
  /// differs — so this never trades away virtualization for a 366-day window.
  final bool sliver;

  const AgendaListView({
    super.key,
    required this.rows,
    required this.onDaySelected,
    required this.onEditEvent,
    required this.onOpenNote,
    required this.emptyTitle,
    required this.emptyHint,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
    this.colorPalette = MarkdownColorPalette.presets,
    this.controller,
    this.sliver = false,
  });

  /// Qualitative priority word appended to a row subtitle. The neutral
  /// default is omitted so only events the user deliberately ranked carry
  /// the extra word.
  static String? priorityBadge(AppLocalizations l10n, int priority) {
    if (priority == kDefaultEventPriority) return null;
    return EventPriorities.labelOf(priority, l10n);
  }

  /// Cached `DateFormat.MMMMEEEEd` per locale — it parses a skeleton on
  /// construction and every visible day header would otherwise rebuild one.
  static final Map<String, DateFormat> _dayHeaderFormatCache = {};

  /// Same caching rule for the three other skeletons the agenda formats with:
  /// the abbreviated day used by range labels, and the month separators.
  static final Map<String, DateFormat> _rangeFormatCache = {};
  static final Map<String, DateFormat> _monthFormatCache = {};
  static final Map<String, DateFormat> _monthYearFormatCache = {};

  /// Same caching rule for the two skeletons the fasting summary card needs:
  /// the abbreviated weekday name, and the abbreviated month.
  static final Map<String, DateFormat> _weekdayFormatCache = {};
  static final Map<String, DateFormat> _monthShortFormatCache = {};
  static final Map<String, DateFormat> _monthShortYearFormatCache = {};

  /// "Aug 10 – Sep 8". The single range label — the panel header, the custom
  /// period chip and a collapsed fasting period's span all read the same way.
  static String rangeLabel(String localeName, DateTime start, DateTime end) {
    final format = _rangeFormatCache[localeName] ??= DateFormat.MMMd(
      localeName,
    );
    return '${format.format(start)} – ${format.format(end)}';
  }

  /// "Aug 25" — one end of a range, for the header's anchor chip.
  static String anchorLabel(String localeName, DateTime day) {
    return (_rangeFormatCache[localeName] ??= DateFormat.MMMd(
      localeName,
    )).format(day);
  }

  /// "Aug – Dec" — the wide counterpart of [rangeLabel], for spans where exact
  /// dates stop being a shape and the month becomes the useful unit. Collapses
  /// to a single month name when both ends share one.
  ///
  /// A window may reach [EventAgenda.maxRangeDays], so its ends can carry the
  /// same month name a year apart — where a bare "Aug – Aug" would say
  /// nothing, and the year comes along exactly as it does for a month header.
  static String monthRangeLabel(
    String localeName,
    DateTime start,
    DateTime end,
  ) {
    if (start.year != end.year) {
      final format = _monthShortYearFormatCache[localeName] ??= DateFormat.yMMM(
        localeName,
      );
      return '${format.format(start)} – ${format.format(end)}';
    }
    final format = _monthShortFormatCache[localeName] ??= DateFormat.MMM(
      localeName,
    );
    if (start.month == end.month) return format.format(start);
    return '${format.format(start)} – ${format.format(end)}';
  }

  /// Abbreviated locale weekday name for a `DateTime.weekday` value, anchored
  /// on 2024-01-01 (a Monday) — the same trick the appearance system's
  /// week-start labels use, so no ARB weekday matrix has to exist.
  static String weekdayLabel(String localeName, int weekday) {
    return (_weekdayFormatCache[localeName] ??= DateFormat.E(
      localeName,
    )).format(DateTime.utc(2024, 1, weekday));
  }

  static String monthLabel(
    String localeName,
    DateTime month, {
    required bool withYear,
  }) {
    if (withYear) {
      return (_monthYearFormatCache[localeName] ??= DateFormat.yMMMM(
        localeName,
      )).format(month);
    }
    return (_monthFormatCache[localeName] ??= DateFormat.MMMM(
      localeName,
    )).format(month);
  }

  /// [today] is passed in rather than read here so the owner computes it once
  /// per build instead of once per visible header row.
  static String dayHeaderLabel(
    AppLocalizations l10n,
    DateTime day,
    DateTime today,
  ) {
    if (day == today) return l10n.upcomingToday;
    if (day == today.add(const Duration(days: 1))) return l10n.upcomingTomorrow;
    return (_dayHeaderFormatCache[l10n.localeName] ??= DateFormat.MMMMEEEEd(
      l10n.localeName,
    )).format(day);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (rows.isEmpty) {
      final empty = AgendaEmptyState(title: emptyTitle, hint: emptyHint);
      // `hasScrollBody: true` (the default) hands the child a fixed
      // BoxConstraints tight to the remaining viewport extent, with no
      // intrinsic-height probe — `hasScrollBody: false` computes one, and
      // `AgendaEmptyState`'s `LayoutBuilder` explicitly refuses to answer
      // that (`LayoutBuilder does not support returning intrinsic
      // dimensions`), which crashed every empty-state render in sliver mode.
      // `AgendaEmptyState` already manages its own overflow internally
      // (`SingleChildScrollView` + `Center`), so `true` is also the
      // semantically correct choice here, not just the one that compiles.
      return sliver ? SliverFillRemaining(child: empty) : empty;
    }

    // Computed once here, not per visible header, and handed to
    // `dayHeaderLabel` for its Today/Tomorrow test.
    final today = EventAgenda.dateOnly(DateTime.now());

    Widget buildItem(BuildContext context, int index) {
      final row = rows[index];
      return switch (row) {
        AgendaMonthHeaderRow(:final month, :final showYear) => Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 20, bottom: 4),
          child: Row(
            children: [
              Text(
                AgendaListView.monthLabel(
                  l10n.localeName,
                  month,
                  withYear: showYear,
                ),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Divider(height: 1, color: colorScheme.outlineVariant),
              ),
            ],
          ),
        ),
        AgendaDayHeaderRow(:final day, :final count) => Padding(
          // A month separator already opened the gap above it, so the day
          // header that follows one must not add a second.
          padding: EdgeInsets.only(
            top: index == 0 || rows[index - 1] is AgendaMonthHeaderRow ? 0 : 16,
            bottom: 8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  // Resolved here rather than while the rows are built, so a
                  // panel left open across midnight relabels on its next
                  // rebuild instead of invalidating the owner's memo.
                  AgendaListView.dayHeaderLabel(l10n, day, today),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                // "Entries", not "events": with holidays interleaved the
                // count covers both, and the day panel's existing key
                // already says exactly that in every locale.
                l10n.daySummaryEntryCount(count),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        AgendaFastingSummaryRow(:final summary, :final entry) => Padding(
          // Same bottom gap as an entry row, and no special top padding: the
          // month or day header that follows is no longer at index 0, so it
          // opens its normal gap under the card.
          padding: const EdgeInsets.only(bottom: 8),
          child: _AgendaCard(
            entry: entry,
            // No event: nothing to rank, nothing to edit, nothing to open.
            priorityBadge: null,
            onTap: () => onDaySelected(summary.first),
            colorPalette: colorPalette,
          ),
        ),
        AgendaEntryRow(:final day, :final entry, :final occurrenceCount) =>
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AgendaCard(
              entry: entry,
              missed: entry.missed,
              priorityBadge: AgendaListView.priorityBadge(
                l10n,
                entry.event?.priority ?? kDefaultEventPriority,
              ),
              collapsedBadge: occurrenceCount > 1
                  ? l10n.upcomingCollapsedTimes(occurrenceCount)
                  : null,
              onTap: () => onDaySelected(day),
              colorPalette: colorPalette,
              onEdit: entry.event == null
                  ? null
                  : () => onEditEvent(entry.event!, day),
              onOpenNote: entry.event?.noteId == null
                  ? null
                  : () => onOpenNote(entry.event!),
            ),
          ),
      };
    }

    if (sliver) {
      return SliverPadding(
        padding: padding,
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            buildItem,
            childCount: rows.length,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: controller,
      padding: padding,
      itemCount: rows.length,
      itemBuilder: buildItem,
    );
  }
}

/// A row in the flattened agenda: a month separator, a day header, or an
/// entry.
sealed class AgendaRow {
  const AgendaRow();
}

/// Separator introducing a new calendar month. Emitted only for windows that
/// span more than one, so short windows keep their old shape.
class AgendaMonthHeaderRow extends AgendaRow {
  /// First day of the month, as the label's only input.
  final DateTime month;

  /// Whether the label carries the year — true when the window itself crosses
  /// one, where a bare "January" would be ambiguous.
  final bool showYear;

  const AgendaMonthHeaderRow({required this.month, this.showYear = false});
}

class AgendaDayHeaderRow extends AgendaRow {
  final DateTime day;
  final int count;

  const AgendaDayHeaderRow({required this.day, required this.count});
}

class AgendaEntryRow extends AgendaRow {
  final DateTime day;
  final DaySummaryEntry entry;

  /// How many occurrences this row stands for. Greater than 1 only while
  /// "collapse recurring" is on, where the row is the event's next occurrence
  /// standing in for the rest of the window.
  final int occurrenceCount;

  const AgendaEntryRow({
    required this.day,
    required this.entry,
    this.occurrenceCount = 1,
  });
}

/// A whole window of one tradition's fasting, standing above the list it
/// summarizes.
///
/// Deliberately **not** an [AgendaEntryRow]: it belongs to no day, carries no
/// event, and must not be counted among the entries — it summarizes them.
class AgendaFastingSummaryRow extends AgendaRow {
  final FastingSummary summary;

  /// Synthesized by `buildAgendaRows`, so the card renders through the same
  /// path every other agenda row does.
  final DaySummaryEntry entry;

  const AgendaFastingSummaryRow({required this.summary, required this.entry});
}

/// Event card mirroring the day summary panel's accent-stripe layout so the
/// agenda and the day panel read as one system.
class _AgendaCard extends StatelessWidget {
  final DaySummaryEntry entry;
  final String? priorityBadge;

  /// "12x in window" when this row stands in for a recurring event's other
  /// collapsed occurrences, so a collapsed row cannot pass as a single event.
  final String? collapsedBadge;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onOpenNote;
  final MarkdownColorPalette colorPalette;

  /// Dims the whole card. Only reached in faded mode — hidden mode drops the
  /// row while the list is built.
  final bool missed;

  const _AgendaCard({
    required this.entry,
    required this.priorityBadge,
    required this.onTap,
    required this.colorPalette,
    this.collapsedBadge,
    this.onEdit,
    this.onOpenNote,
    this.missed = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final subtitle = [
      ?entry.subtitle,
      ?priorityBadge,
      ?collapsedBadge,
    ].join(' · ');
    final description = entry.description;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Opacity(
          opacity: missed ? CalendarColors.missedEventAlpha : 1.0,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: entry.color),
              Expanded(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: entry.color.withValues(alpha: 0.16),
                    foregroundColor: entry.color,
                    child: Icon(entry.icon),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: l10n.eventHasDescription,
                          child: Icon(
                            Icons.notes_rounded,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: (subtitle.isEmpty && description == null)
                      ? null
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (subtitle.isNotEmpty) Text(subtitle),
                            if (description != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: MarkdownInlineText(
                                  data: description,
                                  colorPalette: colorPalette,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                  isThreeLine: description != null,
                  // Holiday rows carry no event, so they get no trailing
                  // actions at all rather than an empty action strip.
                  trailing: onOpenNote == null && onEdit == null
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (onOpenNote != null)
                              IconButton(
                                tooltip: l10n.eventOpenLinkedNote,
                                icon: const Icon(Icons.sticky_note_2_outlined),
                                onPressed: onOpenNote,
                              ),
                            if (onEdit != null)
                              IconButton(
                                tooltip: l10n.upcomingEditEvent,
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: onEdit,
                              ),
                          ],
                        ),
                  onTap: onTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared empty state for the agenda and timeline panel modes.
class AgendaEmptyState extends StatelessWidget {
  final String title;
  final String hint;

  const AgendaEmptyState({super.key, required this.title, required this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // The panel that hosts this can be squeezed shorter than the content's
    // natural height (e.g. a resized desktop window, or a tall calendar
    // grid in month view). LayoutBuilder + a scrollable keeps the content
    // centered when there's room and scrollable instead of overflowing when
    // there isn't.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.event_available_rounded,
                      size: 48,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
