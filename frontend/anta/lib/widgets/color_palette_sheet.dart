import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/calendar_palette.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../services/calendar_palette_service.dart';
import 'app_dialogs.dart';
import 'color_picker_sheet.dart';
import 'color_swatch_picker.dart';
import 'form_rows.dart';
import 'overlay_snackbar.dart';
import 'settings_reorder.dart';

/// Management surface for the calendar colour palette: add a colour, recolour,
/// reorder or delete one of your own, or drop back to the built-in set — a
/// sub-sheet of the UI language since Tier 3
/// (`docs/calendar-language-tier-3-roadmap.md`, D20): YOUR COLORS as a run
/// of rows with their handles and deletes under the "n of 24" count, one Add
/// color row closing the run, the built-ins as a read-only strip, Reset
/// colors last.
///
/// Reached from the manage dot and the long-press menu of any
/// [ColorSwatchPicker] and from the appearance page's Colors row. Applies
/// **live** like the other settings sheets — every tap persists through
/// [CalendarPaletteService] and republishes the facade, so there is nothing
/// to save and dismissing is never a discard.
///
/// The row order **is** the order every picker draws its dots in, which is
/// what makes dragging worth having: the colours reached for most can be put
/// where the thumb lands first.
class ColorPaletteSheet extends StatefulWidget {
  const ColorPaletteSheet({super.key});

  static Future<void> show(BuildContext context) {
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
        child: const ColorPaletteSheet(),
      ),
    );
  }

  @override
  State<ColorPaletteSheet> createState() => _ColorPaletteSheetState();
}

class _ColorPaletteSheetState extends State<ColorPaletteSheet> {
  final FormHeaderHairline _hairline = FormHeaderHairline();

  @override
  void initState() {
    super.initState();
    // Warms the singleton so an unopened palette fills in; nothing is stored,
    // because a restore or a database switch replaces the service and writes
    // through a held instance would go to the wrong place.
    unawaited(CalendarPaletteService.getInstance());
  }

  @override
  void dispose() {
    _hairline.dispose();
    super.dispose();
  }

  /// In the overlay, not the page's `Scaffold`: this sheet is a route above
  /// that page, and a bar raised there is drawn under the sheet.
  void _report(String message, Duration duration) {
    OverlaySnackbar.show(context, message, duration: duration);
  }

  /// The cap check stays although the Add color row is disabled at the cap:
  /// `_add` is the contract, and a refusal explained beats a silent no-op
  /// should another opener ever reach it.
  Future<void> _add() async {
    final l10n = AppLocalizations.of(context)!;
    if (CalendarPalette.custom.length >= SettingsKeys.maxCustomCalendarColors) {
      _report(l10n.colorPaletteFull, AppConstants.snackbarErrorDuration);
      return;
    }
    final picked = await ColorPickerSheet.show(context);
    if (picked == null || !mounted) return;
    final added = await (await CalendarPaletteService.getInstance()).add(
      picked,
    );
    if (added || !mounted) return;
    _report(l10n.colorAlreadyInPalette, AppConstants.snackbarErrorDuration);
  }

  Future<void> _edit(int color) async {
    final picked = await ColorPickerSheet.show(context, initialColor: color);
    if (picked == null || picked == color || !mounted) return;
    final changed = await (await CalendarPaletteService.getInstance()).update(
      color,
      picked,
    );
    if (changed || !mounted) return;
    _report(
      AppLocalizations.of(context)!.colorAlreadyInPalette,
      AppConstants.snackbarErrorDuration,
    );
  }

