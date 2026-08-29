import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import 'category_picker_sheet.dart';

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

  /// Hides everything the sheet offers. The union keeps any archived category
  /// already sitting in the denylist denied — this filter reaches events of
  /// hidden categories too, and "hide all" must not quietly un-hide one.
  void _clearAll() {
    setState(() {
      _hidden = {..._hidden, for (final c in CalendarCategories.visible) c.id};
    });
  }

  /// Opens the multi-select picker over the categories currently shown.
  ///
  /// The sheet is semantics-free — a set in, a set out — and this side is a
  /// **denylist**, so the caller inverts: what comes back is what should be
  /// visible, and everything else is hidden. `pickMulti` deliberately does
  /// not collapse an empty result to `null`, because selecting nothing here
  /// means "hide every category", which is a real state.
  Future<void> _pickCategories(List<CalendarCategory> categories) async {
    final picked = await CategoryPickerSheet.pickMulti(
      context,
      selected: {
        for (final c in categories)
          if (!_hidden.contains(c.id)) c.id,
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _hidden = {
        for (final c in categories)
          if (!picked.contains(c.id)) c.id,
      };
    });
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
    // Hidden categories leave every choosing surface, but a denylist already
    // holding an archived id must still show it or the user cannot un-hide
    // what they can no longer see.
    final categories = CalendarCategories.visiblePlus(_hidden);
    final shown = [
      for (final c in categories)
        if (!_hidden.contains(c.id)) c,
    ];
    // `useSafeArea: true` on the modal route avoids the status bar but has
    // proven unreliable against the bottom gesture/nav bar on real devices —
    // same fix as `EventEditorSheet` / `CategoryEditorSheet`: pad the whole
    // sheet by the larger of the keyboard inset and the system's bottom
    // inset so the fixed Cancel/Apply row is never obscured.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomClearance),
      child: Column(
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
                // Short sets are genuinely better as chips — one tap, no
                // navigation. Past the threshold the wall of chips buries the
                // view-range section above it, so it collapses to one row plus
                // a sub-sheet. Select all / Clear all stay in the header
                // either way, so the common "show everything again" reset
                // never needs the sub-sheet.
                if (categories.length > AppConstants.listSearchThreshold)
                  CategoryFilterTile(
                    selected: shown,
                    selectsAll: shown.length == categories.length,
                    onTap: () => _pickCategories(categories),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in categories)
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
                  child: FilledButton(
                    onPressed: _apply,
                    child: Text(l10n.apply),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
