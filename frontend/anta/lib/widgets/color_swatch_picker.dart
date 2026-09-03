import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/calendar_palette.dart';
import '../l10n/app_localizations.dart';
import '../services/calendar_palette_service.dart';
import '../utils/custom_snackbar.dart';
import 'color_palette_sheet.dart';
import 'color_picker_sheet.dart';

/// The leading dot standing for "no colour of my own" — the theme's accent,
/// the category's colour, the fasting default. Every surface means something
/// slightly different by it, so the caller describes it rather than the
/// picker guessing.
class ColorSwatchDefault {
  final Color color;
  final IconData? icon;
  final String? tooltip;

  const ColorSwatchDefault({required this.color, this.icon, this.tooltip});
}

/// The one colour-choosing row in the app.
///
/// Renders the built-in swatches, then the user's own, then whatever colour
/// is currently selected if it is in neither (an event coloured before its
/// swatch was deleted keeps showing that colour, selected), then the two
/// affordances that make the palette editable: the picker, which **adds the
/// picked colour to the palette permanently** and selects it, and — when
/// [allowEditing] — a shortcut into [ColorPaletteSheet]. Long-pressing one of
/// the user's own swatches offers recolour and delete in place.
///
/// Repaints off [CalendarPalette.listenable], so a colour added from one
/// sheet appears in every other picker already on screen without any caller
/// plumbing a reload.
class ColorSwatchPicker extends StatefulWidget {
  /// The chosen colour, or null for [defaultOption].
  final int? value;

  /// Emits null only when [defaultOption] is non-null and the user picks it.
  final ValueChanged<int?> onChanged;

  /// Leading "use the default" dot. Omitted where a colour is mandatory (the
  /// category editor), present everywhere the colour is an override.
  final ColorSwatchDefault? defaultOption;

  final double spacing;

  const ColorSwatchPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.defaultOption,
    this.spacing = 8,
  });

  @override
  State<ColorSwatchPicker> createState() => _ColorSwatchPickerState();
}

class _ColorSwatchPickerState extends State<ColorSwatchPicker> {
  /// How many runs of dots the row shows before offering the rest behind a
  /// tap. Three keeps the control readable inside a form without hiding the
  /// common case: with no colours of the user's own the whole palette fits.
  static const int _collapsedRuns = 3;

  /// Whether the whole palette is shown, or only the first few runs. Reset on
  /// nothing: a user who expanded once is browsing colours.
  bool _expanded = false;

