import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/event_priorities.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/day_summary_entry.dart';
import '../utils/markdown_color_syntax.dart';
import 'markdown_inline_text.dart';
import '../services/day_summary_resolver.dart';
import '../utils/event_agenda.dart';

/// Grouped agenda list: a day header followed by one card per occurrence.
///
/// Rows are rendered from [EventSummaryProvider] entries rather than from the
/// events directly, so the agenda inherits the day summary panel's icon,
/// tint and subtitle resolution and the two surfaces cannot drift apart.
///
/// Stateful only to memoize the flattened row list: the inputs change by
/// identity (the agenda view rebuilds its lists on every filter change), so
/// unrelated rebuilds — keyboard animation, theme — reuse the cached rows
/// instead of re-deriving O(occurrences) entries.
class AgendaListView extends StatefulWidget {
  /// Occurrences in display order, as produced by [EventAgenda].
  final List<EventOccurrence> occurrences;

  /// Public-holiday days to interleave, ascending. Empty when the user has
  /// not opted in. A day listed here appears even with no events on it.
  final List<DateTime> holidayDays;

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

  /// Whether row subtitles mention the repeat pattern; forwarded to
  /// [EventSummaryProvider] so agenda and day-panel rows always agree.
  final bool showRecurrenceLabels;

  /// Bumped when a per-occurrence description changes. Part of the row-memo
  /// key below: the rows embed resolved description text, but editing one
  /// day's text leaves the occurrence list identical, so nothing else here
  /// would ever notice.
  final int occurrenceRevision;

  const AgendaListView({
    super.key,
    required this.occurrences,
    this.holidayDays = const [],
    required this.onDaySelected,
    required this.onEditEvent,
    required this.onOpenNote,
    required this.emptyTitle,
    required this.emptyHint,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
    this.colorPalette = MarkdownColorPalette.presets,
    this.showRecurrenceLabels = true,
    this.occurrenceRevision = 0,
  });

  /// Qualitative priority word appended to a row subtitle. The neutral
  /// default is omitted so only events the user deliberately ranked carry
  /// the extra word.
  static String? priorityBadge(AppLocalizations l10n, int priority) {
    if (priority == kDefaultEventPriority) return null;
    return EventPriorities.labelOf(priority, l10n);
  }

  static String dayHeaderLabel(AppLocalizations l10n, DateTime day) {
    final today = EventAgenda.dateOnly(DateTime.now());
    if (day == today) return l10n.upcomingToday;
    if (day == today.add(const Duration(days: 1))) return l10n.upcomingTomorrow;
    return DateFormat.MMMMEEEEd(l10n.localeName).format(day);
  }

  @override
  State<AgendaListView> createState() => _AgendaListViewState();
}

class _AgendaListViewState extends State<AgendaListView> {
  /// Cached flattened rows plus the inputs they were derived from. The
  /// entries embed localized strings, so the locale is part of the key; the
  /// Today/Tomorrow header labels are NOT — they are resolved in the item
  /// builder, so a panel left open across midnight relabels on its next
  /// rebuild without invalidating this cache.
  List<_AgendaRow> _rows = const [];
  List<EventOccurrence>? _rowsForOccurrences;
  List<DateTime>? _rowsForHolidays;
  String? _rowsForLocale;
  bool? _rowsForShowRecurrence;
  int? _rowsForOccurrenceRevision;

  List<_AgendaRow> _rowsFor(AppLocalizations l10n) {
    if (identical(_rowsForOccurrences, widget.occurrences) &&
        identical(_rowsForHolidays, widget.holidayDays) &&
        _rowsForLocale == l10n.localeName &&
        _rowsForShowRecurrence == widget.showRecurrenceLabels &&
        _rowsForOccurrenceRevision == widget.occurrenceRevision) {
      return _rows;
    }
    _rowsForOccurrences = widget.occurrences;
    _rowsForHolidays = widget.holidayDays;
    _rowsForLocale = l10n.localeName;
    _rowsForShowRecurrence = widget.showRecurrenceLabels;
    _rowsForOccurrenceRevision = widget.occurrenceRevision;
    return _rows = _buildRows(l10n);
  }

