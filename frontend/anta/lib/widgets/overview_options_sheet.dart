import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list_mode.dart';
import '../models/overview_list_options.dart';
import '../utils/calendar_filter_summary.dart';
import 'category_picker_sheet.dart';
import 'form_rows.dart';

/// The overview list's options behind the bar's tune button: the categories,
/// the order, the rows and Missed only — a live-apply sub-sheet of the UI
/// language.
///
/// Every control writes at once through [onChanged] (the categories through
/// [onCategoriesChanged]), and the page persists
/// what it keeps, so dismissing the sheet by ✕, the barrier or a drag keeps
/// what was set: there is no draft to confirm. Order and Rows shape the list
/// alone, so they stay in place but inert while the page shows another
/// presentation; Missed only narrows month mode's rows too and stays live
/// there, inert in Year mode, whose tiles it does not change.
class OverviewOptionsSheet extends StatefulWidget {
  final OverviewListOptions initial;
  final AgendaDayListMode mode;
  final ValueChanged<OverviewListOptions> onChanged;

  /// The page's categories allowlist; empty means every category (D22 · A).
  final Set<String> categoryIds;

  /// Called with a picked allowlist that differs from the one shown, already
  /// collapsed to empty when it covers every offered category.
  final ValueChanged<Set<String>> onCategoriesChanged;

  const OverviewOptionsSheet({
    super.key,
    required this.initial,
    required this.mode,
    required this.onChanged,
    required this.categoryIds,
    required this.onCategoriesChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required OverviewListOptions initial,
    required AgendaDayListMode mode,
    required ValueChanged<OverviewListOptions> onChanged,
    required Set<String> categoryIds,
    required ValueChanged<Set<String>> onCategoriesChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: colorScheme.pageGround,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FormMetrics.sheetRadius),
        ),
      ),
      // The Categories value may take a second line on the picker's answer,
      // which resizes the sheet while the picker's route is still leaving.
      builder: (context) => FormSheetSemanticsRefresh(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.sizeOf(context).height *
                FormMetrics.sheetHeightFactor,
          ),
          child: OverviewOptionsSheet(
            initial: initial,
            mode: mode,
            onChanged: onChanged,
            categoryIds: categoryIds,
            onCategoriesChanged: onCategoriesChanged,
          ),
        ),
      ),
    );
  }

  @override
  State<OverviewOptionsSheet> createState() => _OverviewOptionsSheetState();
}

class _OverviewOptionsSheetState extends State<OverviewOptionsSheet> {
  late OverviewListOptions _options;
  late Set<String> _categoryIds;
  bool _pickerOpen = false;
  final FormHeaderHairline _hairline = FormHeaderHairline();

  @override
  void initState() {
    super.initState();
    _options = widget.initial;
    _categoryIds = widget.categoryIds;
  }

  @override
  void dispose() {
    _hairline.dispose();
    super.dispose();
  }

  void _apply(OverviewListOptions next) {
    if (next == _options) return;
    setState(() => _options = next);
    widget.onChanged(next);
  }

  /// "All" for the empty allowlist, else the chosen categories read back in
  /// catalog order — two names, then "+N more", on the value's two lines.
  String _categoriesValue(AppLocalizations l10n) {
    if (_categoryIds.isEmpty) return l10n.calendarFilterCategoriesAll;
    return CalendarFilterSummary.namesReadBack([
      for (final category in CalendarCategories.visiblePlus(_categoryIds))
        if (_categoryIds.contains(category.id))
          CalendarCategories.labelOf(category, l10n),
    ], l10n);
  }

  /// The multi picker over the allowlist. An empty allowlist means every
  /// category, so it opens with every offered row ticked, and a result that
  /// covers every offered row collapses back to empty rather than freezing
  /// today's catalog into a list that silently excludes categories created
  /// later.
  Future<void> _pickCategories() async {
    if (_pickerOpen) return;
    _pickerOpen = true;
    try {
      final offered = {
        for (final category in CalendarCategories.visiblePlus(_categoryIds))
          category.id,
      };
      final picked = await CategoryPickerSheet.pickMulti(
        context,
        selected: _categoryIds.isEmpty ? offered : _categoryIds,
      );
      if (picked == null || !mounted) return;
      final next = picked.containsAll(offered) ? const <String>{} : picked;
      if (setEquals(next, _categoryIds)) return;
      setState(() => _categoryIds = next);
      widget.onCategoriesChanged(next);
    } finally {
      _pickerOpen = false;
    }
  }

