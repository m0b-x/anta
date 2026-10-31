import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/calendar_report.dart';
import '../utils/report_labels.dart';
import 'form_rows.dart';
import 'report_group_stack.dart';

/// What the "n more categories" sheet was closed with; null when it was
/// dismissed.
sealed class ReportSheetResult extends Equatable {
  const ReportSheetResult();
}

/// A row picked: the page opens the detail sheet on [eventId] at [day] — a
/// dated row's own day, a routine aggregate's latest.
final class ReportSheetPick extends ReportSheetResult {
  const ReportSheetPick(this.eventId, this.day);

  final String eventId;
  final DateTime day;

  @override
  List<Object?> get props => [eventId, day];
}

/// A group's Show as list: the page hands the overview the folded span and
/// [categoryId].
final class ReportSheetShowList extends ReportSheetResult {
  const ReportSheetShowList(this.categoryId);

  final String categoryId;

  @override
  List<Object?> get props => [categoryId];
}

/// The report's Categories past the card's `ReportMetrics.maxCategoryRows`
/// (V), drawn as the card draws its groups — the same [ReportGroupStack],
/// the page's folds — in a filler: the form sheet's fixed box, route drag,
/// no `PopScope`, so back and the scrim dismiss it whatever is folded, and
/// a group opened or closed never changes the sheet's height under the
/// finger.
///
/// It writes nothing: a row or a Show as list closes the sheet with what
/// was picked, and the page opens it, so a trip never runs under a sheet.
/// No presence buttons — the Categories card has none.
class ReportMoreCategoriesSheet extends StatefulWidget {
  const ReportMoreCategoriesSheet({
    super.key,
    required this.groups,
    required this.events,
    required this.labels,
    required this.today,
    required this.spansMonths,
    required this.use24Hour,
    this.largest,
    this.folds,
  });

  final List<ReportCategoryGroup> groups;

  /// The report's events by id, which every row's words are read from.
  final Map<String, CalendarEvent> events;
  final ReportLabels labels;

  /// Date-only UTC today, as the page reads it.
  final DateTime today;

  /// Whether the report's span crosses a month: a row's day names it (U).
  final bool spansMonths;
  final bool use24Hour;

  /// The card's largest group's count, which the meters are a share of;
  /// null reads the largest of [groups].
  final int? largest;

  /// The page's fold state, so a group closed here is still closed when the
  /// sheet opens again in the same visit (X); the sheet's groups never share
  /// an id with the card's. Null keeps folds of the sheet's own.
  final ReportGroupFolds? folds;

  /// Resolves to what the viewer picked, or null when dismissed.
  static Future<ReportSheetResult?> show(
    BuildContext context, {
    required List<ReportCategoryGroup> groups,
    required Map<String, CalendarEvent> events,
    required ReportLabels labels,
    required DateTime today,
    required bool spansMonths,
    required bool use24Hour,
    int? largest,
    ReportGroupFolds? folds,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<ReportSheetResult>(
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
      builder: (_) => FractionallySizedBox(
        heightFactor: FormMetrics.sheetHeightFactor,
        child: ReportMoreCategoriesSheet(
          groups: groups,
          events: events,
          labels: labels,
          today: today,
          spansMonths: spansMonths,
          use24Hour: use24Hour,
          largest: largest,
          folds: folds,
        ),
      ),
    );
  }

  @override
  State<ReportMoreCategoriesSheet> createState() =>
      _ReportMoreCategoriesSheetState();
}

class _ReportMoreCategoriesSheetState extends State<ReportMoreCategoriesSheet> {
  final ScrollController _scroll = ScrollController();
  late final ReportGroupFolds _folds = widget.folds ?? ReportGroupFolds();

  /// How many times a fold has armed the slack; nothing else shrinks the
  /// list — no marks here, and the groups never refold under the sheet. A
  /// notifier, so a fold rebuilds the slack and not the groups.
  final ValueNotifier<int> _slackArms = ValueNotifier(0);

  /// Whether the sheet has been closed: a second tap in the same frame —
  /// two rows, or a row and ✕ — would pop the page under the sheet.
  bool _done = false;

  @override
  void dispose() {
    _scroll.dispose();
    _slackArms.dispose();
    super.dispose();
  }

  void _pick(ReportSheetResult? result) {
    if (_done) return;
    _done = true;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        // A filler with no draft to keep: ✕ closes, and the trailing slot
        // stays empty. No hairline (the filler's rule).
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.close,
          onLeading: () => _pick(null),
          leadingIdentifier: SemanticsIds.reportMoreClose,
          title: l10n.reportMoreCategoriesTitle,
          trailing: const SizedBox.shrink(),
          trailingInset: FormMetrics.headerActionInset,
        ),
        Expanded(
          child: Semantics(
            container: true,
            identifier: SemanticsIds.reportMoreList,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    RowMetrics.groupInset,
                    FormMetrics.bodyTop,
                    RowMetrics.groupInset,
                    FormMetrics.bodyBottom + clearance,
                  ),
                  sliver: ReportGroupStack(
                    scroll: _scroll,
                    folds: _folds,
                    card: ReportCard.categories,
                    groups: widget.groups,
                    events: widget.events,
                    labels: widget.labels,
                    largest: widget.largest,
                    onDatedTap: (row) =>
                        _pick(ReportSheetPick(row.eventId, row.day)),
                    onRoutineTap: (row) =>
                        _pick(ReportSheetPick(row.eventId, row.latestDay)),
                    onShowAsList: (group) =>
                        _pick(ReportSheetShowList(group.categoryId)),
                    today: widget.today,
                    spansMonths: widget.spansMonths,
                    use24Hour: widget.use24Hour,
                    onShrink: () => _slackArms.value++,
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: _slackArms,
                  builder: (_, arms, _) =>
                      EndSlackSliver(arms: arms, clearance: clearance),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