  /// Flattens the occurrence list into alternating day headers and entry
  /// rows so a single `ListView.builder` can render the grouped agenda.
  ///
  /// Holiday days are merged into the same ascending walk, so a day that is
  /// only a holiday still gets a header and a row. Within a day, events come
  /// first and the holiday last — matching the day summary panel, where the
  /// holiday entry's higher `priority` value sinks it below the events.
  List<_AgendaRow> _buildRows(AppLocalizations l10n) {
    final occurrences = widget.occurrences;
    final holidayDays = widget.holidayDays;
    final eventProvider = EventSummaryProvider(
      l10n,
      showRecurrence: widget.showRecurrenceLabels,
    );
    final holidayProvider = PublicHolidaySummaryProvider(l10n);
    final rows = <_AgendaRow>[];
    var index = 0;
    var holidayIndex = 0;

    while (index < occurrences.length || holidayIndex < holidayDays.length) {
      final nextEventDay = index < occurrences.length
          ? occurrences[index].day
          : null;
      final nextHolidayDay = holidayIndex < holidayDays.length
          ? holidayDays[holidayIndex]
          : null;
      final day = nextEventDay == null
          ? nextHolidayDay!
          : (nextHolidayDay == null || nextEventDay.isBefore(nextHolidayDay)
                ? nextEventDay
                : nextHolidayDay);

      final dayEvents = <CalendarEvent>[];
      while (index < occurrences.length && occurrences[index].day == day) {
        dayEvents.add(occurrences[index].event);
        index++;
      }
      final isHoliday = nextHolidayDay == day;
      if (isHoliday) holidayIndex++;

      final entries = <DaySummaryEntry>[
        ...eventProvider.summaryFor(day, dayEvents),
        if (isHoliday) ...holidayProvider.summaryFor(day, dayEvents),
      ];
      rows.add(_AgendaHeaderRow(day: day, count: entries.length));
      for (final entry in entries) {
        rows.add(_AgendaEntryRow(day: day, entry: entry));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rows = _rowsFor(l10n);

    if (rows.isEmpty) {
      return AgendaEmptyState(title: widget.emptyTitle, hint: widget.emptyHint);
    }

    return ListView.builder(
      padding: widget.padding,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return switch (row) {
          _AgendaHeaderRow(:final day, :final count) => Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 16, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    AgendaListView.dayHeaderLabel(l10n, day),
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
          _AgendaEntryRow(:final day, :final entry) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AgendaCard(
              entry: entry,
              priorityBadge: AgendaListView.priorityBadge(
                l10n,
                entry.event?.priority ?? kDefaultEventPriority,
              ),
              onTap: () => widget.onDaySelected(day),
              colorPalette: widget.colorPalette,
              onEdit: entry.event == null
                  ? null
                  : () => widget.onEditEvent(entry.event!, day),
              onOpenNote: entry.event?.noteId == null
                  ? null
                  : () => widget.onOpenNote(entry.event!),
            ),
          ),
        };
      },
    );
  }
}

/// A row in the flattened agenda: either a day header or an event card.
sealed class _AgendaRow {
  const _AgendaRow();
}

class _AgendaHeaderRow extends _AgendaRow {
  final DateTime day;
  final int count;

  const _AgendaHeaderRow({required this.day, required this.count});
}

class _AgendaEntryRow extends _AgendaRow {
  final DateTime day;
  final DaySummaryEntry entry;

  const _AgendaEntryRow({required this.day, required this.entry});
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

  const _AgendaCard({
    required this.entry,
    required this.priorityBadge,
    required this.onTap,
    required this.colorPalette,
    this.onEdit,
    this.onOpenNote,
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
