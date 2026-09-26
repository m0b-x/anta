import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';
import '../constants/row_metrics.dart';
import 'automation_id.dart';

export '../constants/form_metrics.dart';

abstract class FormDividedRow extends StatelessWidget {
  const FormDividedRow({super.key});

  double get dividerIndent;
}

class FormRowGroup extends StatelessWidget {
  final List<Widget> children;
  final bool trailingGap;

  const FormRowGroup({
    super.key,
    required this.children,
    this.trailingGap = true,
  });

  static double indentOf(Widget row) => row is FormDividedRow
      ? row.dividerIndent
      : FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(
          Divider(
            height: 1,
            thickness: 1,
            indent: indentOf(children[i]),
            endIndent: 0,
            color: colorScheme.rowDivider,
          ),
        );
      }
    }
    return Padding(
      padding: EdgeInsets.only(bottom: trailingGap ? RowMetrics.groupGap : 0),
      child: Material(
        type: MaterialType.card,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.rowGroup,
        borderRadius: BorderRadius.circular(RowMetrics.groupRadius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

class FormSectionLabel extends StatelessWidget {
  final String text;

  const FormSectionLabel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RowMetrics.sectionLabelInset,
        0,
        RowMetrics.sectionLabelInset,
        RowMetrics.sectionLabelBottomPadding,
      ),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: RowMetrics.sectionLabelFontSize,
          height: 14 / RowMetrics.sectionLabelFontSize,
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: RowMetrics.sectionLabelLetterSpacing,
          fontWeight: RowMetrics.sectionLabelFontWeight,
        ),
      ),
    );
  }
}

class FormSheetHandle extends StatelessWidget {
  final bool showHandle;

  const FormSheetHandle({super.key, this.showHandle = true});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: FormMetrics.handleStripHeight,
      child: showHandle
          ? Center(
              child: Container(
                width: FormMetrics.handleWidth,
                height: FormMetrics.handleHeight,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(
                    FormMetrics.handleHeight / 2,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class FormSheetHeader extends StatelessWidget {
  final IconData leadingIcon;
  final String leadingTooltip;
  final VoidCallback onLeading;
  final String title;
  final Widget trailing;

  final double trailingInset;

  final ValueListenable<bool>? scrolled;

  final String? leadingIdentifier;

  const FormSheetHeader({
    super.key,
    required this.leadingIcon,
    required this.leadingTooltip,
    required this.onLeading,
    required this.title,
    required this.trailing,
    this.trailingInset = 12,
    this.scrolled,
    this.leadingIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    Widget leading = IconButton(
      tooltip: leadingTooltip,
      icon: Icon(leadingIcon),
      color: colorScheme.onSurfaceVariant,
      onPressed: onLeading,
    );
    if (leadingIdentifier case final id?) {
      leading = AutomationId(identifier: id, child: leading);
    }
    final row = SizedBox(
      height: FormMetrics.headerHeight,
      child: Padding(
        padding: EdgeInsets.only(left: 4, right: trailingInset),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              leading,
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: FormMetrics.headerTitleSize,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      constraints.maxWidth * FormMetrics.headerActionMaxShare,
                ),
                child: trailing,
              ),
            ],
          ),
        ),
      ),
    );
    final listenable = scrolled;
    if (listenable == null) return row;
    return Stack(
      children: [
        row,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ValueListenableBuilder<bool>(
            valueListenable: listenable,
            builder: (context, isScrolled, _) => IgnorePointer(
              child: Container(
                height: 1,
                color: isScrolled ? colorScheme.rowDivider : Colors.transparent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The header's trailing text action: a sub-sheet's Done, the detail
/// sheet's Edit. One widget rather than three hand-rolled `TextButton`s so
/// the sheets in the detail loop share one size, one weight and one inset;
/// the filled button stays the editor's alone, because it is the commit.
class FormHeaderTextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final String? identifier;

  const FormHeaderTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.identifier,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.primary,
        minimumSize: const Size(0, FormMetrics.headerHeight),
        padding: FormMetrics.headerActionPadding,
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontSize: FormMetrics.headerActionFontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    if (identifier case final id?) {
      return AutomationId(identifier: id, child: button);
    }
    return button;
  }
}

class FormLabelValue extends StatelessWidget {
  final String label;
  final String? value;

  final Widget? valueLeading;
  final Color? labelColor;
  final Color? valueColor;
  final FontWeight labelWeight;

  const FormLabelValue({
    super.key,
    required this.label,
    this.value,
    this.valueLeading,
    this.labelColor,
    this.valueColor,
    this.labelWeight = FontWeight.w400,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelText = Text(
      label,
      style: TextStyle(
        fontSize: FormMetrics.labelSize,
        height: 20 / FormMetrics.labelSize,
        fontWeight: labelWeight,
        color: labelColor ?? colorScheme.onSurface,
      ),
    );
    final valueString = value;
    if (valueString == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: FormMetrics.pairVerticalPadding,
        ),
        child: labelText,
      );
    }
    final valueText = Text(
      valueString,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: FormMetrics.labelSize,
        height: 20 / FormMetrics.labelSize,
        fontWeight: FontWeight.w400,
        color: valueColor ?? colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final leading = valueLeading;
    final valueCell = leading == null
        ? valueText
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 8),
              Flexible(child: valueText),
            ],
          );
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: FormMetrics.pairVerticalPadding,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: FormMetrics.gap,
          runSpacing: FormMetrics.pairRunSpacing,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: labelText,
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: valueCell,
            ),
          ],
        ),
      ),
    );
  }
}

