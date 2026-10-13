import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/overview_list_options.dart';
import 'form_rows.dart';

/// The overview list's options behind the bar's tune button: the order, the
/// rows and Missed only — a live-apply sub-sheet of the UI language.
///
/// Every control writes at once through [onChanged], and the page persists
/// what it keeps, so dismissing the sheet by ✕, the barrier or a drag keeps
/// what was set: there is no draft to confirm. Order and Rows shape the list
/// alone, so they stay in place but inert while the page shows another
/// presentation; Missed only narrows month mode's rows too and stays live.
class OverviewOptionsSheet extends StatefulWidget {
  final OverviewListOptions initial;
  final bool listMode;
  final ValueChanged<OverviewListOptions> onChanged;

  const OverviewOptionsSheet({
    super.key,
    required this.initial,
    required this.listMode,
    required this.onChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required OverviewListOptions initial,
    required bool listMode,
    required ValueChanged<OverviewListOptions> onChanged,
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
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * FormMetrics.sheetHeightFactor,
        ),
        child: OverviewOptionsSheet(
          initial: initial,
          listMode: listMode,
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  State<OverviewOptionsSheet> createState() => _OverviewOptionsSheetState();
}

class _OverviewOptionsSheetState extends State<OverviewOptionsSheet> {
  late OverviewListOptions _options;

  @override
  void initState() {
    super.initState();
    _options = widget.initial;
  }

  void _apply(OverviewListOptions next) {
    if (next == _options) return;
    setState(() => _options = next);
    widget.onChanged(next);
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
    final listMode = widget.listMode;
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
          trailingInset: FormMetrics.headerActionInset,
          // Nothing to confirm: every control has already written.
          trailing: const SizedBox.shrink(),
        ),
        Flexible(
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
                  onChanged: (value) =>
                      _apply(_options.copyWith(missedOnly: value)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
