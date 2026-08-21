import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../l10n/app_localizations.dart';

/// Bottom sheet that picks the upcoming agenda's category **allowlist**.
///
/// An empty result means "all categories" (the filter off), mirroring the
/// priority filter. Returns the chosen id set on Apply, or `null` when
/// dismissed without applying. Reads [CalendarCategories.all] on each build so
/// a database switch (which clears the facade) cannot leave it stale.
class AgendaCategoryFilterSheet extends StatefulWidget {
  final Set<String> initialSelected;

  const AgendaCategoryFilterSheet({super.key, required this.initialSelected});

  static Future<Set<String>?> show(
    BuildContext context, {
    required Set<String> selectedIds,
  }) {
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => AgendaCategoryFilterSheet(initialSelected: selectedIds),
    );
  }

  @override
  State<AgendaCategoryFilterSheet> createState() =>
      _AgendaCategoryFilterSheetState();
}

class _AgendaCategoryFilterSheetState extends State<AgendaCategoryFilterSheet> {
  late final Set<String> _selected = {...widget.initialSelected};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.calendarCategories,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              // Empty allowlist already means "all", so the reset only appears
              // when there is a selection to clear.
              if (_selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: Text(l10n.upcomingClearCategories),
                ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in CalendarCategories.all)
                  FilterChip(
                    avatar: CircleAvatar(
                      backgroundColor: category.color.withValues(alpha: 0.18),
                      foregroundColor: category.color,
                      child: Icon(
                        CalendarIcons.forKey(category.iconKey) ??
                            Icons.event_rounded,
                        size: 16,
                      ),
                    ),
                    label: Text(CalendarCategories.labelOf(category, l10n)),
                    selected: _selected.contains(category.id),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _selected.add(category.id);
                      } else {
                        _selected.remove(category.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(_selected),
            child: Text(l10n.apply),
          ),
        ),
      ],
    );
  }
}
