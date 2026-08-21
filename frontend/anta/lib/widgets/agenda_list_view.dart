import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/calendar_colors.dart';
import '../constants/event_priorities.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/day_summary_entry.dart';
import '../utils/markdown_color_syntax.dart';
import 'markdown_inline_text.dart';
import '../services/day_summary_resolver.dart';
import '../utils/event_agenda.dart';

/// Flattens an occurrence list into alternating day headers and entry rows so
/// a single `ListView.builder` can render the grouped agenda.
///
/// Holiday days are merged into the same ascending walk, so a day that is
/// only a holiday still gets a header and a row. Within a day, events come
/// first and the holiday last — matching the day summary panel, where the
/// holiday entry's higher `priority` value sinks it below the events.
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
}) {
  final hideMissed = missedDisplay == CalendarMissedDisplay.hidden;
  final eventProvider = EventSummaryProvider(
    l10n,
    showRecurrence: showRecurrenceLabels,
  );
  final holidayProvider = PublicHolidaySummaryProvider(l10n);
  final fastingProvider = FastingSummaryProvider(l10n);
  final rows = <AgendaRow>[];
  var index = 0;
  var holidayIndex = 0;
  var fastingIndex = 0;

  while (index < occurrences.length ||
      holidayIndex < holidayDays.length ||
      fastingIndex < fastingDays.length) {
    final nextEventDay = index < occurrences.length
        ? occurrences[index].day
        : null;
    final nextHolidayDay = holidayIndex < holidayDays.length
        ? holidayDays[holidayIndex]
        : null;
    final nextFastingDay = fastingIndex < fastingDays.length
        ? fastingDays[fastingIndex]
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
    while (index < occurrences.length && occurrences[index].day == day) {
      dayEvents.add(occurrences[index].event);
      index++;
    }
    final isHoliday = nextHolidayDay == day;
    if (isHoliday) holidayIndex++;
    final isFasting = nextFastingDay == day;
    if (isFasting) fastingIndex++;

    final entries = <DaySummaryEntry>[
      for (final entry in eventProvider.summaryFor(day, dayEvents))
        if (!hideMissed || !entry.missed) entry,
      if (isHoliday) ...holidayProvider.summaryFor(day, dayEvents),
      if (isFasting) ...fastingProvider.summaryFor(day, dayEvents),
    ];
    if (entries.isEmpty) continue;
    rows.add(AgendaDayHeaderRow(day: day, count: entries.length));
    for (final entry in entries) {
      rows.add(AgendaEntryRow(day: day, entry: entry));
    }
  }
  return rows;
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
  /// now-shorter list.
  final ScrollController? controller;

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
      return AgendaEmptyState(title: emptyTitle, hint: emptyHint);
    }

    // Computed once here, not per visible header, and handed to
    // `dayHeaderLabel` for its Today/Tomorrow test.
    final today = EventAgenda.dateOnly(DateTime.now());

    return ListView.builder(
      controller: controller,
      padding: padding,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return switch (row) {
          AgendaDayHeaderRow(:final day, :final count) => Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 16, bottom: 8),
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
          AgendaEntryRow(:final day, :final entry) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AgendaCard(
              entry: entry,
              missed: entry.missed,
              priorityBadge: AgendaListView.priorityBadge(
                l10n,
                entry.event?.priority ?? kDefaultEventPriority,
              ),
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
      },
    );
  }
}

/// A row in the flattened agenda: either a day header or an event card.
sealed class AgendaRow {
  const AgendaRow();
}

class AgendaDayHeaderRow extends AgendaRow {
  final DateTime day;
  final int count;

  const AgendaDayHeaderRow({required this.day, required this.count});
}

class AgendaEntryRow extends AgendaRow {
  final DateTime day;
  final DaySummaryEntry entry;

  const AgendaEntryRow({required this.day, required this.entry});
}

/// Event card mirroring the day summary panel's accent-stripe layout so the
/// agenda and the day panel read as one system.
class _AgendaCard extends StatelessWidget {
  final DaySummaryEntry entry;
  final String? priorityBadge;
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
    this.onEdit,
    this.onOpenNote,
    this.missed = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final subtitle = [?entry.subtitle, ?priorityBadge].join(' · ');
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
