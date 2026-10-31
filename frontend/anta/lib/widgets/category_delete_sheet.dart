import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart' show kFallbackCategoryId;
import '../models/category_delete_impact.dart';
import '../services/category_service.dart';
import '../utils/custom_snackbar.dart';
import 'category_picker_sheet.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'overlay_snackbar.dart';
import 'value_change_highlight.dart';

/// The delete of a custom category as one decision the user can read whole
/// before taking it (decision C1 of `docs/calendar-categories-roadmap.md`):
/// ✕ · Delete category · Delete, the category with what it holds, where its
/// events and templates go, and what else the delete changes.
///
/// A sub-sheet, so unguarded: ✕, back, the barrier and a drag leave with
/// `null` and write nothing. Delete writes **inside the sheet before the
/// pop**, the category editor's shape, and pops what
/// [CategoryService.deleteCategory] answered — `true` only when the DAO
/// really tombstoned the row, so the page's "Category deleted" never reports
/// a delete a pull already made, or one that never happened.
class CategoryDeleteSheet extends StatefulWidget {
  /// The custom category to delete; a built-in never reaches here (its menu
  /// item is disabled, and the service refuses one anyway).
  final CalendarCategory category;

  /// What the delete would touch, read by [show] before the route opens.
  final CategoryDeleteImpact impact;

  const CategoryDeleteSheet({
    super.key,
    required this.category,
    required this.impact,
  });

  /// Reads the counts first — milliseconds — and only then opens, so the
  /// sheet draws complete on its first frame: a caption landing later grew
  /// the row under the title and moved ✕, Delete and the Move row under the
  /// finger. A failed read opens nothing and says so on the page, which is
  /// still on top: a database that cannot count the rows would not delete
  /// them either.
  static Future<bool?> show(
    BuildContext context, {
    required CalendarCategory category,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final CategoryDeleteImpact impact;
    try {
      final service = await CategoryService.getInstance();
      impact = await service.deleteImpact(category.id);
    } catch (e, st) {
      debugPrint('[CategoryDeleteSheet] impact unavailable: $e\n$st');
      if (context.mounted) {
        CustomSnackbar.showError(context, l10n.categoryChangeFailed);
      }
      return null;
    }
    if (!context.mounted) return null;
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<bool>(
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
      // The Move row grows when a longer target wraps under its label, set
      // while the picker's route is still leaving.
      builder: (context) => FormSheetSemanticsRefresh(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.sizeOf(context).height *
                FormMetrics.sheetHeightFactor,
          ),
          child: CategoryDeleteSheet(category: category, impact: impact),
        ),
      ),
    );
  }

  @override
  State<CategoryDeleteSheet> createState() => _CategoryDeleteSheetState();
}

class _CategoryDeleteSheetState extends State<CategoryDeleteSheet> {
  final FormHeaderHairline _hairline = FormHeaderHairline();

  /// Where the events and templates go; Other until the user picks.
  String _target = kFallbackCategoryId;

  /// While Delete's write runs, ✕ is disabled and the `PopScope` refuses the
  /// barrier and system back, so the sheet pops what the DAO answered and
  /// nothing else. A route drag in that window — the cascade takes some
  /// 50 ms — still closes it with `null`; the write lands all the same and
  /// the page re-reads on the external-change signal, so it is accepted
  /// rather than fought with a drag gate.
  bool _deleting = false;

  @override
  void dispose() {
    _hairline.dispose();
    super.dispose();
  }

