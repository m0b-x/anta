import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/agenda_day_list_mode.dart';
import 'automation_id.dart';
import 'form_rows.dart';

/// The overview's Year · Month · List chips with the search button at the
/// row's end — the page's primary control (D12 · A), on the page rather than
/// in the title's menu, and the search at the thumb (D21 · A).
///
/// One widget so the overview page and the guide's overview card draw the
/// same row (the owner's rule, D59): a change to it reaches both. The ids
/// come from the caller, because the card and the page each have their own
/// and a flow must never mistake one for the other.
class OverviewModeChips extends StatelessWidget {
  const OverviewModeChips({
    super.key,
    required this.mode,
    required this.onSelected,
    required this.modeIdentifier,
    required this.onSearch,
    required this.searchActive,
    required this.searchIdentifier,
  });

  /// Widest to narrowest, the page's own order: it opens on the tiles.
  static const List<AgendaDayListMode> modes = [
    AgendaDayListMode.year,
    AgendaDayListMode.month,
    AgendaDayListMode.list,
  ];

  final AgendaDayListMode mode;
  final ValueChanged<AgendaDayListMode> onSelected;
  final String Function(AgendaDayListMode mode) modeIdentifier;

  /// Null draws the search button disabled, never hidden: a surface with
  /// nothing to search still shows where the search lives.
  final VoidCallback? onSearch;

  /// Whether a query is live: the button reads selected.
  final bool searchActive;
  final String searchIdentifier;

  static String labelOf(AppLocalizations l10n, AgendaDayListMode mode) {
    return switch (mode) {
      AgendaDayListMode.year => l10n.dayListModeYear,
      AgendaDayListMode.month => l10n.dayListModeMonth,
      AgendaDayListMode.list => l10n.dayListModeList,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: FormChipRow(
            indented: false,
            chips: [
              for (final option in modes)
                FormChip(
                  label: labelOf(l10n, option),
                  selected: mode == option,
                  onTap: () => onSelected(option),
                  identifier: modeIdentifier(option),
                ),
            ],
          ),
        ),
        // The trailing control's box and glyph (`FormTrailingButton`'s
        // sizing, which has no selected state): a row's control, not a
        // bar's, and no taller than the chips' tap target.
        AutomationId(
          identifier: searchIdentifier,
          child: SizedBox.square(
            dimension: FormMetrics.trailingButtonSize,
            child: IconButton(
              tooltip: l10n.search,
              isSelected: searchActive,
              iconSize: FormMetrics.trailingIconSize,
              icon: const Icon(Icons.search_rounded),
              onPressed: onSearch,
            ),
          ),
        ),
      ],
    );
  }
}