  /// Whether one of this row's sheets is already in flight. A dot is a small
  /// target in a field of small targets, so a double tap here is routine — and
  /// without this it pushes two identical pickers, the second of which looks
  /// like a sheet that refuses to close. Sheets opened from *inside* a guarded
  /// trip (the long-press menu's edit and manage entries) never re-check it.
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    // The palette is a self-initializing singleton like the rest of the
    // calendar services, so the first picker on screen is what loads it.
    // Nothing is stored: the row renders from the const built-ins until the
    // facade publishes, and the notifier below is what repaints it. Holding
    // the instance would survive a database switch or a backup restore, both
    // of which replace the service — and writes through the stale one would
    // go to a closed database or overwrite the restored palette.
    unawaited(CalendarPaletteService.getInstance());
    CalendarPalette.listenable.addListener(_onPaletteChanged);
  }

  @override
  void dispose() {
    CalendarPalette.listenable.removeListener(_onPaletteChanged);
    super.dispose();
  }

  /// Moves the selection onto a swatch that was recoloured — here, or in the
  /// management sheet, which is reachable from this very row. Either way the
  /// user asked for "this swatch, but that shade", so the thing they were
  /// colouring follows the swatch instead of being stranded on a shade the
  /// palette no longer offers.
  void _onPaletteChanged() {
    final recolor = CalendarPalette.lastRecolor;
    if (recolor == null || !mounted) return;
    if (widget.value == recolor.$1) widget.onChanged(recolor.$2);
  }

  Future<void> _addFromPicker() async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      final picked = await ColorPickerSheet.show(
        context,
        initialColor: widget.value,
      );
      if (picked == null || !mounted) return;
      widget.onChanged(picked);
      if (CalendarPalette.contains(picked)) return;
      final service = await CalendarPaletteService.getInstance();
      final added = await service.add(picked);
      if (added || !mounted) return;
      // The only way `add` refuses a colour the palette does not already carry.
      CustomSnackbar.showError(
        context,
        AppLocalizations.of(context)!.colorPaletteFull,
      );
    } finally {
      _sheetOpen = false;
    }
  }

  /// The manage affordance. Guarded like [_addFromPicker] and awaited, so the
  /// flag survives for the sheet's whole life rather than being cleared on the
  /// frame the route was pushed.
  Future<void> _openPaletteSheet() async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      await ColorPaletteSheet.show(context);
    } finally {
      _sheetOpen = false;
    }
  }

  Future<void> _editCustom(int color) async {
    final picked = await ColorPickerSheet.show(context, initialColor: color);
    if (picked == null || picked == color || !mounted) return;
    final service = await CalendarPaletteService.getInstance();
    final changed = await service.update(color, picked);
    if (changed || !mounted) return;
    CustomSnackbar.showError(
      context,
      AppLocalizations.of(context)!.colorAlreadyInPalette,
    );
  }

  Future<void> _openMenu(int color) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      await _menuBody(color);
    } finally {
      _sheetOpen = false;
    }
  }

  /// Unguarded body of [_openMenu]: the editor and the manage sheet it routes
  /// into are part of the same trip and already hold the slot.
  Future<void> _menuBody(int color) async {
    final l10n = AppLocalizations.of(context)!;
    final action = await showModalBottomSheet<_SwatchAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: ColorSwatchPreview(color: Color(color)),
              title: Text(l10n.editColor),
              onTap: () => Navigator.of(context).pop(_SwatchAction.edit),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(l10n.deleteColor),
              onTap: () => Navigator.of(context).pop(_SwatchAction.delete),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(l10n.manageColors),
              onTap: () => Navigator.of(context).pop(_SwatchAction.manage),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _SwatchAction.edit:
        await _editCustom(color);
      case _SwatchAction.delete:
        final service = await CalendarPaletteService.getInstance();
        await service.remove(color);
      case _SwatchAction.manage:
        if (!mounted) return;
        await ColorPaletteSheet.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<int>(
      valueListenable: CalendarPalette.listenable,
      builder: (context, _, _) {
        final selected = widget.value;
        final orphan = selected != null && !CalendarPalette.contains(selected);
        final defaultOption = widget.defaultOption;

        // The three dots that are never collapsed away: whatever "no colour
        // of my own" means here, the colour in force if the palette no longer
        // offers it, and the two affordances that add and manage.
        final leading = <Widget>[
          if (defaultOption != null)
            ColorSwatchDot(
              color: defaultOption.color,
              icon: defaultOption.icon,
              tooltip: defaultOption.tooltip,
              selected: selected == null,
              onTap: () => widget.onChanged(null),
            ),
          if (orphan)
            ColorSwatchDot(
              color: Color(selected),
              semanticLabel: CalendarPalette.hexOf(selected),
              selected: true,
              onTap: () => widget.onChanged(selected),
            ),
        ];
        final trailing = <Widget>[
          ColorSwatchDot(
            icon: Icons.colorize_rounded,
            tooltip: l10n.addColor,
            selected: false,
            onTap: _addFromPicker,
          ),
          ColorSwatchDot(
            icon: Icons.palette_outlined,
            tooltip: l10n.manageColors,
            selected: false,
            onTap: _openPaletteSheet,
          ),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            final palette = CalendarPalette.all;
            // A full palette is 18 built-ins + up to 24 of the user's own,
            // which is nine rows of circles in the middle of a form. The row
            // keeps its shape by showing the first few runs and offering the
            // rest behind one tap — and the *selected* swatch is always among
            // them, or the control would hide the very thing it is reporting.
            final perRun = _dotsPerRun(constraints.maxWidth);
            final budget =
                perRun * _collapsedRuns - leading.length - trailing.length - 1;

            final collapsed = !_expanded && palette.length > budget;
            final shown = collapsed
                ? _collapsedSwatches(palette, budget, selected)
                : palette;

            return Wrap(
              spacing: widget.spacing,
              runSpacing: widget.spacing,
              children: [
                ...leading,
                for (final swatch in shown)
                  ColorSwatchDot(
                    color: Color(swatch),
                    semanticLabel: CalendarPalette.hexOf(swatch),
                    selected: selected == swatch,
                    onTap: () => widget.onChanged(swatch),
                    onLongPress: CalendarPalette.isDefault(swatch)
                        ? null
                        : () => _openMenu(swatch),
                  ),
                if (collapsed)
                  ColorSwatchDot(
                    icon: Icons.more_horiz_rounded,
                    tooltip: l10n.colorShowAll(palette.length - shown.length),
                    selected: false,
                    onTap: () => setState(() => _expanded = true),
                  ),
                ...trailing,
              ],
            );
          },
        );
      },
    );
  }

  /// How many dots fit across [width] at the row's own metrics.
  int _dotsPerRun(double width) {
    final slot = ColorSwatchDot.tapTarget + widget.spacing;
    if (!width.isFinite || slot <= 0) return 1;
    final fits = ((width + widget.spacing) / slot).floor();
    return fits < 1 ? 1 : fits;
  }

  /// The first [budget] swatches, with the selected one swapped in if it
  /// would otherwise fall outside them.
  static List<int> _collapsedSwatches(
    List<int> palette,
    int budget,
    int? selected,
  ) {
    final limit = budget < 1 ? 1 : budget;
    final shown = palette.take(limit).toList();
    // An empty palette has no slot to swap the selection into. `take` on an
    // empty list is empty however generous the budget is, so the write below
    // would be an out-of-range assignment, not a no-op.
    if (shown.isEmpty) return shown;
    if (selected == null || shown.contains(selected)) return shown;
    if (!palette.contains(selected)) return shown;
    shown[shown.length - 1] = selected;
    return shown;
  }
}

