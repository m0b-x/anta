import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_spacing.dart';
import '../constants/calendar_colors.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/day_summary_entry.dart';
import '../utils/markdown_color_syntax.dart';
import 'markdown_inline_text.dart';

/// Renders the calendar's bottom panel: a header naming the selected day
/// followed by a list of [DaySummaryEntry] cards (events, weekend, public
/// holiday, etc.). Shows an empty-state when the resolver returns no entries.
///
/// Missed occurrences are dimmed here but **always listed**, even when the
/// user set missed days to hidden: this panel is where they are marked and
/// un-marked, and a row that disappeared the moment it was marked could never
/// be brought back.
class DaySummaryPanel extends StatelessWidget {
  /// The selected day the entries belong to, shown in the panel header.
  final DateTime day;

  final List<DaySummaryEntry> entries;

  /// Called when the user taps an entry that carries a [CalendarEvent].
  /// Non-event entries (weekend, holiday) are non-interactive.
  final ValueChanged<CalendarEvent>? onEventTap;

  /// Called when the user taps the "open linked note" affordance on an
  /// event that has a linked note (`event.noteId != null`).
  final ValueChanged<CalendarEvent>? onOpenNote;

  /// Called when the user taps the "remove holiday" affordance on the
  /// public-holiday entry (`entry.key == 'holiday'`). Only that entry
  /// carries the action — weekend and event entries are unaffected.
  final VoidCallback? onSuppressHoliday;

  /// Called with the new presence for a presence-tracking entry's occurrence.
  /// The panel is deliberately day-less, so the caller — which knows the
  /// selected day — binds it, exactly like [onEventTap].
  final void Function(CalendarEvent event, bool missed)? onToggleMissed;

  /// Palette used to render `{name:text}` runs inside event descriptions, so
  /// a row shows the user's custom colours and not just the presets.
  final MarkdownColorPalette colorPalette;

  final double bottomInset;

  const DaySummaryPanel({
    super.key,
    required this.day,
    required this.entries,
    this.onEventTap,
    this.onOpenNote,
    this.onSuppressHoliday,
    this.onToggleMissed,
    this.colorPalette = MarkdownColorPalette.presets,
    this.bottomInset = 0,
  });

  /// Two-line subtitle: the scheduling line (recurrence · time) followed by
  /// the event's description rendered as markdown and clamped to two lines.
  Widget? _buildSubtitle(BuildContext context, DaySummaryEntry entry) {
    final subtitle = entry.subtitle;
    final description = entry.description;
    if (subtitle == null && description == null) return null;
    if (description == null) return Text(subtitle!);

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (subtitle != null) Text(subtitle),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              DateFormat.MMMMEEEEd(l10n.localeName).format(day),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (entries.isNotEmpty)
            Text(
              l10n.daySummaryEntryCount(entries.length),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );

    if (entries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            // LayoutBuilder + a scrollable keeps this centered when there's
            // room and scrollable instead of overflowing when the panel is
            // squeezed shorter than the content's natural height (e.g. a
            // resized desktop window, or a tall calendar grid in month
            // view).
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          0,
                          16,
                          0,
                          16 + bottomInset,
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
                              l10n.calendarNoEventsForDay,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: ListView.separated(
            // Keyed on the day: selecting another one must build a fresh
            // viewport at offset 0 rather than recycle this day's rows and
            // its scroll position, which left the previous day's cards
            // showing faintly through the overscroll correction.
            key: ValueKey(day),
            // Clears the page's floating add button — see AppSpacing.
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + AppSpacing.fabClearance + bottomInset,
            ),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final event = entry.event;
              final hasLinkedNote = event?.noteId != null;
              final isHoliday = entry.key == 'holiday';
              final canToggleMissed =
                  event != null &&
                  entry.presenceTracked &&
                  onToggleMissed != null;
              // Presence replaces the decorative chevron rather than adding a
              // third widget: the note button already claims one slot, and a
              // third would not fit a phone-width trailing strip.
              final tail = canToggleMissed
                  ? IconButton(
                      tooltip: entry.missed
                          ? l10n.eventMarkPresent
                          : l10n.eventMarkMissed,
                      icon: Icon(
                        entry.missed
                            ? Icons.event_available_rounded
                            : Icons.event_busy_rounded,
                      ),
                      onPressed: () => onToggleMissed!(event, !entry.missed),
                    )
                  : const Icon(Icons.chevron_right_rounded);
              return Card(
                // Entry-keyed so a row — and the opacity layer a missed
                // occurrence puts inside it — is never reused for a
                // different entry.
                key: ValueKey(entry.key),
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                // A Positioned stripe inside a Stack sizes itself off the
                // Stack's own height instead of a sibling's — so the Stack
                // can size-to-content (from the Padding/ListTile) and the
                // stripe still stretches to match, with no IntrinsicHeight
                // pass needed. Mirrors _AgendaCard in agenda_list_view.dart,
                // which renders this same accent-stripe design.
                child: Opacity(
                  opacity: entry.missed
                      ? CalendarColors.missedEventAlpha
                      : 1.0,
                  child: Stack(
                    children: [
                      // Accent stripe echoing the day-cell marker color, so
                      // list entries and grid markers read as one system.
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
                            backgroundColor: entry.color.withValues(
                              alpha: 0.16,
                            ),
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
                              if (entry.description != null) ...[
                                const SizedBox(width: 6),
                                Tooltip(
                                  message: l10n.eventHasDescription,
                                  child: Icon(
                                    Icons.notes_rounded,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: _buildSubtitle(context, entry),
                          // The description adds a second subtitle line; the
                          // tile has to be told, or it clips to one.
                          isThreeLine: entry.description != null,
                          trailing: event != null
                              ? (hasLinkedNote && onOpenNote != null
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: l10n.eventOpenLinkedNote,
                                            icon: const Icon(
                                              Icons.sticky_note_2_outlined,
                                            ),
                                            onPressed: () =>
                                                onOpenNote!(event),
                                          ),
                                          tail,
                                        ],
                                      )
                                    : tail)
                              : (isHoliday && onSuppressHoliday != null
                                    ? IconButton(
                                        tooltip: l10n.removeHoliday,
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                        ),
                                        onPressed: onSuppressHoliday,
                                      )
                                    : null),
                          onTap: event == null || onEventTap == null
                              ? null
                              : () => onEventTap!(event),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
