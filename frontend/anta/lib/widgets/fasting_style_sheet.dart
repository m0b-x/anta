import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_colors.dart';
import '../constants/calendar_icons.dart';
import '../constants/fasting_calendar.dart';
import '../constants/fasting_style_limits.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/fasting_appearance.dart';
import '../utils/markdown_plain_text.dart';
import 'app_dialogs.dart';
import 'color_swatch_picker.dart';
import 'event_avatar.dart';
import 'event_description_sheet.dart';
import 'form_rows.dart';
import 'icon_picker_sheet.dart';

/// Per-tradition fasting look & feel editor: grid style, colour, icon, where
/// the day-panel row sits, and the row's own title and description — a
/// sub-sheet of the UI language (Tier 3, D15, D18, D19) led by the preview.
///
/// Applies **live** through [onChanged] rather than gating behind a Save —
/// every control here is a settings toggle whose effect the preview shows
/// immediately, and the caller (the settings page) persists on each change,
/// exactly like the switches around it. Dismissing therefore keeps the
/// edits, which is what a settings surface should do. The two texts are
/// written by the dialog and the sheet that edit them, on confirm, so there
/// is nothing pending to flush when the sheet closes.
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
        child: FastingStyleSheet(
          tradition: tradition,
          initialStyle: initialStyle,
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  State<FastingStyleSheet> createState() => _FastingStyleSheetState();
}

class _FastingStyleSheetState extends State<FastingStyleSheet> {
  late FastingTraditionStyle _style;
  final FormHeaderHairline _hairline = FormHeaderHairline();

  @override
  void initState() {
    super.initState();
    _style = widget.initialStyle;
  }

  @override
  void dispose() {
    _hairline.dispose();
    super.dispose();
  }

  void _apply(FastingTraditionStyle next) {
    setState(() => _style = next);
    widget.onChanged(next);
  }

  Color get _color => _style.colorOr(CalendarColors.fasting);

  /// Resolved from the sheet's own draft rather than the engine, so the
  /// preview updates on the very first tap — the engine only learns about
  /// the change once the settings page has persisted and reconfigured it.
  IconData get _icon =>
      CalendarIcons.forKey(_style.iconKey) ??
      FastingCalendar.defaultIconOf(widget.tradition);

  /// Dropped before every picker, dialog and sheet this one opens — the
  /// language's rule for every opener. Nothing in this sheet holds the
  /// focus of its own, but the route under a returning modal hands focus and
  /// the keyboard back to whatever held it, and the rule is cheaper kept than
  /// re-derived when a field is added here.
  void _blur() => FocusManager.instance.primaryFocus?.unfocus();

  Future<void> _pickIcon() async {
    _blur();
    final picked = await IconPickerSheet.show(
      context,
      tint: _color,
      initialKey: _style.iconKey,
    );
    if (picked == null || !mounted) return;
    _apply(_style.copyWith(iconKey: picked));
  }

  /// The title in the one dialog layer (the folder and note rename
  /// precedent). A confirmed value writes at once — a blank one is the clear,
  /// `copyWith` storing it as null; a cancelled dialog writes nothing.
  Future<void> _editTitle() async {
    _blur();
    final l10n = AppLocalizations.of(context)!;
    final value = await AppDialogs.textInput(
      context,
      title: l10n.fastingTitleOverrideLabel,
      // The computed name doubles as the hint, so an empty field visibly
      // means "keep what the calendar works out".
      hintText: FastingCalendar.periodNameOf(_samplePeriod, l10n),
      initialValue: _style.titleOverride ?? '',
      maxLength: kFastingTitleMaxLength,
    );
    if (value == null || !mounted) return;
    _apply(_style.copyWith(titleOverride: value));
  }

