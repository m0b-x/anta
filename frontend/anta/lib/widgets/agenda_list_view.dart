import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_colors.dart';
import '../constants/calendar_icons.dart';
import '../constants/fasting_calendar.dart';
import '../constants/public_holidays.dart';
import '../constants/event_priorities.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/day_summary_entry.dart';
import '../models/upcoming_agenda_filters.dart';
import '../utils/markdown_color_syntax.dart';
import 'agenda_day_list_sheet.dart';
import 'markdown_inline_text.dart';
import '../services/day_summary_resolver.dart';
import '../utils/event_agenda.dart';

/// Flattens an occurrence list into month separators, day headers and entry
/// rows so a single `ListView.builder` can render the grouped agenda.
///
/// Holiday days are merged into the same ascending walk, so a day that is
/// only a holiday still gets a header and a row. Within a day, events come
/// first and the holiday last — matching the day summary panel, where the
/// holiday entry's higher `priority` value sinks it below the events. Under
/// [AgendaHolidayDisplay.summary] they leave the walk entirely and become one
/// card built from the same [holidayDays] list.
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
/// they describe the window rather than a day inside it, and among themselves
/// they sort by their entry's `priority` — so the holiday card leads the
/// fasting ones by default, and a user who placed fasting first in the day
/// panel gets the same order here. They are [AgendaHolidaySummaryRow]s and
/// [AgendaFastingSummaryRow]s, never [AgendaEntryRow]s, so a caller counting
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
  AgendaHolidayDisplay holidayDisplay = AgendaHolidayDisplay.everyDay,
  List<EventCategorySummary> eventSummaries = const [],
}) {
  final hideMissed = missedDisplay == CalendarMissedDisplay.hidden;
  final eventProvider = EventSummaryProvider(
    l10n,
    showRecurrence: showRecurrenceLabels,
  );
  final holidayProvider = PublicHolidaySummaryProvider(l10n);
  final fastingProvider = FastingSummaryProvider(l10n);

  // In summary mode a layer leaves the day walk entirely — its cards below are
  // built from the very same list, so nothing is dropped, only relocated.
  final holidaysAsSummary = holidayDisplay == AgendaHolidayDisplay.summary;
  final walkedHolidays = holidaysAsSummary ? const <DateTime>[] : holidayDays;
  // Events are keyed off the summaries rather than a flag: they are a fold of
  // `occurrences`, so a non-empty list *is* the caller having chosen summary
  // mode, and the two can never contradict each other.
  final walkedOccurrences = eventSummaries.isEmpty
      ? occurrences
      : const <EventOccurrence>[];

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

  while (index < walkedOccurrences.length ||
      holidayIndex < walkedHolidays.length ||
      fastingIndex < fasting.length) {
    final nextEventDay = index < walkedOccurrences.length
        ? walkedOccurrences[index].day
        : null;
    final nextHolidayDay = holidayIndex < walkedHolidays.length
        ? walkedHolidays[holidayIndex]
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
    while (index < walkedOccurrences.length &&
        walkedOccurrences[index].day == day) {
      final occurrence = walkedOccurrences[index];
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
  // summary describes the whole window, so it leads the list. Sorted among
  // themselves by the entry priority the day panel already ranks by, so the
  // two surfaces agree about which annotation comes first — and tie-broken on
  // insertion order, because `List.sort` is **not** stable in Dart and several
  // cards legitimately share a priority (every event category sits in the
  // event band, and two fasting traditions share the fasting one).
  final summaryRows =
      <AgendaRow>[
        for (final summary in eventSummaries)
          AgendaEventSummaryRow(
            summary: summary,
            entry: _eventSummaryEntry(summary, l10n),
            rangeLabel: AgendaListView.rangeLabel(
              l10n.localeName,
              summary.first,
              summary.last,
            ),
          ),
        if (holidaysAsSummary && holidayDays.isNotEmpty)
          AgendaHolidaySummaryRow(
            days: holidayDays,
            entry: _holidaySummaryEntry(holidayDays, l10n),
            rangeLabel: AgendaListView.rangeLabel(
              l10n.localeName,
              holidayDays.first,
              holidayDays.last,
            ),
          ),
        for (final summary in fastingSummaries)
          AgendaFastingSummaryRow(
            summary: summary,
            entry: _fastingSummaryEntry(summary, l10n),
            rangeLabel: _fastingSummaryRangeLabel(summary, l10n),
          ),
      ].indexed.toList()..sort((a, b) {
        final byPriority = _summaryPriority(
          a.$2,
        ).compareTo(_summaryPriority(b.$2));
        return byPriority != 0 ? byPriority : a.$1.compareTo(b.$1);
      });

  final rows = <AgendaRow>[for (final entry in summaryRows) entry.$2];
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

/// Ranking among the summary cards, read off the entry each one already
/// carries. Reusing `DaySummaryEntry.priority` rather than hardcoding an order
/// is what makes the cards follow the placement the user chose for the day
/// panel — the public holiday sits at 150 and fasting defaults to 160, but
/// `FastingRowPlacement.first` legitimately puts a tradition above it.
int _summaryPriority(AgendaRow row) => switch (row) {
  AgendaEventSummaryRow(:final entry) => entry.priority,
  AgendaHolidaySummaryRow(:final entry) => entry.priority,
  AgendaFastingSummaryRow(:final entry) => entry.priority,
  _ => 0,
};

/// The card standing in for one category's whole window of events.
///
/// Icon, colour and title come from the category itself, so the card carries
/// the same identity its rows do. The count leads with **distinct events**
/// because a daily event across ninety days is one event, not ninety; the
/// occurrence tally follows, and only when it says something the event count
/// does not — a category of one-time events would just repeat itself.
DaySummaryEntry _eventSummaryEntry(
  EventCategorySummary summary,
  AppLocalizations l10n,
) {
  final category = CalendarCategories.resolve(summary.categoryId);
  return DaySummaryEntry(
    key: 'category:${summary.categoryId}',
    icon: CalendarIcons.forKey(category.iconKey) ?? Icons.event_rounded,
    color: category.color,
    title: CalendarCategories.labelOf(category, l10n),
    subtitle: [
      l10n.upcomingEventCount(summary.eventCount),
      if (summary.occurrenceCount > summary.eventCount)
        l10n.upcomingCollapsedTimes(summary.occurrenceCount),
    ].join(' · '),
    // The event band, so category cards lead the holiday (150) and fasting
    // (160) ones — the same order the day panel ranks these three in.
    priority: 0,
  );
}

/// The event card's drill-down: one row per occurrence, **date first**,
/// because the rows share a category and it is the date and title that vary.
///
/// Every row carries its edit action, so collapsing the events layer never
/// puts editing further away than it was in the list.
List<AgendaDayListEntry> _eventDayEntries(
  EventCategorySummary summary,
  AppLocalizations l10n,
  DateTime today,
  void Function(CalendarEvent event, DateTime day) onEditEvent,
) {
  return [
    for (final occurrence in summary.occurrences)
      AgendaDayListEntry(
        day: occurrence.day,
        icon: CalendarCategories.iconFor(occurrence.event),
        color: CalendarCategories.resolve(occurrence.event.categoryId).color,
        title: occurrence.event.title,
        subtitle: AgendaListView.dayHeaderLabel(l10n, occurrence.day, today),
        onEdit: () => onEditEvent(occurrence.event, occurrence.day),
      ),
  ];
}

/// The card standing in for every public holiday in the window.
///
/// Icon, colour, key and priority mirror [PublicHolidaySummaryProvider] exactly
/// — the provider answers for a *day* and this row has none, but the two must
/// still read as the same thing.
DaySummaryEntry _holidaySummaryEntry(
  List<DateTime> days,
  AppLocalizations l10n,
) {
  return DaySummaryEntry(
    key: 'holiday',
    icon: Icons.celebration_rounded,
    color: CalendarColors.publicHoliday,
    title: l10n.upcomingShowHolidays,
    subtitle: l10n.upcomingHolidayCount(days.length),
    priority: 150,
  );
}

/// The holiday card's drill-down: one row per holiday, **name first**, because
/// every row is a different holiday and the name is what distinguishes them.
List<AgendaDayListEntry> _holidayDayEntries(
  List<DateTime> days,
  AppLocalizations l10n,
  DateTime today,
) {
  return [
    for (final day in days)
      if (PublicHolidays.holidayOn(day) case final info?)
        AgendaDayListEntry(
          day: day,
          icon: Icons.celebration_rounded,
          color: CalendarColors.publicHoliday,
          // Carries the "(observed)" suffix for a substitute day, so two
          // Christmas rows in one week explain themselves here too.
          title: PublicHolidays.labelOf(info, l10n),
          subtitle: AgendaListView.dayHeaderLabel(l10n, day, today),
        ),
  ];
}

/// The fasting card's drill-down: one row per marked day, **date first**,
/// because every row belongs to the same fast and only the date varies.
///
/// The regime line comes from [FastingSummaryProvider] filtered to this
/// summary's tradition — the same reuse `_fastingEntries` makes for run rows,
/// so the title-override rule and the regime naming are inherited rather than
/// re-derived.
List<AgendaDayListEntry> _fastingDayEntries(
  FastingSummary summary,
  AppLocalizations l10n,
  DateTime today,
) {
  final provider = FastingSummaryProvider(l10n);
  final key = 'fasting:${summary.tradition.name}';
  return [
    for (final day in summary.days)
      if (provider
              .summaryFor(day, const [])
              .where((entry) => entry.key == key)
              .firstOrNull
          case final entry?)
        AgendaDayListEntry(
          day: day,
          icon: entry.icon,
          color: entry.color,
          title: AgendaListView.dayHeaderLabel(l10n, day, today),
          subtitle: [entry.title, ?entry.subtitle].join(' · '),
        ),
  ];
}

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

/// "Wed, Fri · 14 days" — which days, how many. The exact span is
/// [_fastingSummaryRangeLabel], rendered on the card's own second line so it
/// can never be the fragment a clip slices in half.
String _fastingSummarySubtitle(FastingSummary summary, AppLocalizations l10n) {
  return [
    _weekdayPattern(summary.weekdays, l10n),
    l10n.upcomingFastingSpanDays(summary.dayCount),
  ].join(' · ');
}

String _fastingSummaryRangeLabel(
  FastingSummary summary,
  AppLocalizations l10n,
) {
  return summary.last.difference(summary.first).inDays <= _exactSpanMaxDays
      ? AgendaListView.rangeLabel(l10n.localeName, summary.first, summary.last)
      : AgendaListView.monthRangeLabel(
          l10n.localeName,
          summary.first,
          summary.last,
        );
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

  /// Opens a summary card's drill-down. The list is built here, where the
  /// localized entries already are, and shown by the owner, which owns
  /// navigation — and which routes a picked day back through [onDaySelected].
  /// Null hides the cards' trailing button entirely.
  final ValueChanged<AgendaDayList>? onShowDayList;

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
    this.onShowDayList,
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

  /// "Today" / "Tomorrow" / "Aug 25" — [dayHeaderLabel]'s short twin, for
  /// places with no room for a full weekday-and-month date (the add button's
  /// label). Shares [anchorLabel]'s cached format, and [today] is passed in for
  /// the same reason: the caller computes it once.
  static String shortDayLabel(
    AppLocalizations l10n,
    DateTime day,
    DateTime today,
  ) {
    if (day == today) return l10n.upcomingToday;
    if (day == today.add(const Duration(days: 1))) return l10n.upcomingTomorrow;
    return anchorLabel(l10n.localeName, day);
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

    // Built on press, not per frame: a 366-day window's fasting card would
    // otherwise resolve forty-odd rows nobody has asked to see.
    void showDayList(
      String title,
      String subtitle,
      List<AgendaDayListEntry> Function() entries,
    ) {
      onShowDayList?.call(
        AgendaDayList(title: title, subtitle: subtitle, entries: entries()),
      );
    }

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
        AgendaFastingSummaryRow(
          :final summary,
          :final entry,
          :final rangeLabel,
        ) =>
          Padding(
            // Same bottom gap as an entry row, and no special top padding: the
            // month or day header that follows is no longer at index 0, so it
            // opens its normal gap under the card.
            padding: const EdgeInsets.only(bottom: 8),
            child: _AgendaCard(
              entry: entry,
              // No event: nothing to rank, nothing to edit, nothing to open.
              priorityBadge: null,
              secondaryLine: rangeLabel,
              onTap: () => onDaySelected(summary.first),
              onShowAll: onShowDayList == null
                  ? null
                  : () => showDayList(
                      entry.title,
                      [?entry.subtitle, rangeLabel].join(' · '),
                      () => _fastingDayEntries(summary, l10n, today),
                    ),
              colorPalette: colorPalette,
            ),
          ),
        AgendaEventSummaryRow(
          :final summary,
          :final entry,
          :final rangeLabel,
        ) =>
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AgendaCard(
              entry: entry,
              // The card ranks a whole category; no single event's priority
              // could speak for it.
              priorityBadge: null,
              secondaryLine: rangeLabel,
              onTap: () => onDaySelected(summary.first),
              onShowAll: onShowDayList == null
                  ? null
                  : () => showDayList(
                      entry.title,
                      [?entry.subtitle, rangeLabel].join(' · '),
                      () => _eventDayEntries(summary, l10n, today, onEditEvent),
                    ),
              colorPalette: colorPalette,
            ),
          ),
        AgendaHolidaySummaryRow(:final days, :final entry, :final rangeLabel) =>
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AgendaCard(
              entry: entry,
              priorityBadge: null,
              secondaryLine: rangeLabel,
              onTap: () => onDaySelected(days.first),
              onShowAll: onShowDayList == null
                  ? null
                  : () => showDayList(
                      entry.title,
                      [?entry.subtitle, rangeLabel].join(' · '),
                      () => _holidayDayEntries(days, l10n, today),
                    ),
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

/// One category's events across the window, standing above the list it
/// summarizes.
///
/// Like its holiday and fasting siblings, deliberately **not** an
/// [AgendaEntryRow]: it belongs to no day and must not be counted among the
/// entries.
class AgendaEventSummaryRow extends AgendaRow {
  final EventCategorySummary summary;
  final DaySummaryEntry entry;
  final String rangeLabel;

  const AgendaEventSummaryRow({
    required this.summary,
    required this.entry,
    required this.rangeLabel,
  });
}

/// Every public holiday in the window, standing above the list it summarizes.
///
/// Like its fasting twin, deliberately **not** an [AgendaEntryRow]: it belongs
/// to no day and must not be counted among the entries.
class AgendaHolidaySummaryRow extends AgendaRow {
  /// The holidays this card stands for, ascending — the exact list its
  /// drill-down shows, so the count on the card cannot outrun it.
  final List<DateTime> days;

  final DaySummaryEntry entry;
  final String rangeLabel;

  const AgendaHolidaySummaryRow({
    required this.days,
    required this.entry,
    required this.rangeLabel,
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
  final String rangeLabel;

  const AgendaFastingSummaryRow({
    required this.summary,
    required this.entry,
    required this.rangeLabel,
  });
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

  /// Opens the drill-down behind a summary card. Only the summary cards set
  /// it: an ordinary row already *is* the thing, with nothing to expand into.
  final VoidCallback? onShowAll;

  final MarkdownColorPalette colorPalette;

  /// Dims the whole card. Only reached in faded mode — hidden mode drops the
  /// row while the list is built.
  final bool missed;

  /// The date range a summary card stands for, forced onto its own line so a
  /// long span can never be the fragment a two-line wrap slices in half.
  /// Null for every row that is not a summary card.
  final String? secondaryLine;

  const _AgendaCard({
    required this.entry,
    required this.priorityBadge,
    required this.onTap,
    required this.colorPalette,
    this.collapsedBadge,
    this.onEdit,
    this.onOpenNote,
    this.onShowAll,
    this.missed = false,
    this.secondaryLine,
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
    final range = secondaryLine;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: missed ? CalendarColors.missedEventAlpha : 1.0,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: Container(color: entry.color),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: entry.color.withValues(alpha: 0.16),
                  foregroundColor: entry.color,
                  child: Icon(entry.icon),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(entry.title, overflow: TextOverflow.ellipsis),
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
                subtitle:
                    (subtitle.isEmpty && range == null && description == null)
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              maxLines: range == null ? null : 1,
                              overflow: range == null
                                  ? null
                                  : TextOverflow.ellipsis,
                            ),
                          if (range != null)
                            Text(
                              range,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
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
                isThreeLine: description != null || range != null,
                // A per-day holiday or fasting row carries no event and no
                // drill-down, so it gets no trailing strip at all rather
                // than an empty one.
                trailing:
                    onOpenNote == null && onEdit == null && onShowAll == null
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
                          if (onShowAll != null)
                            IconButton(
                              tooltip: l10n.upcomingShowAllDays,
                              icon: const Icon(Icons.list_rounded),
                              onPressed: onShowAll,
                            ),
                        ],
                      ),
                onTap: onTap,
              ),
            ),
          ],
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
