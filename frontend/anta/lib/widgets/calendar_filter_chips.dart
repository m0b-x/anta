import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/calendar_grid_filters.dart';
import '../utils/calendar_filter_summary.dart';

/// One removable chip per active filter, above the grid.
///
/// This is the answer to "why is my event missing" without opening anything:
/// every narrowing axis is named, and its `x` undoes that one axis while
/// leaving the rest alone. Renders nothing at all when no filter is active, so
/// an unfiltered calendar keeps every pixel it has today.
///
/// Both the label and what the `x` does come from
/// [CalendarFilterSummary.facetsOf] — never a second switch here, or a chip
/// could name an axis differently from the sheet that set it, or clear a
/// different one than it names.
class CalendarFilterChips extends StatelessWidget {
  final CalendarGridFilters filters;

  /// Applies the filter set with one axis removed.
  final ValueChanged<CalendarGridFilters> onChanged;

  /// Opens the full filter sheet — the chip body itself is tappable, so a
  /// chip is both a label and a way back to what set it.
  final VoidCallback onOpenFilters;

  const CalendarFilterChips({
    super.key,
    required this.filters,
    required this.onChanged,
    required this.onOpenFilters,
  });

  /// Height of the row, matching a compact chip plus its padding. Fixed so
  /// the horizontal scroll view has a bounded cross axis.
  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final facets = CalendarFilterSummary.facetsOf(filters, l10n);
    if (facets.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        itemCount: facets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final facet = facets[index];
          return Center(
            child: InputChip(
              avatar: Icon(facet.icon, size: 18),
              label: Text(facet.label),
              visualDensity: VisualDensity.compact,
              showCheckmark: false,
              onPressed: onOpenFilters,
              onDeleted: () => onChanged(facet.without),
              deleteButtonTooltipMessage: l10n.upcomingRemoveFilter,
            ),
          );
        },
      ),
    );
  }
}
