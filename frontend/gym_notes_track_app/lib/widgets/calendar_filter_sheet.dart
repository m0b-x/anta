import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../l10n/app_localizations.dart';

/// Result returned by [CalendarFilterSheet] when the user applies a change.
class CalendarFilterResult {
  final CalendarFormat format;
  final Set<String> hiddenCategoryIds;

  const CalendarFilterResult({
    required this.format,
    required this.hiddenCategoryIds,
  });
}

/// Bottom-sheet that lets the user pick the calendar view range (month /
/// two weeks / week) and choose which event categories should appear.
class CalendarFilterSheet extends StatefulWidget {
  final CalendarFormat initialFormat;
  final Set<String> initialHiddenIds;

  const CalendarFilterSheet({
    super.key,
    required this.initialFormat,
    required this.initialHiddenIds,
  });

  static Future<CalendarFilterResult?> show(
    BuildContext context, {
    required CalendarFormat format,
    required Set<String> hiddenCategoryIds,
  }) {
    return showModalBottomSheet<CalendarFilterResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.75,
        child: CalendarFilterSheet(
          initialFormat: format,
          initialHiddenIds: hiddenCategoryIds,
        ),
      ),
    );
  }

  @override
  State<CalendarFilterSheet> createState() => _CalendarFilterSheetState();
}

class _CalendarFilterSheetState extends State<CalendarFilterSheet> {
  late CalendarFormat _format;
  late Set<String> _hidden;

  @override
  void initState() {
    super.initState();
    _format = widget.initialFormat;
    _hidden = {...widget.initialHiddenIds};
  }

  String _formatLabel(AppLocalizations l10n, CalendarFormat f) {
    return switch (f) {
      CalendarFormat.month => l10n.calendarFormatMonth,
      CalendarFormat.twoWeeks => l10n.calendarFormatTwoWeeks,
      CalendarFormat.week => l10n.calendarFormatWeek,
    };
  }

  void _toggleCategory(String id, bool visible) {
    setState(() {
      if (visible) {
        _hidden.remove(id);
      } else {
        _hidden.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() => _hidden = <String>{});
  }

  void _clearAll() {
    setState(() => _hidden = {for (final c in CalendarCategories.all) c.id});
  }

  void _apply() {
    Navigator.of(context).pop(
      CalendarFilterResult(
        format: _format,
        hiddenCategoryIds: Set.unmodifiable(_hidden),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final allSelected = _hidden.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            l10n.calendarFiltersTitle,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            children: [
              _SectionLabel(text: l10n.calendarViewRange),
              const SizedBox(height: 8),
              SegmentedButton<CalendarFormat>(
                segments: [
                  for (final f in CalendarFormat.values)
                    ButtonSegment<CalendarFormat>(
                      value: f,
                      label: Text(_formatLabel(l10n, f)),
                    ),
                ],
                selected: {_format},
                showSelectedIcon: false,
                onSelectionChanged: (sel) {
                  setState(() => _format = sel.first);
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _SectionLabel(text: l10n.calendarEventCategories),
                  ),
                  TextButton(
                    onPressed: allSelected ? _clearAll : _selectAll,
                    child: Text(
                      allSelected
                          ? l10n.calendarClearAll
                          : l10n.calendarSelectAll,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in CalendarCategories.all)
                    FilterChip(
                      avatar: CircleAvatar(
                        backgroundColor: c.color.withValues(alpha: 0.18),
                        foregroundColor: c.color,
                        child: Icon(
                          CalendarIcons.forKey(c.iconKey) ??
                              Icons.event_rounded,
                          size: 16,
                        ),
                      ),
                      label: Text(CalendarCategories.labelOf(c, l10n)),
                      selected: !_hidden.contains(c.id),
                      onSelected: (sel) => _toggleCategory(c.id, sel),
                    ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(onPressed: _apply, child: Text(l10n.apply)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
