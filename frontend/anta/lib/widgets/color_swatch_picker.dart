import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_theme.dart';
import '../constants/calendar_palette.dart';
import '../constants/form_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../services/calendar_palette_service.dart';
import 'app_dialogs.dart';
import 'automation_id.dart';
import 'color_palette_sheet.dart';
import 'color_picker_sheet.dart';
import 'form_menu_item.dart';
import 'overlay_snackbar.dart';

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

/// The dot's own drawing, and the sample that stands in for one at a row's
/// start. Private because none of it is a form row's geometry: a row sees
/// only the dot's [ColorSwatchDot.tapTarget] footprint and its diameter,
/// which `FormMetrics` names.
abstract final class _SwatchMetrics {
  /// The gap between the dots when the caller sets none: the strip's
  /// spacing before the Look sheet closed it to `FormMetrics.swatchSpacing`
  /// so eighteen colours fit three runs. Every sheet of the language passes
  /// that one and the appearance page its own, so this reaches only a bare
  /// strip.
  static const double looseSpacing = 8;

  /// A hairline in `outlineVariant` around every dot, so a swatch near the
  /// surface's own colour still has an edge; the selected one's ring in
  /// `onSurface` at two and a half times that, so the selection reads from
  /// across the strip without leaning on the check glyph alone.
  static const double ringWidth = 1;
  static const double selectedRingWidth = 2.5;

  /// The check or glyph inside a dot, as a share of its diameter: half, so
  /// the fill stays what the eye reads and the glyph is a mark on it.
  static const double glyphShare = 0.5;

  /// The sample at a row's start — the palette's rows — inside the row's
  /// `rowLeadingSize` box: smaller than the 40 dp avatar the box is cut for,
  /// so the row reads as a colour beside its hex rather than an avatar row.
  static const double previewDiameter = 24;
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

  final bool collapsible;

  const ColorSwatchPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.defaultOption,
    this.spacing = _SwatchMetrics.looseSpacing,
    this.collapsible = true,
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

  /// Drops the focus before anything modal opens over the strip. The strip
  /// sits under a text field in the category editor and the fasting style
  /// sheet, and a field still focused when the modal returns raises the
  /// keyboard again and scrolls the sheet back up to it.
  static void _blur() => FocusManager.instance.primaryFocus?.unfocus();

  /// A refusal raised over whatever sheet embeds the strip, up for the error
  /// duration the palette sheet gives these same two refusals. A `Scaffold`
  /// snackbar is drawn on the page under the modal route, where nobody saw
  /// "Your palette is full" from the Look sheet.
  void _refuse(String message) => OverlaySnackbar.show(
    context,
    message,
    duration: AppConstants.snackbarErrorDuration,
  );

