import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/day_summary_entry.dart';

/// Renders the calendar's bottom panel: a header naming the selected day
/// followed by a list of [DaySummaryEntry] cards (events, weekend, public
/// holiday, etc.). Shows an empty-state when the resolver returns no entries.
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

  const DaySummaryPanel({
    super.key,
    required this.day,
    required this.entries,
    this.onEventTap,
    this.onOpenNote,
    this.onSuppressHoliday,
  });

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
                        padding: const EdgeInsets.symmetric(vertical: 16),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final event = entry.event;
              final hasLinkedNote = event?.noteId != null;
              final isHoliday = entry.key == 'holiday';
              return Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                // IntrinsicHeight bounds the Row to its tallest child's
                // height before `stretch` applies — without it, the Card
                // (inside a ListView) hands the Row unbounded height and
                // the accent-stripe Container tries to stretch to infinity.
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Accent stripe echoing the day-cell marker color, so
                      // list entries and grid markers read as one system.
                      Container(width: 4, color: entry.color),
                      Expanded(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: entry.color.withValues(
                              alpha: 0.16,
                            ),
                            foregroundColor: entry.color,
                            child: Icon(entry.icon),
                          ),
                          title: Text(entry.title),
                          subtitle: entry.subtitle == null
                              ? null
                              : Text(entry.subtitle!),
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
                                            onPressed: () => onOpenNote!(event),
                                          ),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                          ),
                                        ],
                                      )
                                    : const Icon(Icons.chevron_right_rounded))
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