  static String _orderLabel(AppLocalizations l10n, OverviewOrder order) {
    return switch (order) {
      OverviewOrder.oldestFirst => l10n.overviewOrderOldestFirst,
      OverviewOrder.newestFirst => l10n.overviewOrderNewestFirst,
    };
  }

  static String _rowsLabel(AppLocalizations l10n, OverviewRows rows) {
    return switch (rows) {
      OverviewRows.everyOccurrence => l10n.overviewRowsEveryOccurrence,
      OverviewRows.perEvent => l10n.overviewRowsPerEvent,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final listMode = widget.mode == AgendaDayListMode.list;
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view, never the whole body (`sheet_bottom_clearance_test.dart`).
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.close,
          leadingIdentifier: SemanticsIds.overviewOptionsClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.overviewListOptions,
          scrolled: _hairline.scrolled,
          trailingInset: FormMetrics.headerActionInset,
          // Nothing to confirm: every control has already written.
          trailing: const SizedBox.shrink(),
        ),
        Flexible(
          child: _hairline.watch(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                RowMetrics.groupInset,
                FormMetrics.bodyTop,
                RowMetrics.groupInset,
                FormMetrics.bodyBottom + clearance,
              ),
              child: FormRowGroup(
                trailingGap: false,
                children: [
                  FormPickerRow(
                    glyph: Icons.category_rounded,
                    label: l10n.overviewCategories,
                    value: _categoriesValue(l10n),
                    identifier: SemanticsIds.overviewCategories,
                    onTap: _pickCategories,
                  ),
                  FormMenuRow<OverviewOrder>(
                    glyph: Icons.swap_vert_rounded,
                    label: l10n.overviewOrder,
                    value: _orderLabel(l10n, _options.order),
                    selected: _options.order,
                    menuWidth: FormMetrics.menuWidth,
                    identifier: SemanticsIds.overviewOrder,
                    items: [
                      FormMenuItem(
                        value: OverviewOrder.oldestFirst,
                        label: _orderLabel(l10n, OverviewOrder.oldestFirst),
                        identifier: SemanticsIds.overviewOrderOldest,
                      ),
                      FormMenuItem(
                        value: OverviewOrder.newestFirst,
                        label: _orderLabel(l10n, OverviewOrder.newestFirst),
                        identifier: SemanticsIds.overviewOrderNewest,
                      ),
                    ],
                    onSelected: listMode
                        ? (order) => _apply(_options.copyWith(order: order))
                        : null,
                  ),
                  FormMenuRow<OverviewRows>(
                    glyph: Icons.view_list_rounded,
                    label: l10n.overviewRows,
                    value: _rowsLabel(l10n, _options.rows),
                    selected: _options.rows,
                    menuWidth: FormMetrics.menuWidth,
                    identifier: SemanticsIds.overviewRows,
                    items: [
                      FormMenuItem(
                        value: OverviewRows.everyOccurrence,
                        label: _rowsLabel(l10n, OverviewRows.everyOccurrence),
                        identifier: SemanticsIds.overviewRowsEvery,
                      ),
                      FormMenuItem(
                        value: OverviewRows.perEvent,
                        label: _rowsLabel(l10n, OverviewRows.perEvent),
                        identifier: SemanticsIds.overviewRowsPerEvent,
                      ),
                    ],
                    onSelected: listMode
                        ? (rows) => _apply(_options.copyWith(rows: rows))
                        : null,
                  ),
                  FormSwitchRow(
                    glyph: Icons.do_not_disturb_on_outlined,
                    label: l10n.overviewMissedOnly,
                    value: _options.missedOnly,
                    identifier: SemanticsIds.overviewMissedOnly,
                    onChanged: widget.mode == AgendaDayListMode.year
                        ? null
                        : (value) =>
                              _apply(_options.copyWith(missedOnly: value)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