  Future<void> _delete(int color) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.deleteColor,
      content: l10n.deleteColorConfirm,
      confirmText: l10n.delete,
      icon: Icons.delete_outline_rounded,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await (await CalendarPaletteService.getInstance()).remove(color);
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    await (await CalendarPaletteService.getInstance()).move(oldIndex, newIndex);
  }

  Future<void> _resetToDefaults() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.colorPaletteReset,
      content: l10n.colorPaletteResetConfirm,
      confirmText: l10n.reset,
      icon: Icons.refresh_rounded,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await (await CalendarPaletteService.getInstance()).resetToDefaults();
    if (!mounted) return;
    _report(l10n.colorPaletteResetDone, AppConstants.snackbarSuccessDuration);
  }

  /// The lifted row: the shared proxy (a hair of scale, a shadow) over a
  /// clip. A middle row of the run paints square corners of its own, and the
  /// proxy's rounded shadow would otherwise frame a square card.
  Widget _liftedRow(Widget child, int index, Animation<double> animation) {
    return reorderDragProxy(
      ClipRRect(
        borderRadius: BorderRadius.circular(reorderProxyRadius),
        child: child,
      ),
      index,
      animation,
    );
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

    return ValueListenableBuilder<int>(
      valueListenable: CalendarPalette.listenable,
      builder: (context, _, _) {
        final custom = CalendarPalette.custom;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FormSheetHandle(),
            FormSheetHeader(
              leadingIcon: Icons.close_rounded,
              leadingTooltip: l10n.close,
              leadingIdentifier: SemanticsIds.paletteClose,
              onLeading: () => Navigator.of(context).pop(),
              title: l10n.colorPaletteTitle,
              scrolled: _hairline.scrolled,
              trailingInset: FormMetrics.headerActionInset,
              // Nothing to confirm: every tap has already written.
              trailing: const SizedBox.shrink(),
            ),
            // Slivers rather than a ListView so the reorderable rows keep a
            // real scrollable of their own: a `shrinkWrap` list inside
            // another scroll view silently kills drag auto-scroll, the same
            // trap the categories page documents. Shrink-wrapped itself, so
            // the sheet stays content-tall under the sub-sheet's clamp while
            // still being the one scrollable.
            Flexible(
              child: _hairline.watch(
                child: CustomScrollView(
                  shrinkWrap: true,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        RowMetrics.groupInset,
                        FormMetrics.bodyTop,
                        RowMetrics.groupInset,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: FormSectionLabel(
                          text: l10n.colorPaletteCustomLabel,
                          // The cap is invisible until it refuses an add,
                          // which is the wrong moment to learn it exists.
                          trailing: l10n.colorPaletteCapCount(
                            custom.length,
                            SettingsKeys.maxCustomCalendarColors,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RowMetrics.groupInset,
                      ),
                      sliver: SliverReorderableList(
                        itemCount: custom.length,
                        onReorderItem: _reorder,
                        proxyDecorator: _liftedRow,
                        itemBuilder: (context, index) =>
                            _buildCustomRow(l10n, custom, index),
                      ),
                    ),
                    SliverPadding(
                      // The clearance rides the last sliver's padding rather
                      // than a trailing box, which is where every other
                      // sheet in the app puts it — and what
                      // `sheet_bottom_clearance_test` measures.
                      padding: EdgeInsets.fromLTRB(
                        RowMetrics.groupInset,
                        0,
                        RowMetrics.groupInset,
                        FormMetrics.bodyBottom + clearance,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildAddRow(l10n, custom),
                            if (custom.isEmpty)
                              FormCaption(
                                text: l10n.colorPaletteEmpty,
                                // Under the group, and the group gap before
                                // the next section's label.
                                padding: FormMetrics.groupCaptionPadding
                                    .copyWith(bottom: RowMetrics.groupGap),
                              ),
                            FormSectionLabel(
                              text: l10n.colorPaletteDefaultsLabel,
                            ),
                            FormRowGroup(children: [_buildBuiltInStrip()]),
                            FormRowGroup(
                              trailingGap: false,
                              children: [_buildResetRow(l10n, custom)],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// One of the user's own swatches as a row of the run: the handle, the
  /// sample, the hex, the delete — a tap recolours. Lifted by its handle or
  /// by a long press anywhere on it (the saved-filters rows' pair).
  Widget _buildCustomRow(AppLocalizations l10n, List<int> custom, int index) {
    final color = custom[index];
    final hex = CalendarPalette.hexOf(color);
    return ReorderableDelayedDragStartListener(
      key: ValueKey(color),
      index: index,
      child: FormRowShell(
        first: index == 0,
        // The Add color row closes the run, so no colour row is its last.
        last: false,
        child: FormPickerRow(
          handle: FormDragHandle(
            index: index,
            label: l10n.colorReorder,
            identifier: SemanticsIds.paletteHandle(hex),
          ),
          leading: ColorSwatchPreview(color: Color(color)),
          label: hex,
          onTap: () => _edit(color),
          showChevron: false,
          identifier: SemanticsIds.paletteRow(hex),
          trailingButton: FormTrailingButton(
            icon: Icons.delete_outline_rounded,
            tooltip: l10n.deleteColor,
            identifier: SemanticsIds.paletteDelete(hex),
            onPressed: () => _delete(color),
          ),
        ),
      ),
    );
  }

  /// The one add control, closing the run of the user's colours — disabled
  /// in place at the cap, with the count above saying why.
  Widget _buildAddRow(AppLocalizations l10n, List<int> custom) {
    final atCap = custom.length >= SettingsKeys.maxCustomCalendarColors;
    return FormRowShell(
      first: custom.isEmpty,
      last: true,
      child: FormActionRow(
        glyph: Icons.add_rounded,
        label: l10n.addColor,
        identifier: SemanticsIds.paletteAdd,
        onTap: atCap ? null : _add,
      ),
    );
  }

  /// Samples, not choices: a built-in cannot be edited or deleted, so it
  /// gets no tap target promising either — only its hex as its name.
  Widget _buildBuiltInStrip() {
    return FormSwatchRow(
      child: Wrap(
        spacing: FormMetrics.swatchSpacing,
        runSpacing: FormMetrics.swatchSpacing,
        children: [
          for (final color in CalendarPalette.defaults)
            ColorSwatchDot(
              color: Color(color),
              selected: false,
              semanticLabel: CalendarPalette.hexOf(color),
            ),
        ],
      ),
    );
  }

  Widget _buildResetRow(AppLocalizations l10n, List<int> custom) {
    return FormActionRow(
      glyph: Icons.refresh_rounded,
      label: l10n.colorPaletteReset,
      destructive: true,
      identifier: SemanticsIds.paletteReset,
      onTap: custom.isEmpty ? null : _resetToDefaults,
    );
  }
}