  Future<void> _addFromPicker() async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      _blur();
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
      _refuse(AppLocalizations.of(context)!.colorPaletteFull);
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
      _blur();
      await ColorPaletteSheet.show(context);
    } finally {
      _sheetOpen = false;
    }
  }

  Future<void> _editCustom(int color) async {
    _blur();
    final picked = await ColorPickerSheet.show(context, initialColor: color);
    if (picked == null || picked == color || !mounted) return;
    final service = await CalendarPaletteService.getInstance();
    final changed = await service.update(color, picked);
    if (changed || !mounted) return;
    _refuse(AppLocalizations.of(context)!.colorAlreadyInPalette);
  }

  /// Asks first, as the palette sheet's delete does (Tier 3, D21): the
  /// strip's menu is one long press from a dot in a field of dots, and an
  /// unconfirmed delete there took a colour off every event wearing it.
  Future<void> _deleteCustom(int color) async {
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
    final service = await CalendarPaletteService.getInstance();
    await service.remove(color);
  }

  /// [anchor] is the long-pressed dot's own element, which is where the menu
  /// hangs.
  Future<void> _openMenu(BuildContext anchor, int color) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      await _menuBody(anchor, color);
    } finally {
      _sheetOpen = false;
    }
  }

  /// Unguarded body of [_openMenu]: the editor and the manage sheet it routes
  /// into are part of the same trip and already hold the slot.
  ///
  /// A popup of the language's menu rows at the dot — the preset ⋮'s
  /// anatomy and anchor rule — never a bottom sheet of list tiles, so the
  /// strip's one menu reads like every other menu in the app.
  Future<void> _menuBody(BuildContext anchor, int color) async {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    _blur();
    final action = await showMenu<_SwatchAction>(
      context: anchor,
      positionBuilder: (_, constraints) => formMenuPosition(
        anchor,
        constraints,
        menuHeight: formMenuHeight(_SwatchAction.values.length),
      ),
      color: colorScheme.menuSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FormMetrics.menuRadius),
      ),
      menuPadding: FormMetrics.menuPadding,
      // The preset ⋮'s floor, not a choice menu's: an actions menu floors
      // at the app's menu width and grows for a label that needs it.
      constraints: const BoxConstraints(
        minWidth: AppTheme.menuWidth,
        maxWidth: FormMetrics.menuMaxWidth,
      ),
      items: [
        PopupMenuItem<_SwatchAction>(
          value: _SwatchAction.edit,
          height: FormMetrics.menuRowHeight,
          child: FormMenuItemRow(
            identifier: SemanticsIds.swatchMenuEdit,
            icon: Icons.edit_outlined,
            label: l10n.editColor,
          ),
        ),
        PopupMenuItem<_SwatchAction>(
          value: _SwatchAction.delete,
          height: FormMetrics.menuRowHeight,
          child: FormMenuItemRow(
            identifier: SemanticsIds.swatchMenuDelete,
            icon: Icons.delete_outline_rounded,
            label: l10n.deleteColor,
            color: colorScheme.error,
          ),
        ),
        PopupMenuItem<_SwatchAction>(
          value: _SwatchAction.manage,
          height: FormMetrics.menuRowHeight,
          child: FormMenuItemRow(
            identifier: SemanticsIds.swatchMenuManage,
            icon: Icons.palette_outlined,
            label: l10n.manageColors,
          ),
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _SwatchAction.edit:
        await _editCustom(color);
      case _SwatchAction.delete:
        await _deleteCustom(color);
      case _SwatchAction.manage:
        _blur();
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
              // Always a glyph: a default dot drawn bare is identical to a
              // swatch of the same colour beside it (the fasting violet next
              // to #8E24AA on the device).
              icon: defaultOption.icon ?? Icons.format_color_reset_rounded,
              tooltip: defaultOption.tooltip,
              selected: selected == null,
              identifier: SemanticsIds.swatchDefault,
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
            identifier: SemanticsIds.swatchAdd,
            onTap: _addFromPicker,
          ),
          ColorSwatchDot(
            icon: Icons.palette_outlined,
            tooltip: l10n.manageColors,
            selected: false,
            identifier: SemanticsIds.swatchManage,
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

            final collapsed =
                widget.collapsible && !_expanded && palette.length > budget;
            final shown = collapsed
                ? _collapsedSwatches(palette, budget, selected)
                : palette;

            return Wrap(
              spacing: widget.spacing,
              runSpacing: widget.spacing,
              children: [
                ...leading,
                for (final swatch in shown)
                  if (CalendarPalette.isDefault(swatch))
                    ColorSwatchDot(
                      color: Color(swatch),
                      semanticLabel: CalendarPalette.hexOf(swatch),
                      selected: selected == swatch,
                      onTap: () => widget.onChanged(swatch),
                    )
                  else
                    // An element of its own, so the long-press menu can hang
                    // from the dot's render box.
                    Builder(
                      builder: (dotContext) => ColorSwatchDot(
                        color: Color(swatch),
                        semanticLabel: CalendarPalette.hexOf(swatch),
                        selected: selected == swatch,
                        onTap: () => widget.onChanged(swatch),
                        onLongPress: () => _openMenu(dotContext, swatch),
                      ),
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
  static const double diameter = FormMetrics.swatchDiameter;

  /// Footprint of an interactive dot, and therefore the row's grid unit.
  static const double tapTarget = FormMetrics.trailingButtonSize;

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
  /// edit that is not on offer. A sample still takes the [tapTarget]
  /// footprint and carries its [semanticLabel] as a plain node, so the
  /// palette's read-only strip sits on the pickers' grid and reads each
  /// colour's hex to a screen reader instead of eighteen silent circles.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// A `SemanticsIds` value for a dot a device script hits by id — the
  /// default, add and manage dots, whose tooltips change with the locale.
  /// Lands on the dot's one node beside its label and its selected state.
  final String? identifier;

  const ColorSwatchDot({
    super.key,
    this.color,
    this.icon,
    this.tooltip,
    this.semanticLabel,
    required this.selected,
    this.onTap,
    this.onLongPress,
    this.identifier,
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
          width: selected
              ? _SwatchMetrics.selectedRingWidth
              : _SwatchMetrics.ringWidth,
        ),
      ),
      child: selected
          ? Icon(
              Icons.check_rounded,
              size: size * _SwatchMetrics.glyphShare,
              color: onFill,
            )
          : (icon == null
                ? null
                : Icon(
                    icon,
                    size: size * _SwatchMetrics.glyphShare,
                    color: onFill,
                  )),
    );
    if (tooltip != null) dot = Tooltip(message: tooltip!, child: dot);
    final footprint = size > tapTarget ? size : tapTarget;
    if (onTap == null && onLongPress == null) {
      final sample = SizedBox.square(
        dimension: footprint,
        child: Center(child: dot),
      );
      if (semanticLabel case final label?) {
        return Semantics(label: label, child: sample);
      }
      return sample;
    }
    final node = Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        customBorder: const CircleBorder(),
        child: SizedBox.square(dimension: footprint, child: Center(child: dot)),
      ),
    );
    if (identifier case final id?) {
      return AutomationId(identifier: id, child: node);
    }
    return node;
  }
}

/// Non-interactive swatch used as a leading avatar in list rows.
class ColorSwatchPreview extends StatelessWidget {
  final Color color;

  const ColorSwatchPreview({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _SwatchMetrics.previewDiameter,
      height: _SwatchMetrics.previewDiameter,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}