class FormGlyph extends StatelessWidget {
  final IconData icon;
  final Color? color;

  const FormGlyph({super.key, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: FormMetrics.glyphSize,
      color: color ?? Theme.of(context).colorScheme.primary,
    );
  }
}

class FormChevron extends StatelessWidget {
  const FormChevron({super.key});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.chevron_right,
      size: FormMetrics.chevronSize,
      color: Theme.of(context).colorScheme.outline,
    );
  }
}

class FormTrailingButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  const FormTrailingButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: FormMetrics.trailingButtonSize,
      child: IconButton(
        tooltip: tooltip,
        iconSize: FormMetrics.trailingIconSize,
        color: color ?? Theme.of(context).colorScheme.outline,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}

class FormPickerRow extends FormDividedRow {
  final IconData? glyph;
  final Color? glyphColor;
  final String label;
  final String? value;
  final Widget? valueLeading;
  final Color? labelColor;
  final Color? valueColor;
  final VoidCallback? onTap;
  final FormTrailingButton? trailingButton;
  final bool showChevron;
  final String? semanticsLabel;
  final String? identifier;
  final bool subRow;

  /// A line of the row's own data under the pair — the dates after the
  /// next occurrence, never help text. It lives inside the row's ink well
  /// and semantics node, so the row stays one target and one announcement.
  final String? caption;

  @override
  final double dividerIndent;

  const FormPickerRow({
    super.key,
    this.glyph,
    this.glyphColor,
    required this.label,
    this.value,
    this.valueLeading,
    this.labelColor,
    this.valueColor,
    required this.onTap,
    this.trailingButton,
    this.showChevron = true,
    this.semanticsLabel,
    this.identifier,
    this.subRow = false,
    this.caption,
    this.dividerIndent = FormMetrics.dividerIndentGlyph,
  });

  @override
  Widget build(BuildContext context) {
    final button = trailingButton;
    final pair = FormLabelValue(
      label: label,
      value: value,
      valueLeading: valueLeading,
      labelColor: labelColor,
      valueColor: valueColor,
    );
    final content = Row(
      children: [
        if (glyph case final icon?) ...[
          FormGlyph(icon: icon, color: glyphColor),
          const SizedBox(width: FormMetrics.gap),
        ],
        Expanded(child: pair),
        if (button == null && showChevron) ...[
          const SizedBox(width: FormMetrics.gap),
          const FormChevron(),
        ],
      ],
    );
    final leftInset = glyph == null && subRow
        ? FormMetrics.subRowInset
        : RowMetrics.groupInset;
    final rightInset = button == null ? FormMetrics.rowEndPadding : 0.0;
    final line = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
      child: Padding(
        padding: EdgeInsets.only(left: leftInset, right: rightInset),
        child: content,
      ),
    );
    final captionText = caption;
    // The caption starts where the label starts, past the glyph column, so
    // it reads as the value's continuation and not as a second row.
    final body = captionText == null
        ? line
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              line,
              FormCaption(
                text: captionText,
                padding: EdgeInsets.only(
                  left:
                      leftInset +
                      (glyph == null
                          ? 0
                          : FormMetrics.glyphSize + FormMetrics.gap),
                  right: rightInset,
                  bottom: FormMetrics.rowCaptionBottomPadding,
                ),
              ),
            ],
          );
    Widget well = InkWell(onTap: onTap, child: body);
    if (semanticsLabel != null) {
      well = Semantics(
        label: semanticsLabel,
        button: true,
        enabled: onTap != null,
        onTap: onTap,
        child: ExcludeSemantics(child: well),
      );
    }
    if (identifier case final id?) {
      well = AutomationId(identifier: id, child: well);
    } else {
      // A row is one announcement — label, value, caption — whether or not
      // a driver needs an id on it (`AutomationId` merges for the ones that
      // do). The trailing button below stays a sibling, so a two-target row
      // keeps its second node.
      well = MergeSemantics(child: well);
    }
    if (button == null) return well;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: well),
        button,
      ],
    );
  }
}

