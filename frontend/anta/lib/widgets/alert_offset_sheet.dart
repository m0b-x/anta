import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../utils/alert_offset.dart';
import 'form_rows.dart';

/// The Custom sub-sheet of an alert's When: a number in a unit, stepped one
/// at a time — ✕ · Custom · Done.
///
/// A draft, like every sub-sheet. Done returns the number the alert stores —
/// minutes before the start for a timed event, whole days before for an
/// all-day one — and ✕, drag, back and the barrier return `null`, so opening
/// it writes nothing: an alert "at start" stays at start until the user
/// confirms something else. The counting rules are [AlertOffset]'s and the
/// wording is the caller's; the sheet only shows what the two say.
class AlertOffsetSheet extends StatefulWidget {
  /// What the alert stores today, in the event's own unit. A value the
  /// stepper cannot count — "at start", 90 minutes, 36 hours — opens on the
  /// nearest one it can ([AlertOffset.seed]).
  final int initial;

  /// Whether the event is all-day, which leaves days as the only unit.
  final bool allDay;

  /// How a stored offset reads, in the caller's own words: the line under
  /// the stepper. The alert sheet hands over the function its When row reads
  /// its value from, so what stands here before Done is what that row says
  /// after it.
  final String Function(int stored) readBack;

  const AlertOffsetSheet({
    super.key,
    required this.initial,
    required this.allDay,
    required this.readBack,
  });

  static Future<int?> show(
    BuildContext context, {
    required int initial,
    required bool allDay,
    required String Function(int stored) readBack,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<int>(
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
        child: AlertOffsetSheet(
          initial: initial,
          allDay: allDay,
          readBack: readBack,
        ),
      ),
    );
  }

  @override
  State<AlertOffsetSheet> createState() => _AlertOffsetSheetState();
}

class _AlertOffsetSheetState extends State<AlertOffsetSheet> {
  late AlertOffset _offset = AlertOffset.seed(
    widget.initial,
    allDay: widget.allDay,
  );

  final FormHeaderHairline _hairline = FormHeaderHairline();

  @override
  void dispose() {
    _hairline.dispose();
    super.dispose();
  }

  /// The units the sheet counts in: days alone for an all-day event.
  List<AlertOffsetUnit> get _units =>
      widget.allDay ? const [AlertOffsetUnit.days] : AlertOffsetUnit.values;

  /// Every offset the stepper can stand on, unit by unit from its floor to
  /// its ceiling. Walked by [AlertOffset]'s own steps, so the bounds stay
  /// that class's to say.
  List<AlertOffset> _everyOffset() {
    final all = <AlertOffset>[];
    for (final unit in _units) {
      var offset = _offset.withUnit(unit);
      while (offset.canDecrement) {
        offset = offset.decremented;
      }
      all.add(offset);
      while (offset.canIncrement) {
        offset = offset.incremented;
        all.add(offset);
      }
    }
    return all;
  }

  static String _unitLabel(AppLocalizations l10n, AlertOffsetUnit unit) {
    return switch (unit) {
      AlertOffsetUnit.minutes => l10n.eventAlertUnitMinutes,
      AlertOffsetUnit.hours => l10n.eventAlertUnitHours,
      AlertOffsetUnit.days => l10n.eventAlertUnitDays,
    };
  }

  static String _unitIdentifier(AlertOffsetUnit unit) {
    return switch (unit) {
      AlertOffsetUnit.minutes => SemanticsIds.alertCustomUnitMinutes,
      AlertOffsetUnit.hours => SemanticsIds.alertCustomUnitHours,
      AlertOffsetUnit.days => SemanticsIds.alertCustomUnitDays,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view, never the whole body — the rule every calendar sheet
    // follows (`sheet_bottom_clearance_test.dart`).
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
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.alertCustomClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.eventAlertCustom,
          scrolled: _hairline.scrolled,
          trailingInset: FormMetrics.headerActionInset,
          trailing: FormHeaderTextButton(
            label: l10n.eventDescriptionDone,
            identifier: SemanticsIds.alertCustomDone,
            onPressed: () => Navigator.of(context).pop(_offset.stored),
          ),
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
              // The slot holds the whole body here, not a caption alone.
              // This sheet is as tall as its content, and a unit's name and
              // the read-back can each take another line at a large text
              // scale: a body that grew with a step would move the stepper
              // from under the finger on it. So the body's tallest state is
              // laid out unseen under it.
              child: FormCaptionSlot(
                candidates: [_buildSizer(l10n)],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildGroup(l10n, _offset),
                    _buildReadBack(_offset),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// As tall as the body can get, which no single state may be: every unit's
  /// group laid over one another, and under them every line the read-back
  /// can say. The wording is the caller's, so its tallest line is not one
  /// this sheet can name — each is laid out, and the tallest wins.
  Widget _buildSizer(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            for (final unit in _units)
              _buildGroup(l10n, _offset.withUnit(unit)),
          ],
        ),
        Stack(
          children: [
            for (final offset in _everyOffset()) _buildReadBack(offset),
          ],
        ),
      ],
    );
  }

  Widget _buildGroup(AppLocalizations l10n, AlertOffset offset) {
    return FormRowGroup(
      trailingGap: false,
      children: [
        if (!widget.allDay)
          FormChipRow(
            indented: false,
            chips: [
              for (final unit in AlertOffsetUnit.values)
                FormChip(
                  label: _unitLabel(l10n, unit),
                  selected: offset.unit == unit,
                  identifier: _unitIdentifier(unit),
                  onTap: () => setState(() => _offset = _offset.withUnit(unit)),
                ),
            ],
          ),
        FormStepperRow(
          label: _unitLabel(l10n, offset.unit),
          value: '${offset.value}',
          widestValue: '${offset.unit.max}',
          decrementTooltip: l10n.eventAlertOffsetDecrement,
          incrementTooltip: l10n.eventAlertOffsetIncrement,
          decrementIdentifier: SemanticsIds.alertCustomLess,
          incrementIdentifier: SemanticsIds.alertCustomMore,
          onDecrement: offset.canDecrement
              ? () => setState(() => _offset = _offset.decremented)
              : null,
          onIncrement: offset.canIncrement
              ? () => setState(() => _offset = _offset.incremented)
              : null,
        ),
      ],
    );
  }

  Widget _buildReadBack(AlertOffset offset) {
    return FormCaption(
      text: widget.readBack(offset.stored),
      padding: FormMetrics.groupCaptionPadding,
    );
  }
}
