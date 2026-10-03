import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/public_holidays.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../services/public_holiday_service.dart';
import 'form_rows.dart';
import 'overlay_snackbar.dart';

/// Bottom sheet listing every built-in holiday the user has suppressed for
/// a specific date, each with a Restore button beside it — a sub-sheet of
/// the UI language since Tier 3 (`docs/calendar-language-tier-3-roadmap.md`,
/// §3.6). Suppressing (rather than deleting) a built-in row is what makes
/// the removal survive an app restart or backup restore; this sheet is the
/// durable undo path for someone who changes their mind after the
/// snackbar's Undo has expired.
///
/// Applies live: a restore deletes its suppression row at once, and
/// dismissing never discards anything.
class RemovedHolidaysSheet extends StatefulWidget {
  final PublicHolidayService holidayService;

  const RemovedHolidaysSheet({super.key, required this.holidayService});

  static Future<void> show(
    BuildContext context,
    PublicHolidayService holidayService,
  ) {
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
        child: RemovedHolidaysSheet(holidayService: holidayService),
      ),
    );
  }

  @override
  State<RemovedHolidaysSheet> createState() => _RemovedHolidaysSheetState();
}

class _RemovedHolidaysSheetState extends State<RemovedHolidaysSheet> {
  List<SuppressedHoliday>? _items;
  final FormHeaderHairline _hairline = FormHeaderHairline();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hairline.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await widget.holidayService.suppressedHolidays();
    if (!mounted) return;
    setState(() => _items = items);
  }

  /// Deletes the suppression and drops the row. The failure path re-reads
  /// the list rather than trusting the row either way: a delete that threw
  /// may or may not have landed, and the service's own republish never ran.
  Future<void> _restore(SuppressedHoliday item) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await widget.holidayService.restoreSuppressed(item.date, item.holiday);
    } catch (e) {
      debugPrint('[RemovedHolidaysSheet] Restore failed: $e');
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      _report(l10n.holidayRestoreFailed, AppConstants.snackbarErrorDuration);
      return;
    }
    if (!mounted) return;
    setState(() => _items?.remove(item));
    _report(l10n.holidayRestored, AppConstants.snackbarSuccessDuration);
  }

  /// In the overlay, not the page's `Scaffold`: this sheet is a route above
  /// that page, and a bar raised there is drawn under the sheet.
  void _report(String message, Duration duration) {
    OverlaySnackbar.show(context, message, duration: duration);
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
          leadingTooltip: l10n.close,
          leadingIdentifier: SemanticsIds.removedHolidaysClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.removedHolidays,
          scrolled: _hairline.scrolled,
          trailingInset: FormMetrics.headerActionInset,
          // Nothing to confirm: a restore has already written.
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
              child: _buildBody(l10n),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    final items = _items;
    if (items == null) {
      // One row's height, so the sheet opens at the size its first row will
      // take rather than collapsing to a spinner and growing a frame later.
      return const SizedBox(
        height: FormMetrics.rowMinHeight,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (items.isEmpty) {
      return FormCaption(
        text: l10n.removedHolidaysEmpty,
        padding: FormMetrics.groupCaptionPadding,
      );
    }
    final formatter = DateFormat.yMMMMd(l10n.localeName);
    return FormRowGroup(
      trailingGap: false,
      children: [
        for (final item in items)
          // A read row with the restore as its second target: the name and
          // the date are facts, and the one thing to do with them is the
          // button.
          FormPickerRow(
            glyph: Icons.event_busy_rounded,
            label: PublicHolidays.nameOf(item.holiday, l10n),
            value: formatter.format(item.date),
            onTap: null,
            showChevron: false,
            trailingButton: FormTrailingButton(
              icon: Icons.restore_rounded,
              tooltip: l10n.holidayRestore,
              identifier: SemanticsIds.holidayRestoreButton(
                item.holiday.name,
                item.date,
              ),
              onPressed: () => _restore(item),
            ),
          ),
      ],
    );
  }
}