enum _SwatchAction { edit, delete, manage }

/// The one colour dot. A null [color] paints the neutral surface fill used by
/// the add and manage affordances; a non-null one fills the circle and
/// resolves its own check-mark contrast.
///
/// The painted circle is [diameter], but an interactive dot lays out at
/// [tapTarget] with the circle centred in it — a 44px circle is a 44px target,
/// which is under Material's 48dp floor, and a colour row is a field of small
/// round things where a near-miss picks the wrong one.
class ColorSwatchDot extends StatelessWidget {
  /// Diameter of the painted circle.
  static const double diameter = 44;

  /// Footprint of an interactive dot, and therefore the row's grid unit.
  static const double tapTarget = 48;

  final Color? color;
  final IconData? icon;

  /// Shown on hover/long-press *and* used as the accessible name.
  final String? tooltip;

  /// The accessible name for a dot whose meaning is its fill and nothing
  /// else — a swatch. Without it a screen reader reads a row of eighteen
  /// identical "button, not selected" nodes.
  final String? semanticLabel;

  final bool selected;
  final double size;

  /// A null [onTap] renders the swatch as a sample rather than a choice — the
  /// built-in list in the management sheet, where tapping would promise an
  /// edit that is not on offer.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ColorSwatchDot({
    super.key,
    this.color,
    this.icon,
    this.tooltip,
    this.semanticLabel,
    required this.selected,
    this.onTap,
    this.onLongPress,
    this.size = diameter,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fill = color ?? colorScheme.surfaceContainerHighest;
    final onFill = color == null
        ? colorScheme.onSurfaceVariant
        : (ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
              ? Colors.white
              : Colors.black87);
    Widget dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? colorScheme.onSurface : colorScheme.outlineVariant,
          width: selected ? 2.5 : 1,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: size * 0.5, color: onFill)
          : (icon == null ? null : Icon(icon, size: size * 0.5, color: onFill)),
    );
    if (tooltip != null) dot = Tooltip(message: tooltip!, child: dot);
    if (onTap == null && onLongPress == null) return dot;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: SizedBox.square(
        dimension: size > tapTarget ? size : tapTarget,
        child: Center(
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            customBorder: const CircleBorder(),
            child: dot,
          ),
        ),
      ),
    );
  }
}

/// Non-interactive swatch used as a leading avatar in list rows.
class ColorSwatchPreview extends StatelessWidget {
  final Color color;

  const ColorSwatchPreview({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}
