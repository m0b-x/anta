import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import 'form_rows.dart';

/// One row of a [FilterCheckListSheet]: the value's own icon and label — a
/// priority's glyph, a trait's facet icon — never the field's.
class FilterCheckItem {
  final String id;
  final IconData icon;
  final String label;

  /// A `SemanticsIds` value for the row, so a device script ticks it in any
  /// locale.
  final String? identifier;

  const FilterCheckItem({
    required this.id,
    required this.icon,
    required this.label,
    this.identifier,
  });
}

/// The check-list sub-sheet the filter sheet's Priority and Only show rows
/// open: one group of check rows, ✕ · title · Done, content-tall.
///
/// One class for both lists rather than a file per value list, so the two
/// cannot drift. Done returns the checked ids — an empty set is a real
/// answer ("Any", "Everything"), never collapsed to `null`; ✕, drag, back and
/// the barrier return `null` and change nothing. No guard: a draft here costs
/// one tap to redo.
class FilterCheckListSheet extends StatefulWidget {
  final String title;
  final List<FilterCheckItem> items;
  final Set<String> selected;

  const FilterCheckListSheet({
    super.key,
    required this.title,
    required this.items,
    required this.selected,
  });

  static Future<Set<String>?> show(
    BuildContext context, {
    required String title,
    required List<FilterCheckItem> items,
    required Set<String> selected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<Set<String>>(
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
        child: FilterCheckListSheet(
          title: title,
          items: items,
          selected: selected,
        ),
      ),
    );
  }

  @override
  State<FilterCheckListSheet> createState() => _FilterCheckListSheetState();
}

class _FilterCheckListSheetState extends State<FilterCheckListSheet> {
  late final Set<String> _selected = {...widget.selected};

  /// The body's scroll position feeds the header's hairline (a form sheet's
  /// rule): a notifier, never `setState`, so a scroll frame rebuilds a 1 px
  /// line and not the sheet.
  final ScrollController _bodyScroll = ScrollController();
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _bodyScroll.addListener(_onBodyScroll);
  }

  @override
  void dispose() {
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    _headerScrolled.dispose();
    super.dispose();
  }

  void _onBodyScroll() {
    final scrolled = _bodyScroll.hasClients && _bodyScroll.offset > 0;
    if (_headerScrolled.value != scrolled) _headerScrolled.value = scrolled;
  }

  void _setChecked(String id, bool checked) {
    setState(() {
      if (checked) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
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
          leadingIdentifier: SemanticsIds.filterListClose,
          onLeading: () => Navigator.of(context).pop(),
          title: widget.title,
          scrolled: _headerScrolled,
          trailingInset: FormMetrics.headerActionInset,
          trailing: FormHeaderTextButton(
            label: l10n.eventDescriptionDone,
            identifier: SemanticsIds.filterListDone,
            onPressed: () => Navigator.of(context).pop({..._selected}),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: _bodyScroll,
            padding: EdgeInsets.fromLTRB(
              RowMetrics.groupInset,
              FormMetrics.bodyTop,
              RowMetrics.groupInset,
              FormMetrics.bodyBottom + clearance,
            ),
            child: FormRowGroup(
              trailingGap: false,
              children: [
                for (final item in widget.items)
                  FormCheckRow(
                    glyph: item.icon,
                    label: item.label,
                    checked: _selected.contains(item.id),
                    identifier: item.identifier,
                    onChanged: (checked) => _setChecked(item.id, checked),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