class FormSwitchRow extends FormDividedRow {
  final IconData? glyph;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? identifier;

  @override
  final double dividerIndent;

  const FormSwitchRow({
    super.key,
    this.glyph,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.identifier,
    this.dividerIndent = FormMetrics.dividerIndentGlyph,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final twoLine = subtitle != null;
    final text = twoLine
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: FormMetrics.labelSize,
                  height: 20 / FormMetrics.labelSize,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: RowMetrics.lineGap),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: FormMetrics.captionSize,
                  height: 18 / FormMetrics.captionSize,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          )
        : FormLabelValue(label: label);
    final row = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: twoLine
            ? FormMetrics.twoLineRowMinHeight
            : FormMetrics.rowMinHeight,
      ),
      child: Padding(
        padding: twoLine
            ? RowMetrics.twoLinePadding
            : const EdgeInsets.only(
                left: RowMetrics.groupInset,
                right: FormMetrics.rowEndPadding,
              ),
        child: Row(
          children: [
            if (glyph case final icon?) ...[
              FormGlyph(icon: icon),
              const SizedBox(width: FormMetrics.gap),
            ],
            Expanded(child: text),
            const SizedBox(width: FormMetrics.gap),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
    final well = Opacity(
      opacity: enabled ? 1 : FormMetrics.disabledOpacity,
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: row,
      ),
    );
    return MergeSemantics(
      child: identifier == null
          ? well
          : Semantics(identifier: identifier, child: well),
    );
  }
}

class FormActionRow extends FormDividedRow {
  final IconData glyph;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
  final String? identifier;

  @override
  final double dividerIndent;

