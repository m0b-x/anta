import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import '../constants/calendar_palette.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../services/calendar_palette_service.dart';
import '../utils/custom_snackbar.dart';
import 'app_dialogs.dart';
import 'color_picker_sheet.dart';
import 'color_swatch_picker.dart';
import 'settings_reorder.dart';

/// Management surface for the calendar colour palette: add a colour, recolour,
/// reorder or delete one of your own, or drop back to the built-in set.
///
/// Reached from the palette icon on any [ColorSwatchPicker] and from the
/// calendar settings page. Applies **live** like the other settings sheets —
/// every tap persists through [CalendarPaletteService] and republishes the
/// facade, so there is nothing to save and dismissing is never a discard.
///
/// The row order **is** the order every picker draws its dots in, which is
/// what makes dragging worth having: the colours reached for most can be put
/// where the thumb lands first.
class ColorPaletteSheet extends StatefulWidget {
  const ColorPaletteSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.86,
        child: ColorPaletteSheet(),
      ),
    );
  }

  @override
  State<ColorPaletteSheet> createState() => _ColorPaletteSheetState();
}

class _ColorPaletteSheetState extends State<ColorPaletteSheet> {
  @override
  void initState() {
    super.initState();
    // Warms the singleton so an unopened palette fills in; nothing is stored,
    // because a restore or a database switch replaces the service and writes
    // through a held instance would go to the wrong place.
    unawaited(CalendarPaletteService.getInstance());
  }

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context)!;
    if (CalendarPalette.custom.length >= SettingsKeys.maxCustomCalendarColors) {
      CustomSnackbar.showError(context, l10n.colorPaletteFull);
      return;
    }
    final picked = await ColorPickerSheet.show(context);
    if (picked == null || !mounted) return;
    final added = await (await CalendarPaletteService.getInstance()).add(
      picked,
    );
    if (added || !mounted) return;
    CustomSnackbar.showError(context, l10n.colorAlreadyInPalette);
  }

  Future<void> _edit(int color) async {
    final picked = await ColorPickerSheet.show(context, initialColor: color);
    if (picked == null || picked == color || !mounted) return;
    final changed = await (await CalendarPaletteService.getInstance()).update(
      color,
      picked,
    );
    if (changed || !mounted) return;
    CustomSnackbar.showError(
      context,
      AppLocalizations.of(context)!.colorAlreadyInPalette,
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
    CustomSnackbar.showSuccess(context, l10n.settingsReset);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // `useSafeArea: true` guards the status bar, not the bottom gesture bar.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return ValueListenableBuilder<int>(
      valueListenable: CalendarPalette.listenable,
      builder: (context, _, _) {
        final custom = CalendarPalette.custom;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: l10n.close,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      l10n.colorPaletteTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.addColor,
                    icon: const Icon(Icons.add_rounded),
                    onPressed: _add,
                  ),
                ],
              ),
            ),
            // Slivers rather than a ListView so the reorderable rows keep a
            // real scrollable of their own: a `shrinkWrap` list inside another
            // scroll view silently kills drag auto-scroll, the same trap the
            // categories page documents.
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.colorPaletteDesc,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              0,
                              AppSpacing.lg,
                              0,
                              AppSpacing.sm,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.colorPaletteCustomLabel,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                // The cap is invisible until it refuses an
                                // add, which is the wrong moment to learn it
                                // exists.
                                Text(
                                  l10n.colorPaletteCapCount(
                                    custom.length,
                                    SettingsKeys.maxCustomCalendarColors,
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (custom.isEmpty)
                            Text(
                              l10n.colorPaletteEmpty,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          else
                            Text(
                              l10n.colorPaletteEditHint,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverReorderableList(
                      itemCount: custom.length,
                      onReorderItem: _reorder,
                      proxyDecorator: reorderDragProxy,
                      itemBuilder: (context, index) => _CustomColorRow(
                        key: ValueKey(custom[index]),
                        color: custom[index],
                        index: index,
                        onEdit: () => _edit(custom[index]),
                        onDelete: () => _delete(custom[index]),
                      ),
                    ),
                  ),
                  SliverPadding(
                    // The clearance rides the last sliver's padding rather than a
                    // trailing box, which is where every other sheet in the app
                    // puts it — and what `sheet_bottom_clearance_test` measures.
                    padding: EdgeInsets.fromLTRB(
                      20,
                      AppSpacing.sm,
                      20,
                      24 + bottomClearance,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _add,
                            icon: const Icon(Icons.add_rounded),
                            label: Text(l10n.addColor),
                          ),
                          _Label(text: l10n.colorPaletteDefaultsLabel),
                          Wrap(
                            spacing: AppSpacing.md,
                            runSpacing: AppSpacing.md,
                            children: [
                              // Samples, not choices: a built-in cannot be
                              // edited or deleted, so it gets no tap target
                              // promising either.
                              for (final color in CalendarPalette.defaults)
                                ColorSwatchDot(
                                  color: Color(color),
                                  selected: false,
                                  tooltip: l10n.colorPaletteBuiltIn,
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Center(
                            child: TextButton.icon(
                              onPressed: custom.isEmpty
                                  ? null
                                  : _resetToDefaults,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(l10n.colorPaletteReset),
                              style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One of the user's own swatches: drag handle, sample, hex, delete.
///
/// The handle leads the row, where the other three reorderable lists in the
/// app put theirs, so the four read as one system.
class _CustomColorRow extends StatelessWidget {
  final int color;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CustomColorRow({
    super.key,
    required this.color,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A label, never a `Tooltip`: a tooltip brings a long-press
          // recognizer, and holding still on the handle then dragging would
          // let it win the arena and kill the reorder. The other three
          // reorderable lists in the app carry a bare handle for the same
          // reason.
          Semantics(
            label: l10n.colorReorder,
            child: ReorderHandle(index: index),
          ),
          const SizedBox(width: AppSpacing.sm),
          ColorSwatchPreview(color: Color(color)),
        ],
      ),
      title: Text(CalendarPalette.hexOf(color)),
      trailing: IconButton(
        tooltip: l10n.deleteColor,
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: onDelete,
      ),
      onTap: onEdit,
    );
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.lg, 0, AppSpacing.sm),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
