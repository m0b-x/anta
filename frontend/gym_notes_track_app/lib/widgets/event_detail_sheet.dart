import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/calendar_categories.dart';
import '../constants/event_priorities.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/recurrence_rule.dart';
import '../services/event_time_formatter.dart';
import '../services/recurrence_formatter.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/money_display_config.dart';
import 'simple_markdown_preview.dart';

/// What the user chose to do from the detail sheet.
enum EventDetailAction { edit, openNote }

/// Read-only view of a single [CalendarEvent].
///
/// Tapping a day-panel row lands here rather than straight in the edit form:
/// with descriptions being real markdown content, the first thing a tap should
/// do is *show* the event. Editing stays one button away.
///
/// The description renders through the same builder as the note preview, with
/// the money ledger off — a balance is a per-note concept, so `$` rows in an
/// event description stay literal text.
class EventDetailSheet extends StatefulWidget {
  /// How far ahead the "next occurrences" list scans, in days. Matches the
  /// agenda's clamp so the two never disagree about what is upcoming.
  static const int _scanDays = 366;

  /// How many upcoming dates to list.
  static const int _maxOccurrences = 5;

  final CalendarEvent event;
  final MarkdownColorPalette colorPalette;

  const EventDetailSheet({
    super.key,
    required this.event,
    this.colorPalette = MarkdownColorPalette.presets,
  });

  static Future<EventDetailAction?> show(
    BuildContext context, {
    required CalendarEvent event,
    MarkdownColorPalette colorPalette = MarkdownColorPalette.presets,
  }) {
    return showModalBottomSheet<EventDetailAction>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.8,
        child: EventDetailSheet(event: event, colorPalette: colorPalette),
      ),
    );
  }

  @override
  State<EventDetailSheet> createState() => _EventDetailSheetState();
}

class _EventDetailSheetState extends State<EventDetailSheet> {
  /// Next days the event fires on, starting today. Resolved **once**: the
  /// scan walks up to 366 days and the sheet body is a `ListView`, so doing
  /// it in `build` would re-run it on every scroll-driven rebuild.
  late final List<DateTime> _upcoming = _computeUpcoming();

  List<DateTime> _computeUpcoming() {
    final event = widget.event;
    // A one-time or explicit-date event has nothing to project.
    if (event.rule is OneTimeRecurrence) return const [];
    final today = DateTime.now();
    final start = DateTime.utc(today.year, today.month, today.day);
    final days = <DateTime>[];
    for (
      var i = 0;
      i < EventDetailSheet._scanDays &&
          days.length < EventDetailSheet._maxOccurrences;
      i++
    ) {
      final day = start.add(Duration(days: i));
      if (event.occursOn(day)) days.add(day);
    }
    return days;
  }

  /// "Sat, May 10" — with the count label appended ("Sat, May 10 · 30
  /// years", "Mon, Aug 10 · Week 3") when the event counts its occurrences,
  /// so a birthday's chips read as the coming ages and a program's as its
  /// coming weeks.
  String _occurrenceChipLabel(DateTime day, String localeName) {
    final date = DateFormat.MMMEd(localeName).format(day);
    final count = RecurrenceFormatter.countLabel(
      widget.event,
      day,
      AppLocalizations.of(context)!,
    );
    return count == null ? date : '$date · $count';
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final colorPalette = widget.colorPalette;
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localeName = l10n.localeName;
    final category = CalendarCategories.resolve(event.categoryId);
    final accent = (event.colorValue != null && event.tintIcon)
        ? Color(event.colorValue!)
        : category.color;
    final description = event.description?.trim();
    final time = event.time;
    final isRecurring = event.rule is! OneTimeRecurrence;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.close,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  l10n.eventDetailsTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(EventDetailAction.edit),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: Text(l10n.edit),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: accent.withValues(alpha: 0.18),
                    foregroundColor: accent,
                    child: Icon(CalendarCategories.iconFor(event)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          CalendarCategories.labelOf(category, l10n),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InfoRow(
                icon: Icons.event_rounded,
                text: DateFormat.yMMMMEEEEd(localeName).format(event.startDate),
              ),
              _InfoRow(
                icon: Icons.schedule_rounded,
                text: time == null
                    ? l10n.eventAllDay
                    : EventTimeFormatter.formatRange(time, l10n),
              ),
              if (isRecurring)
                _InfoRow(
                  icon: Icons.repeat_rounded,
                  text: RecurrenceFormatter.format(
                    event.rule,
                    l10n,
                    localeName,
                    retroactive: event.retroactive,
                  ),
                ),
              if (isRecurring && event.endDate != null)
                _InfoRow(
                  icon: Icons.event_busy_rounded,
                  text: DateFormat.yMMMMEEEEd(
                    localeName,
                  ).format(event.endDate!),
                ),
              if (event.priority != kDefaultEventPriority)
                _InfoRow(
                  icon: EventPriorities.iconFor(event.priority),
                  text: EventPriorities.labelOf(event.priority, l10n),
                ),
              if (event.noteId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(EventDetailAction.openNote),
                    icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
                    label: Text(l10n.eventOpenLinkedNote),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                l10n.eventDescription,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              if (description == null || description.isEmpty)
                Text(
                  l10n.eventDetailsNoDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SimpleMarkdownPreview(
                    data: description,
                    padding: const EdgeInsets.all(12),
                    colorPalette: colorPalette,
                    moneyConfig: MoneyDisplayConfig.disabled,
                  ),
                ),
              if (isRecurring) ...[
                const SizedBox(height: 20),
                Text(
                  l10n.eventDetailsNextOccurrences,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                if (_upcoming.isEmpty)
                  Text(
                    l10n.eventDetailsNoOccurrences,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final day in _upcoming)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(_occurrenceChipLabel(day, localeName)),
                        ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