  const FormActionRow({
    super.key,
    required this.glyph,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.identifier,
    this.dividerIndent = FormMetrics.dividerIndentGlyph,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = destructive ? colorScheme.error : colorScheme.primary;
    final enabled = onTap != null;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.only(
          left: RowMetrics.groupInset,
          right: FormMetrics.rowEndPadding,
        ),
        child: Row(
          children: [
            FormGlyph(icon: glyph, color: color),
            const SizedBox(width: FormMetrics.gap),
            Expanded(
              child: FormLabelValue(
                label: label,
                labelColor: color,
                labelWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
    final well = Opacity(
      opacity: enabled ? 1 : FormMetrics.disabledOpacity,
      child: InkWell(onTap: onTap, child: row),
    );
    if (identifier case final id?) {
      return AutomationId(identifier: id, child: well);
    }
    return well;
  }
}

class FormRadioRow extends FormDividedRow {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const FormRadioRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentPlain;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: FormMetrics.rowMinHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.only(
              left: RowMetrics.groupInset,
              right: 14,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: FormMetrics.pairVerticalPadding,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: FormMetrics.labelSize,
                        height: 20 / FormMetrics.labelSize,
                        fontWeight: selected
                            ? FontWeight.w500
                            : FontWeight.w400,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: FormMetrics.gap),
                SizedBox.square(
                  dimension: FormMetrics.trailingIconSize,
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: FormMetrics.trailingIconSize,
                          color: colorScheme.primary,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FormChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double tapTarget;

  /// A `SemanticsIds` value for a chip a device script has to hit by id —
  /// the presence pair, whose labels change with the locale.
  final String? identifier;

  const FormChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tapTarget = FormMetrics.chipTapTarget,
    this.identifier,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(FormMetrics.chipRadius),
      side: BorderSide(
        color: selected ? Colors.transparent : colorScheme.outlineVariant,
      ),
    );
    final chip = Semantics(
      button: true,
      selected: selected,
      child: _TapTargetPadding(
        minHeight: tapTarget,
        child: Material(
          color: selected ? colorScheme.secondaryContainer : Colors.transparent,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: FormMetrics.chipHeight,
              child: Padding(
                padding: FormMetrics.chipPadding,
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: FormMetrics.chipFontSize,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (identifier case final id?) {
      return AutomationId(identifier: id, child: chip);
    }
    return chip;
  }
}

class _TapTargetPadding extends SingleChildRenderObjectWidget {
  final double minHeight;

  const _TapTargetPadding({required this.minHeight, required Widget child})
    : super(child: child);

  @override
  _RenderTapTargetPadding createRenderObject(BuildContext context) =>
      _RenderTapTargetPadding(minHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTapTargetPadding renderObject,
  ) {
    renderObject.minHeight = minHeight;
  }
}

class _RenderTapTargetPadding extends RenderShiftedBox {
  double _minHeight;

  _RenderTapTargetPadding(this._minHeight, [RenderBox? child]) : super(child);

  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(0, _minHeight));
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    final height = child.size.height > _minHeight
        ? child.size.height
        : _minHeight;
    size = constraints.constrain(Size(child.size.width, height));
    final parentData = child.parentData! as BoxParentData;
    parentData.offset = Offset(0, (size.height - child.size.height) / 2);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTest(result, position: position)) return true;
    final child = this.child;
    if (child == null || !size.contains(position)) return false;
    final center = child.size.center(Offset.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(center),
      position: center,
      hitTest: (result, position) => child.hitTest(result, position: center),
    );
  }
}

class FormChipRow extends FormDividedRow {
  final List<Widget> chips;
  final Widget? caption;

  /// With a [label] the row stands on its own — `[glyph] label … chips` on
  /// one line, the chips dropping under the label when the two do not fit
  /// (the `FormLabelValue` wrap) — instead of being the sub-row a switch
  /// reveals. The detail sheet's presence pair is the one such row.
  final IconData? glyph;
  final String? label;

  const FormChipRow({
    super.key,
    required this.chips,
    this.caption,
    this.glyph,
    this.label,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    final chipWrap = Wrap(
      spacing: FormMetrics.chipSpacing,
      runSpacing: 0,
      children: chips,
    );
    final labelText = label;
    if (labelText == null) {
      return Padding(
        padding: FormMetrics.chipRowPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            chipWrap,
            if (caption case final text?) ...[const SizedBox(height: 8), text],
          ],
        ),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    final icon = glyph;
    final labelIndent = icon == null
        ? 0.0
        : FormMetrics.glyphSize + FormMetrics.gap;
    final line = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.only(
          left: RowMetrics.groupInset,
          right: FormMetrics.rowEndPadding,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              FormGlyph(icon: icon),
              const SizedBox(width: FormMetrics.gap),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: FormMetrics.gap,
                  runSpacing: 0,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: FormMetrics.pairVerticalPadding,
                        ),
                        child: Text(
                          labelText,
                          style: TextStyle(
                            fontSize: FormMetrics.labelSize,
                            height: 20 / FormMetrics.labelSize,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                      ),
                      child: chipWrap,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final captionWidget = caption;
    if (captionWidget == null) return line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        line,
        Padding(
          padding: EdgeInsets.only(
            left: RowMetrics.groupInset + labelIndent,
            right: RowMetrics.groupInset,
            bottom: FormMetrics.rowCaptionBottomPadding,
          ),
          child: captionWidget,
        ),
      ],
    );
  }
}

class FormCaption extends StatelessWidget {
  final String text;
  final bool error;
  final EdgeInsets padding;

  const FormCaption({
    super.key,
    required this.text,
    this.error = false,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Text(
        text,
        style: TextStyle(
          fontSize: FormMetrics.captionSize,
          height: 18 / FormMetrics.captionSize,
          color: error ? colorScheme.error : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class FormMenuItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const FormMenuItem({required this.value, required this.label, this.icon});
}

class FormMenuRow<T> extends FormDividedRow {
  final IconData glyph;
  final String label;
  final String value;
  final T selected;
  final List<FormMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final double menuWidth;
  final String? identifier;

  const FormMenuRow({
    super.key,
    required this.glyph,
    required this.label,
    required this.value,
    required this.selected,
    required this.items,
    required this.onSelected,
    required this.menuWidth,
    this.identifier,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return MenuAnchor(
      alignmentOffset: Offset(-menuWidth, 0),
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomEnd,
        backgroundColor: WidgetStatePropertyAll(colorScheme.menuSurface),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FormMetrics.menuRadius),
          ),
        ),
        padding: const WidgetStatePropertyAll(FormMetrics.menuPadding),
        minimumSize: WidgetStatePropertyAll(Size(menuWidth, 0)),
        maximumSize: WidgetStatePropertyAll(Size(menuWidth, double.infinity)),
      ),
      menuChildren: [
        for (final item in items)
          MergeSemantics(
            child: Semantics(
              selected: item.value == selected,
              child: MenuItemButton(
                onPressed: () => onSelected(item.value),
                style: MenuItemButton.styleFrom(
                  minimumSize: Size(menuWidth, FormMetrics.menuRowHeight),
                  padding: const EdgeInsets.symmetric(
                    horizontal: RowMetrics.groupInset,
                  ),
                ),
                leadingIcon: item.icon == null
                    ? null
                    : Icon(
                        item.icon,
                        size: FormMetrics.menuIconSize,
                        color: colorScheme.onSurfaceVariant,
                      ),
                trailingIcon: item.value == selected
                    ? Icon(
                        Icons.check_rounded,
                        size: FormMetrics.menuIconSize,
                        color: colorScheme.primary,
                      )
                    : const SizedBox(width: FormMetrics.menuIconSize),
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: FormMetrics.labelSize,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => FormPickerRow(
        glyph: glyph,
        label: label,
        value: value,
        identifier: identifier,
        onTap: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            FocusManager.instance.primaryFocus?.unfocus();
            controller.open();
          }
        },
      ),
    );
  }
}