  Future<void> _pickTarget() async {
    final picked = await CategoryPickerSheet.pickSingle(
      context,
      selectedId: _target,
      exclude: {widget.category.id},
    );
    if (picked == null || !mounted) return;
    setState(() => _target = picked);
  }

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      final service = await CategoryService.getInstance();
      final deleted = await service.deleteCategory(
        widget.category.id,
        reassignTo: _target,
      );
      if (!mounted) return;
      Navigator.of(context).pop(deleted);
    } catch (e, st) {
      debugPrint('[CategoryDeleteSheet] Delete failed: $e\n$st');
      if (!mounted) return;
      setState(() => _deleting = false);
      // In the overlay, not the page's `Scaffold`, which draws under this
      // sheet: the sheet stays, so the user can try again or leave.
      OverlaySnackbar.show(
        context,
        AppLocalizations.of(context)!.categoryChangeFailed,
        duration: AppConstants.snackbarErrorDuration,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view, never the whole body (`sheet_bottom_clearance_test.dart`).
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    final impact = widget.impact;
    final category = widget.category;
    final name = CalendarCategories.labelOf(category, l10n);
    // The categories page's rule, decided by the text scale and never by the
    // name: at large text the glyph replaces the avatar, and the 18 dp it
    // frees keeps a one-word built-in name whole at 2.0 on a small phone.
    final scaler = MediaQuery.textScalerOf(context);
    final compact =
        scaler.scale(RowMetrics.titleFontSize) / RowMetrics.titleFontSize >=
        RowMetrics.compactLeadingTextScale;
    final icon = CalendarIcons.forKey(category.iconKey) ?? Icons.event_rounded;
    return PopScope(
      canPop: !_deleting,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormSheetHandle(),
          FormSheetHeader(
            leadingIcon: Icons.close_rounded,
            leadingTooltip: l10n.cancel,
            leadingIdentifier: SemanticsIds.categoryDeleteClose,
            onLeading: _deleting ? null : () => Navigator.of(context).pop(),
            title: l10n.deleteCategory,
            // "Delete category" is cut at 2.0 in every language beside ✕ and
            // Delete; stacked, it reads whole.
            stackTitleAtLargeText: true,
            scrolled: _hairline.scrolled,
            trailingInset: FormMetrics.headerActionInset,
            trailing: FormHeaderTextButton(
              label: l10n.delete,
              identifier: SemanticsIds.categoryDeleteConfirm,
              color: colorScheme.error,
              onPressed: _deleting ? null : _delete,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FormRowGroup(
                      trailingGap: false,
                      children: [
                        FormReadTitleRow(
                          leading: compact
                              ? Icon(
                                  icon,
                                  size: RowMetrics.glyphSize,
                                  color: category.color,
                                )
                              : EventAvatar(icon: icon, color: category.color),
                          leadingSize: compact
                              ? FormMetrics.glyphSize
                              : FormMetrics.rowLeadingSize,
                          title: name,
                          caption: _impactCaption(l10n, impact),
                        ),
                        // The picker closes itself on a pick, so the row it
                        // wrote to is read back with a flash.
                        ValueChangeHighlight(
                          value: _target,
                          child: FormPickerRow(
                            glyph: Icons.drive_file_move_rounded,
                            label: l10n.categoryDeleteMoveTo,
                            value: CalendarCategories.labelOf(
                              CalendarCategories.resolve(_target),
                              l10n,
                            ),
                            identifier: SemanticsIds.categoryDeleteTarget,
                            // Nothing to move is said by disabling the row in
                            // place, never by hiding it.
                            enabled:
                                impact.events + impact.templates > 0 &&
                                !_deleting,
                            onTap: _pickTarget,
                          ),
                        ),
                      ],
                    ),
                    // Sized for all three sentences, so the caption keeps its
                    // height whatever the counts say.
                    FormCaptionSlot(
                      candidates: [
                        _consequences(
                          l10n,
                          name,
                          templates: true,
                          alerts: true,
                        ),
                      ],
                      child: _consequences(
                        l10n,
                        name,
                        templates: impact.templates > 0,
                        alerts: impact.alerts > 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "n events · m alerts · k templates": the events always, zero reading
  /// "No events"; the alerts and templates only when there are some. Each
  /// segment's words are held together by the no-break spaces the strings
  /// carry, and the space before each dot is one too, so a wrapped line
  /// never starts with the dot (the categories page's caption).
  static String _impactCaption(
    AppLocalizations l10n,
    CategoryDeleteImpact impact,
  ) {
    return [
      l10n.categoryEventCount(impact.events),
      if (impact.alerts > 0) l10n.categoryDeleteImpactAlerts(impact.alerts),
      if (impact.templates > 0)
        l10n.categoryDeleteImpactTemplates(impact.templates),
    ].join(' · ');
  }

  /// Templates, then alerts, then the views: the first two only when the
  /// category has some, the last always.
  static Widget _consequences(
    AppLocalizations l10n,
    String name, {
    required bool templates,
    required bool alerts,
  }) {
    return FormCaption(
      text: [
        if (templates) l10n.categoryDeleteTemplatesMove,
        if (alerts) l10n.categoryDeleteAlertsRemoved,
        l10n.categoryDeleteConsequences(name),
      ].join(' '),
      padding: FormMetrics.groupCaptionPadding,
    );
  }
}
