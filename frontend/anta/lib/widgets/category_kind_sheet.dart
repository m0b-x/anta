import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/category_kinds.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../utils/category_profile_labels.dart';
import 'form_rows.dart';

/// The category editor's kind picker (analytics S3): every kind of the
/// catalogue under its area's label, each with its one line of examples,
/// Custom last — a sub-sheet that picks on tap, in `CategoryPickerSheet`'s
/// single mode shape.
///
/// No search (the S3 spec's E): twenty-one rows in seven labelled groups,
/// and a field would raise the keyboard over them. Opens at the top and
/// never scrolls to the checked row (H), so the groups always read in the
/// same order from the same place.
class CategoryKindSheet extends StatefulWidget {
  final CategoryKind selected;

  const CategoryKindSheet({super.key, required this.selected});

  /// The picked kind, or null on ✕, the barrier, back and a drag.
  static Future<CategoryKind?> show(
    BuildContext context, {
    required CategoryKind selected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<CategoryKind>(
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
        child: CategoryKindSheet(selected: selected),
      ),
    );
  }

  @override
  State<CategoryKindSheet> createState() => _CategoryKindSheetState();
}

class _CategoryKindSheetState extends State<CategoryKindSheet> {
  final FormHeaderHairline _hairline = FormHeaderHairline();

  @override
  void dispose() {
    _hairline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view, never the whole body (`sheet_bottom_clearance_test.dart`).
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    final areas = [
      for (final area in CategoryKinds.areas)
        if (CategoryKinds.inArea(area).isNotEmpty) area,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.categoryKindClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.categoryKindLabel,
          scrolled: _hairline.scrolled,
          trailingInset: FormMetrics.headerActionInset,
          // A pick is the answer; there is nothing to confirm.
          trailing: const SizedBox.shrink(),
        ),
        Flexible(
          child: _hairline.watch(
            child: Semantics(
              identifier: SemanticsIds.categoryKindList,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  RowMetrics.groupInset,
                  FormMetrics.bodyTop,
                  RowMetrics.groupInset,
                  FormMetrics.bodyBottom + clearance,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final area in areas) ...[
                      FormSectionLabel(text: lifeAreaName(l10n, area)),
                      FormRowGroup(
                        trailingGap: area != areas.last,
                        children: [
                          for (final row in CategoryKinds.inArea(area))
                            FormCheckRow(
                              label: categoryKindName(l10n, row.kind),
                              caption: categoryKindExample(l10n, row.kind),
                              checked: row.kind == widget.selected,
                              exclusive: true,
                              identifier: SemanticsIds.categoryKind(
                                row.kind.name,
                              ),
                              onChanged: (_) =>
                                  Navigator.of(context).pop(row.kind),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
