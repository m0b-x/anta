import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import '../constants/calendar_colors.dart';
import '../constants/calendar_icons.dart';
import '../constants/fasting_calendar.dart';
import '../l10n/app_localizations.dart';
import '../models/fasting_appearance.dart';
import 'color_wheel_picker.dart';
import 'icon_picker_sheet.dart';

/// Per-tradition fasting look & feel editor: grid style, colour, icon and
/// where the day-panel row sits.
///
/// Applies **live** through [onChanged] rather than gating behind a Save —
/// every control here is a settings toggle whose effect the preview shows
/// immediately, and the caller (the settings page) persists on each change,
/// exactly like the switches around it. Dismissing therefore keeps the
/// edits, which is what a settings surface should do.
class FastingStyleSheet extends StatefulWidget {
  final FastingTradition tradition;
  final FastingTraditionStyle initialStyle;
  final ValueChanged<FastingTraditionStyle> onChanged;

  const FastingStyleSheet({
    super.key,
    required this.tradition,
    required this.initialStyle,
    required this.onChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required FastingTradition tradition,
    required FastingTraditionStyle initialStyle,
    required ValueChanged<FastingTraditionStyle> onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FastingStyleSheet(
        tradition: tradition,
        initialStyle: initialStyle,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<FastingStyleSheet> createState() => _FastingStyleSheetState();
}

class _FastingStyleSheetState extends State<FastingStyleSheet> {
  late FastingTraditionStyle _style;
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;

  /// Discrete choices (chips, swatches, icon) write through immediately;
  /// only per-keystroke text waits, so typing a description does not queue a
  /// settings write per character. Mirrors the agenda search field's
  /// debounce in `CalendarBottomPanel`.
  Timer? _textDebounce;
  static const Duration _textDebounceDelay = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    _style = widget.initialStyle;
    _titleController = TextEditingController(text: _style.titleOverride ?? '');
    _descriptionController = TextEditingController(
      text: _style.description ?? '',
    );
  }

  @override
  void dispose() {
    // Leaving inside the debounce window must not lose the last keystrokes.
    _flushPendingText();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _apply(FastingTraditionStyle next) {
    setState(() => _style = next);
    widget.onChanged(next);
  }

  /// Applies the current text fields, debounced. Keeps [_style] in sync
  /// immediately (so the preview follows every keystroke) while deferring
  /// the persist callback.
  void _applyTextDebounced() {
    setState(() {
      _style = _style.copyWith(
        titleOverride: _titleController.text,
        description: _descriptionController.text,
      );
    });
    _textDebounce?.cancel();
    _textDebounce = Timer(_textDebounceDelay, () => widget.onChanged(_style));
  }

  void _flushPendingText() {
    final timer = _textDebounce;
    if (timer == null || !timer.isActive) return;
    timer.cancel();
    widget.onChanged(_style);
  }

  Color get _color => _style.colorOr(CalendarColors.fasting);

  /// Resolved from the sheet's own draft rather than the engine, so the
  /// preview updates on the very first tap — the engine only learns about
  /// the change once the settings page has persisted and reconfigured it.
  IconData get _icon =>
      CalendarIcons.forKey(_style.iconKey) ??
      FastingCalendar.defaultIconOf(widget.tradition);

  Future<void> _pickIcon() async {
    final picked = await IconPickerSheet.show(
      context,
      tint: _color,
      initialKey: _style.iconKey,
    );
    if (picked == null || !mounted) return;
    _apply(_style.copyWith(iconKey: picked));
  }

  Future<void> _pickCustomColor() async {
    final picked = await ColorWheelDialog.show(
      context,
      initialColor: _style.colorValue,
    );
    if (picked == null || !mounted) return;
    _apply(_style.copyWith(colorValue: picked));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // `useSafeArea: true` guards the status bar, not the bottom gesture/nav
    // bar — same fix as `CategoryPickerSheet`.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return FractionallySizedBox(
      heightFactor: 0.86,
      child: Column(
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
                    FastingCalendar.traditionNameOf(widget.tradition, l10n),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomClearance),
              children: [
                _label(theme, l10n.fastingPreviewLabel),
                _Preview(
                  color: _color,
                  icon: _icon,
                  title:
                      _style.titleOverride ??
                      FastingCalendar.periodNameOf(_samplePeriod, l10n),
                  subtitle: FastingCalendar.regimeNameOf(_sampleRegime, l10n),
                  description: _style.description,
                  style: _style.style,
                ),
                _label(theme, l10n.fastingStyleTitle),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final style in FastingDisplayStyle.values)
                      ChoiceChip(
                        label: Text(FastingCalendar.styleNameOf(style, l10n)),
                        selected: _style.style == style,
                        onSelected: (selected) {
                          if (selected) _apply(_style.copyWith(style: style));
                        },
                      ),
                  ],
                ),
                _label(theme, l10n.eventColor),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    _ColorDot(
                      color: CalendarColors.fasting,
                      selected: _style.colorValue == null,
                      tooltip: l10n.fastingColorDefault,
                      onTap: () => _apply(_style.copyWith(clearColor: true)),
                    ),
                    for (final swatch in CalendarColors.swatchPalette)
                      _ColorDot(
                        color: Color(swatch),
                        selected: _style.colorValue == swatch,
                        onTap: () =>
                            _apply(_style.copyWith(colorValue: swatch)),
                      ),
                    _ColorDot(
                      icon: Icons.colorize_rounded,
                      selected: false,
                      onTap: _pickCustomColor,
                    ),
                  ],
                ),
                _label(theme, l10n.iconLabel),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _color.withValues(alpha: 0.18),
                      foregroundColor: _color,
                      child: Icon(_icon),
                    ),
                    title: Text(
                      _style.iconKey == null
                          ? l10n.fastingIconDefault
                          : l10n.iconCustom,
                    ),
                    subtitle: Text(l10n.pickIcon),
                    trailing: _style.iconKey == null
                        ? const Icon(Icons.chevron_right_rounded)
                        : IconButton(
                            tooltip: l10n.resetToDefault,
                            icon: const Icon(Icons.refresh_rounded),
                            onPressed: () =>
                                _apply(_style.copyWith(clearIcon: true)),
                          ),
                    onTap: _pickIcon,
                  ),
                ),
                _label(theme, l10n.fastingTitleOverrideLabel),
                TextField(
                  controller: _titleController,
                  maxLength: 120,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    // The computed name doubles as the hint, so an empty
                    // field visibly means "keep what the calendar works out".
                    hintText: FastingCalendar.periodNameOf(_samplePeriod, l10n),
                    counterText: '',
                    suffixIcon: _titleController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l10n.resetToDefault,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _titleController.clear();
                              _applyTextDebounced();
                            },
                          ),
                  ),
                  onChanged: (_) => _applyTextDebounced(),
                ),
                _label(theme, l10n.fastingDescriptionLabel),
                TextField(
                  controller: _descriptionController,
                  maxLength: 500,
                  maxLines: 3,
                  minLines: 2,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: l10n.fastingDescriptionHint,
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => _applyTextDebounced(),
                ),
                _label(theme, l10n.fastingPlacementTitle),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final placement in FastingRowPlacement.values)
                      ChoiceChip(
                        label: Text(
                          FastingCalendar.placementNameOf(placement, l10n),
                        ),
                        selected: _style.placement == placement,
                        onSelected: (selected) {
                          if (selected) {
                            _apply(_style.copyWith(placement: placement));
                          }
                        },
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    l10n.fastingPlacementHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A representative period/regime for the preview, picked per tradition so
  /// the sample reads like something that tradition actually observes.
  FastingPeriod get _samplePeriod => switch (widget.tradition) {
    FastingTradition.orthodox => FastingPeriod.greatLent,
    FastingTradition.catholic => FastingPeriod.lent,
    FastingTradition.muslim => FastingPeriod.ramadan,
    FastingTradition.jewish => FastingPeriod.yomKippur,
  };

  FastingRegime get _sampleRegime => switch (widget.tradition) {
    FastingTradition.orthodox => FastingRegime.fish,
    FastingTradition.catholic => FastingRegime.penitential,
    FastingTradition.muslim => FastingRegime.daylight,
    FastingTradition.jewish => FastingRegime.full,
  };

  Widget _label(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(0, AppSpacing.lg, 0, AppSpacing.sm),
    child: Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// Shows both halves of the configuration at once: a sample day cell
/// carrying the chosen grid treatment, next to the day-panel row it will
/// produce. Built from plain widgets rather than the real `CalendarDayCell`
/// / `DaySummaryPanel` because it only has to communicate the choice, and
/// wiring the real ones here would drag a `CalendarAppearance` and a whole
/// entry list into a settings sheet.
class _Preview extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? description;
  final FastingDisplayStyle style;

  const _Preview({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showsBar = style == FastingDisplayStyle.bar;
    final tinted = style == FastingDisplayStyle.tint;
    final strong = style == FastingDisplayStyle.strong;

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            // Sample day cell.
            Container(
              width: 44,
              height: 52,
              decoration: BoxDecoration(
                color: tinted ? color.withValues(alpha: 0.10) : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    '15',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: strong ? color : theme.colorScheme.onSurface,
                      fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                      height: 1.0,
                    ),
                  ),
                  const Spacer(),
                  if (showsBar)
                    Container(
                      width: 24,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Sample day-panel row.
            Expanded(
              child: Row(
                children: [
                  Container(width: 4, height: 40, color: color),
                  const SizedBox(width: AppSpacing.sm),
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: color.withValues(alpha: 0.16),
                    foregroundColor: color,
                    child: Icon(icon, size: 18),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        // Plain text on purpose: the real row renders this
                        // as clamped markdown, but a preview that pulled in
                        // the markdown builder would drag the whole engine
                        // into a settings sheet to show two lines.
                        if (description != null)
                          Text(
                            description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selectable colour swatch, mirroring the event editor's dots.
class _ColorDot extends StatelessWidget {
  final Color? color;
  final IconData? icon;
  final bool selected;
  final String? tooltip;
  final VoidCallback onTap;

  const _ColorDot({
    this.color,
    this.icon,
    this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = color ?? theme.colorScheme.surfaceContainerHighest;
    final onFill = color == null
        ? theme.colorScheme.onSurfaceVariant
        : (ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
              ? Colors.white
              : Colors.black87);
    Widget dot = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: selected
            ? Border.all(color: theme.colorScheme.onSurface, width: 2.5)
            : null,
      ),
      child: icon != null
          ? Icon(icon, size: 20, color: onFill)
          : (selected
                ? Icon(Icons.check_rounded, size: 20, color: onFill)
                : null),
    );
    if (tooltip != null) dot = Tooltip(message: tooltip!, child: dot);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: dot,
    );
  }
}