  /// The description in the sheet every description is written in (the
  /// template form's precedent), with the fasting budget. Done writes at
  /// once; a cancelled sheet, and a Done that changed nothing, write nothing.
  Future<void> _editDescription() async {
    _blur();
    final l10n = AppLocalizations.of(context)!;
    final initial = _style.description ?? '';
    final text = await EventDescriptionSheet.show(
      context,
      initialText: initial,
      heading: FastingCalendar.traditionNameOf(widget.tradition, l10n),
      limit: kFastingDescriptionMaxLength,
      grandfatheredLength: initial.length,
    );
    if (text == null || !mounted || text == initial) return;
    _apply(_style.copyWith(description: text));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view, never the whole body — the rule every calendar sheet
    // follows (`sheet_bottom_clearance_test.dart`): the box is a fixed
    // fraction of the screen, and a tall IME would collapse a padded Column
    // to nothing.
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
          leadingIdentifier: SemanticsIds.fastingStyleClose,
          onLeading: () => Navigator.of(context).pop(),
          title: FastingCalendar.traditionNameOf(widget.tradition, l10n),
          scrolled: _hairline.scrolled,
          trailingInset: FormMetrics.headerActionInset,
          // Nothing to confirm: every control has already written.
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormSectionLabel(text: l10n.fastingPreviewLabel),
                  FormRowGroup(children: [_buildPreview(l10n)]),
                  FormRowGroup(
                    children: [_buildGridRow(l10n), _buildPlacementRow(l10n)],
                  ),
                  FormRowGroup(
                    children: [_buildIconRow(l10n), _buildColorRow(l10n)],
                  ),
                  FormRowGroup(
                    trailingGap: false,
                    children: [
                      _buildTitleRow(l10n),
                      _buildDescriptionRow(l10n),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(AppLocalizations l10n) {
    return _Preview(
      color: _color,
      icon: _icon,
      title:
          _style.titleOverride ??
          FastingCalendar.periodNameOf(_samplePeriod, l10n),
      subtitle: FastingCalendar.regimeNameOf(_sampleRegime, l10n),
      description: _style.description,
      style: _style.style,
    );
  }

  Widget _buildGridRow(AppLocalizations l10n) {
    return FormMenuRow<FastingDisplayStyle>(
      glyph: Icons.grid_on_rounded,
      label: l10n.fastingStyleTitle,
      value: FastingCalendar.styleNameOf(_style.style, l10n),
      selected: _style.style,
      menuWidth: FormMetrics.menuWidth,
      identifier: SemanticsIds.fastingStyleGrid,
      items: [
        for (final style in FastingDisplayStyle.values)
          FormMenuItem(
            value: style,
            label: FastingCalendar.styleNameOf(style, l10n),
            identifier: _gridItemId(style),
          ),
      ],
      onSelected: (style) => _apply(_style.copyWith(style: style)),
    );
  }

  /// No sentence under it (D15): a row that reads "After holidays" says
  /// where the row sits.
  Widget _buildPlacementRow(AppLocalizations l10n) {
    return FormMenuRow<FastingRowPlacement>(
      glyph: Icons.low_priority_rounded,
      label: l10n.fastingPlacementTitle,
      value: FastingCalendar.placementNameOf(_style.placement, l10n),
      selected: _style.placement,
      menuWidth: FormMetrics.menuWidth,
      identifier: SemanticsIds.fastingStylePlacement,
      items: [
        for (final placement in FastingRowPlacement.values)
          FormMenuItem(
            value: placement,
            label: FastingCalendar.placementNameOf(placement, l10n),
            identifier: _placementItemId(placement),
          ),
      ],
      onSelected: (placement) => _apply(_style.copyWith(placement: placement)),
    );
  }

  /// The reset is a second target beside the row (the Look sheet's Icon row)
  /// and exists only while there is an icon to reset: the row's value says
  /// "Default icon" in its place.
  Widget _buildIconRow(AppLocalizations l10n) {
    final custom = _style.iconKey != null;
    return FormPickerRow(
      glyph: Icons.emoji_symbols_rounded,
      label: l10n.iconLabel,
      value: custom ? l10n.iconCustom : l10n.fastingIconDefault,
      onTap: _pickIcon,
      identifier: SemanticsIds.fastingStyleIcon,
      trailingButton: custom
          ? FormTrailingButton(
              icon: Icons.refresh_rounded,
              tooltip: l10n.resetToDefault,
              identifier: SemanticsIds.fastingStyleIconReset,
              onPressed: () => _apply(_style.copyWith(clearIcon: true)),
            )
          : null,
    );
  }

  /// The default dot stands for the shared fasting violet and draws its
  /// glyph, so it is told apart from a swatch of the same colour beside it.
  Widget _buildColorRow(AppLocalizations l10n) {
    return FormSwatchRow(
      identifier: SemanticsIds.swatchRow,
      child: ColorSwatchPicker(
        value: _style.colorValue,
        onChanged: (value) => _apply(
          value == null
              ? _style.copyWith(clearColor: true)
              : _style.copyWith(colorValue: value),
        ),
        spacing: FormMetrics.swatchSpacing,
        collapsible: false,
        defaultOption: ColorSwatchDefault(
          color: CalendarColors.fasting,
          tooltip: l10n.fastingColorDefault,
        ),
      ),
    );
  }

  Widget _buildTitleRow(AppLocalizations l10n) {
    final override = _style.titleOverride;
    return FormPickerRow(
      glyph: Icons.title_rounded,
      label: l10n.fastingTitleOverrideLabel,
      value: override ?? l10n.eventLookDefault,
      onTap: _editTitle,
      identifier: SemanticsIds.fastingStyleTitle,
      trailingButton: override == null
          ? null
          : FormTrailingButton(
              icon: Icons.close_rounded,
              tooltip: l10n.resetToDefault,
              identifier: SemanticsIds.fastingStyleTitleClear,
              // A blank override is the clear: `copyWith` stores it as null.
              onPressed: () => _apply(_style.copyWith(titleOverride: '')),
            ),
    );
  }

  /// The description read back as the row's own line with its markdown
  /// markers dropped, the template form's rule, clamped at the value's two
  /// lines so a 500-character text stays a row; the hint stands in its place
  /// while there is none. Money is off in every description, so a `$`-led
  /// line is read as the text it was typed as.
  Widget _buildDescriptionRow(AppLocalizations l10n) {
    final description = _style.description;
    return FormPickerRow(
      glyph: Icons.notes_rounded,
      label: l10n.fastingDescriptionLabel,
      caption: description == null
          ? l10n.fastingDescriptionHint
          : MarkdownPlainText.strip(description, money: false),
      captionMaxLines: FormMetrics.valueMaxLines,
      onTap: _editDescription,
      identifier: SemanticsIds.fastingStyleDescription,
    );
  }

  static String _gridItemId(FastingDisplayStyle style) => switch (style) {
    FastingDisplayStyle.tint => SemanticsIds.fastingStyleGridTint,
    FastingDisplayStyle.bar => SemanticsIds.fastingStyleGridBar,
    FastingDisplayStyle.strong => SemanticsIds.fastingStyleGridStrong,
    FastingDisplayStyle.none => SemanticsIds.fastingStyleGridNone,
  };

  static String _placementItemId(FastingRowPlacement placement) =>
      switch (placement) {
        FastingRowPlacement.first => SemanticsIds.fastingStylePlacementFirst,
        FastingRowPlacement.beforeHolidays =>
          SemanticsIds.fastingStylePlacementBeforeHolidays,
        FastingRowPlacement.afterHolidays =>
          SemanticsIds.fastingStylePlacementAfterHolidays,
        FastingRowPlacement.last => SemanticsIds.fastingStylePlacementLast,
      };

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
}

/// The sample's own geometry: a day cell beside the day-panel row it
/// produces, both in miniature. Named here rather than read off the row
/// metrics because none of it is a form row's — the cell is the grid's chip,
/// the stripe and the avatar are the panel row's at a smaller size than
/// `EventAvatar` draws — and a preview that borrowed a row's gap or a
/// chevron's size would drift with them for no reason the eye could see.
abstract final class _PreviewMetrics {
  static const String sampleDay = '15';
  static const double cellWidth = 44;
  static const double cellHeight = 52;
  static const double cellRadius = 10;
  static const double cellTopInset = 6;

  /// The day number's line is its glyph height alone, as the grid's cell
  /// draws it.
  static const double dayNumberLineHeight = 1;
  static const double barWidth = 24;
  static const double barHeight = 4;
  static const double barBottomInset = 6;
  static const double barRadius = 3;
  static const double stripeWidth = 4;
  static const double stripeHeight = 40;
  static const double avatarRadius = 16;
  static const double avatarIconSize = 18;

  /// Between the stripe, the avatar and the text of the sample row.
  static const double partGap = 8;
}

/// Shows both halves of the configuration at once: a sample day cell
/// carrying the chosen grid treatment, next to the day-panel row it will
/// produce. Built from plain widgets rather than the real `CalendarDayCell`
/// / `DaySummaryPanel` because it only has to communicate the choice, and
/// wiring the real ones here would drag a `CalendarAppearance` and a whole
/// entry list into a settings sheet. Drawn straight on its group (D19): no
/// card, no tinted ground of its own.
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
    final colorScheme = theme.colorScheme;
    final showsBar = style == FastingDisplayStyle.bar;
    final tinted = style == FastingDisplayStyle.tint;
    final strong = style == FastingDisplayStyle.strong;
    final captionStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    // The cell is a drawing of a grid cell, so it says nothing; the row
    // reads as one line, like every row of a group.
    final cell = ExcludeSemantics(
      child: Container(
        width: _PreviewMetrics.cellWidth,
        height: _PreviewMetrics.cellHeight,
        decoration: BoxDecoration(
          color: tinted
              ? color.withValues(alpha: CalendarColors.fastingTintAlpha)
              : null,
          borderRadius: BorderRadius.circular(_PreviewMetrics.cellRadius),
        ),
        child: Column(
          children: [
            const SizedBox(height: _PreviewMetrics.cellTopInset),
            // The number takes what the bar leaves and is fitted into it
            // (D19): a text scale that makes the digits wider than the cell
            // shrinks them instead of wrapping "15" into "1" over "5", so
            // this one fixed box in the sheet cannot overflow at any scale.
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: Text(
                  _PreviewMetrics.sampleDay,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: strong ? color : colorScheme.onSurface,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                    height: _PreviewMetrics.dayNumberLineHeight,
                  ),
                ),
              ),
            ),
            if (showsBar)
              Container(
                width: _PreviewMetrics.barWidth,
                height: _PreviewMetrics.barHeight,
                margin: const EdgeInsets.only(
                  bottom: _PreviewMetrics.barBottomInset,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(
                    _PreviewMetrics.barRadius,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final row = Row(
      children: [
        Container(
          width: _PreviewMetrics.stripeWidth,
          height: _PreviewMetrics.stripeHeight,
          color: color,
        ),
        const SizedBox(width: _PreviewMetrics.partGap),
        CircleAvatar(
          radius: _PreviewMetrics.avatarRadius,
          backgroundColor: color.withValues(alpha: EventAvatar.backgroundAlpha),
          foregroundColor: color,
          child: Icon(icon, size: _PreviewMetrics.avatarIconSize),
        ),
        const SizedBox(width: _PreviewMetrics.partGap),
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
                style: captionStyle,
              ),
              // Plain text on purpose: the real row renders this as clamped
              // markdown, but a preview that pulled in the markdown builder
              // would drag the whole engine into a settings sheet to show
              // two lines.
              if (description case final text?)
                Text(
                  text,
                  maxLines: FormMetrics.valueMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: captionStyle,
                ),
            ],
          ),
        ),
      ],
    );

    return MergeSemantics(
      child: Padding(
        padding: RowMetrics.twoLinePadding,
        child: Row(
          children: [
            cell,
            const SizedBox(width: FormMetrics.gap),
            Expanded(child: row),
          ],
        ),
      ),
    );
  }
}
