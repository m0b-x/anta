import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';
import '../constants/row_metrics.dart';
import 'automation_id.dart';
import 'form_menu_item.dart';
import 'settings_reorder.dart';

export '../constants/form_metrics.dart';
export 'form_sheet_frame.dart';

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

/// One row of a rounded group, drawn on its own — the row-at-a-time twin of
/// [FormRowGroup] for a list a `Column` cannot hold: a reorderable list, a
/// sliver. Same tokens, same hairline rule (under every row but the last, at
/// the child's own indent), the corners on the first and last rows only, so
/// a run of shells reads as one group.
///
/// Only the end rows are a clipped [Material]. A middle row has no corner to
/// round, so it paints flat and hosts its ink on a transparent [Material] —
/// a clip path per row is what a long list would otherwise pay for corners
/// that are never drawn (the browser's row shell reasons the same way).
class FormRowShell extends StatelessWidget {
  final bool first;
  final bool last;

  /// The air below the last row, [FormRowGroup]'s `trailingGap`.
  final bool trailingGap;

  final Widget child;

  const FormRowShell({
    super.key,
    required this.first,
    required this.last,
    required this.child,
    this.trailingGap = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = Radius.circular(RowMetrics.groupRadius);
    final borderRadius = BorderRadius.vertical(
      top: first ? radius : Radius.zero,
      bottom: last ? radius : Radius.zero,
    );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        if (!last)
          Divider(
            height: 1,
            thickness: 1,
            indent: FormRowGroup.indentOf(child),
            endIndent: 0,
            color: colorScheme.rowDivider,
          ),
      ],
    );
    final shell = first || last
        ? Material(
            type: MaterialType.card,
            clipBehavior: Clip.antiAlias,
            color: colorScheme.rowGroup,
            borderRadius: borderRadius,
            child: body,
          )
        : ColoredBox(
            color: colorScheme.rowGroup,
            child: Material(type: MaterialType.transparency, child: body),
          );
    if (!last || !trailingGap) return shell;
    return Padding(
      padding: const EdgeInsets.only(bottom: RowMetrics.groupGap),
      child: shell,
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
        // Dart's `toUpperCase` is the simple case mapping, which leaves ß
        // alone: "Außerdem anzeigen" came out "AUßERDEM ANZEIGEN" on the
        // device. German capitals write it SS.
        text.toUpperCase().replaceAll('ß', 'SS'),
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

  /// A `SemanticsIds` value for a button a device script has to hit by id —
  /// the Saved filter row's bookmark, a preset's ⋮ — whose tooltip changes
  /// with the locale and, for the bookmark, with the state.
  final String? identifier;

  const FormTrailingButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.identifier,
  });

  @override
  Widget build(BuildContext context) {
    final button = SizedBox.square(
      dimension: FormMetrics.trailingButtonSize,
      child: IconButton(
        tooltip: tooltip,
        iconSize: FormMetrics.trailingIconSize,
        color: color ?? Theme.of(context).colorScheme.outline,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
    if (identifier case final id?) {
      return AutomationId(identifier: id, child: button);
    }
    return button;
  }
}

/// The drag handle of a row that can be lifted — the [FormCheckRow.handle]
/// slot: the shared [ReorderHandle] every reorderable list in the app wears,
/// centred in a [FormMetrics.dragHandleSlot] target, as one semantics node
/// carrying its accessible name and its id.
///
/// [label] is a semantics label and never a `Tooltip`: a tooltip brings a
/// long-press recogniser, and holding still on the handle before dragging
/// would let it win the arena and kill the reorder (the palette sheet's
/// note). [index] wires the handle to the enclosing reorderable list; while
/// [enabled] is false the handle greys **in place** and drags nothing, so a
/// list that is locked (a search is live) keeps every row where it was.
class FormDragHandle extends StatelessWidget {
  final int? index;
  final bool enabled;
  final String label;
  final String? identifier;

  const FormDragHandle({
    super.key,
    this.index,
    this.enabled = true,
    required this.label,
    this.identifier,
  });

  @override
  Widget build(BuildContext context) {
    final handle = SizedBox.square(
      dimension: FormMetrics.dragHandleSlot,
      child: Center(
        child: Semantics(
          label: label,
          child: ReorderHandle(index: enabled ? index : null, enabled: enabled),
        ),
      ),
    );
    if (identifier case final id?) {
      return AutomationId(identifier: id, child: handle);
    }
    return MergeSemantics(child: handle);
  }
}

class FormPickerRow extends FormDividedRow {
  /// A 40 dp widget — an `EventAvatar` — standing where the glyph would,
  /// which gives the row the title row's 56 dp shape and, unless
  /// [dividerIndent] says otherwise, its divider indent. Wins over [glyph].
  final Widget? leading;
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

  /// False draws the row at the disabled opacity with no ink and no tap and
  /// marks its one node disabled — a control the form has switched off, the
  /// shape `FormMenuRow` takes without a handler. A read row (the next
  /// occurrences) passes `onTap: null` instead and stays fully drawn, so a
  /// value the user cannot act on never looks like one they may not.
  final bool enabled;

  final double? _dividerIndent;

  const FormPickerRow({
    super.key,
    this.leading,
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
    this.enabled = true,
    double? dividerIndent,
  }) : _dividerIndent = dividerIndent;

  /// The glyph indent unless a caller sets one; the title indent under a
  /// [leading] widget, which is wider than a glyph.
  @override
  double get dividerIndent =>
      _dividerIndent ??
      (leading != null
          ? FormMetrics.dividerIndentTitle
          : FormMetrics.dividerIndentGlyph);

  @override
  Widget build(BuildContext context) {
    final button = trailingButton;
    final avatar = leading;
    final captionText = caption;
    final tap = enabled ? onTap : null;
    final pair = FormLabelValue(
      label: label,
      value: value,
      valueLeading: valueLeading,
      labelColor: labelColor,
      valueColor: valueColor,
    );
    // Under a leading widget the caption joins the label in one column — the
    // check row's two-line shape — so the avatar centres against both lines
    // instead of sitting on the first with the caption hanging under it.
    // Under a glyph the caption stays a line below the pair: the glyph names
    // the field and belongs on the label line.
    final stacked = avatar != null && captionText != null;
    final text = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              pair,
              FormCaption(
                text: captionText,
                maxLines: 2,
                padding: const EdgeInsets.only(
                  bottom: FormMetrics.pairVerticalPadding,
                ),
              ),
            ],
          )
        : pair;
    final content = Row(
      children: [
        if (avatar != null) ...[
          SizedBox.square(
            dimension: FormMetrics.rowLeadingSize,
            child: Center(child: avatar),
          ),
          const SizedBox(width: FormMetrics.gap),
        ] else if (glyph case final icon?) ...[
          FormGlyph(icon: icon, color: glyphColor),
          const SizedBox(width: FormMetrics.gap),
        ],
        Expanded(child: text),
        if (button == null && showChevron) ...[
          const SizedBox(width: FormMetrics.gap),
          const FormChevron(),
        ],
      ],
    );
    final leftInset = avatar == null && glyph == null && subRow
        ? FormMetrics.subRowInset
        : RowMetrics.groupInset;
    final rightInset = button == null ? FormMetrics.rowEndPadding : 0.0;
    // The width of whatever stands before the label, so the caption below
    // can start where the label starts.
    final double leadingColumn = avatar != null
        ? FormMetrics.rowLeadingSize + FormMetrics.gap
        : glyph != null
        ? FormMetrics.glyphSize + FormMetrics.gap
        : 0;
    final line = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: stacked
            ? FormMetrics.twoLineRowMinHeight
            : avatar != null
            ? FormMetrics.titleRowMinHeight
            : FormMetrics.rowMinHeight,
      ),
      child: Padding(
        padding: EdgeInsets.only(left: leftInset, right: rightInset),
        child: content,
      ),
    );
    // The caption starts where the label starts, past the glyph column, so
    // it reads as the value's continuation and not as a second row.
    final body = captionText == null || stacked
        ? line
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              line,
              FormCaption(
                text: captionText,
                padding: EdgeInsets.only(
                  left: leftInset + leadingColumn,
                  right: rightInset,
                  bottom: FormMetrics.rowCaptionBottomPadding,
                ),
              ),
            ],
          );
    Widget well = InkWell(onTap: tap, child: body);
    if (semanticsLabel != null) {
      well = Semantics(
        label: semanticsLabel,
        button: true,
        enabled: tap != null,
        onTap: tap,
        child: ExcludeSemantics(child: well),
      );
    } else if (!enabled) {
      // Inside the merge below, so the flag lands on the row's one node
      // beside its id and its label.
      well = Semantics(enabled: false, child: well);
    }
    if (!enabled) {
      well = Opacity(opacity: FormMetrics.disabledOpacity, child: well);
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

/// The multi-select twin of [FormRadioRow]: a row of a value list that ticks
/// and un-ticks — a priority, a trait, a category — or, with [exclusive], the
/// radio shape with a leading avatar the plain radio row has no slot for (a
/// saved filter, "No filter").
///
/// The whole row is one target and one announcement. The control sits in a
/// 48 dp slot flush with the row's end, so a checkbox centres where a
/// two-target row's button does; with a [trailingButton] the exclusive check
/// shrinks to its glyph and the button takes the slot, the shape the preset
/// rows wear. A [caption] is the row's own second line (what a preset
/// filters, "Hidden" on an archived category), never help text.
class FormCheckRow extends FormDividedRow {
  /// A 40 dp widget — an `EventAvatar` — that stands where the glyph would.
  /// Wins over [glyph].
  final Widget? leading;
  final IconData? glyph;
  final String label;
  final String? caption;
  final bool checked;

  /// Null draws the row at the disabled opacity with no tap and no ink.
  final ValueChanged<bool>? onChanged;

  /// Radio semantics and the check glyph instead of a checkbox: one row of
  /// the list is on at a time, and tapping it is a pick, not a toggle.
  final bool exclusive;
  final String? identifier;
  final FormTrailingButton? trailingButton;

  /// A [FormDragHandle] in a [FormMetrics.dragHandleSlot] target flush with
  /// the row's start — a third target beside the row's own node and its
  /// [trailingButton], the shape a reorderable list's rows wear. It takes
  /// the glyph's column: the text starts at [FormMetrics.dividerIndentGlyph]
  /// and the hairline indents to it.
  final Widget? handle;

  const FormCheckRow({
    super.key,
    this.leading,
    this.glyph,
    required this.label,
    this.caption,
    required this.checked,
    required this.onChanged,
    this.exclusive = false,
    this.identifier,
    this.trailingButton,
    this.handle,
  });

  @override
  double get dividerIndent {
    if (leading != null) return FormMetrics.dividerIndentTitle;
    if (glyph != null || handle != null) return FormMetrics.dividerIndentGlyph;
    return FormMetrics.dividerIndentPlain;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final captionText = caption;
    final twoLine = captionText != null;
    final button = trailingButton;
    void toggle() => onChanged!(!checked);

    final labelText = Text(
      label,
      style: TextStyle(
        fontSize: FormMetrics.labelSize,
        height: 20 / FormMetrics.labelSize,
        fontWeight: exclusive && checked ? FontWeight.w500 : FontWeight.w400,
        color: colorScheme.onSurface,
      ),
    );
    // The vertical air wraps the text alone: the 48 dp control slot beside it
    // would otherwise add the two-line padding to its own height and push a
    // 62 dp row to 66.
    final text = twoLine
        ? Padding(
            padding: EdgeInsets.symmetric(
              vertical: RowMetrics.twoLinePadding.vertical / 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                labelText,
                const SizedBox(height: RowMetrics.lineGap),
                // Clamped like a value: a preset's description at 200 %
                // German ran four lines.
                Text(
                  captionText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: FormMetrics.captionSize,
                    height: 18 / FormMetrics.captionSize,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(
              vertical: FormMetrics.pairVerticalPadding,
            ),
            child: labelText,
          );

    final Widget control;
    if (!exclusive) {
      control = Checkbox(
        value: checked,
        onChanged: enabled ? (_) => toggle() : null,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
      );
    } else {
      final glyphBox = SizedBox.square(
        dimension: FormMetrics.trailingIconSize,
        child: checked
            ? Icon(
                Icons.check_rounded,
                size: FormMetrics.trailingIconSize,
                color: colorScheme.primary,
              )
            : null,
      );
      control = button == null
          ? SizedBox.square(
              dimension: FormMetrics.trailingButtonSize,
              child: Center(child: glyphBox),
            )
          : glyphBox;
    }

    final minHeight = twoLine
        ? FormMetrics.twoLineRowMinHeight
        : leading != null
        ? FormMetrics.titleRowMinHeight
        : FormMetrics.rowMinHeight;
    final dragHandle = handle;
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        // Past a handle the text sits at the glyph column, 4 dp after the
        // 48 dp slot; without one, at the group inset like every row.
        padding: EdgeInsets.only(
          left: dragHandle == null
              ? RowMetrics.groupInset
              : FormMetrics.dividerIndentGlyph - FormMetrics.dragHandleSlot,
        ),
        child: Row(
          children: [
            if (leading case final avatar?) ...[
              avatar,
              const SizedBox(width: FormMetrics.gap),
            ] else if (glyph case final icon?) ...[
              FormGlyph(icon: icon),
              const SizedBox(width: FormMetrics.gap),
            ],
            Expanded(child: text),
            const SizedBox(width: FormMetrics.gap),
            control,
          ],
        ),
      ),
    );
    Widget well = InkWell(onTap: enabled ? toggle : null, child: row);
    if (exclusive) {
      // The checkbox announces its own state; the radio shape has to say it
      // here, as `Radio` does — checked, in a mutually exclusive group.
      well = Semantics(
        inMutuallyExclusiveGroup: true,
        checked: checked,
        enabled: enabled,
        child: well,
      );
    }
    well = Opacity(
      opacity: enabled ? 1 : FormMetrics.disabledOpacity,
      child: well,
    );
    if (identifier case final id?) {
      well = AutomationId(identifier: id, child: well);
    } else {
      well = MergeSemantics(child: well);
    }
    if (button == null && dragHandle == null) return well;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ?dragHandle,
        Expanded(child: well),
        ?button,
      ],
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

  /// Clamps the caption like a value, ellipsizing past the limit — the
  /// second line of a row with a leading widget, where a template's summary
  /// at 200 % German would otherwise run four lines. Null wraps freely.
  final int? maxLines;

  const FormCaption({
    super.key,
    required this.text,
    this.error = false,
    this.padding = EdgeInsets.zero,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: FormMetrics.captionSize,
          height: 18 / FormMetrics.captionSize,
          color: error ? colorScheme.error : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A search field as the first row of a group — a searchable sub-sheet's
/// first row, a filler's pinned one. It stands in for `SettingsSearchField`
/// only inside a form group; the settings pages keep theirs.
///
/// Never autofocused: a sheet that opens with the keyboard up hides the list
/// it exists to show. The clear button is a sibling target that always has a
/// slot, so the field's width never changes as text comes and goes.
class FormSearchRow extends FormDividedRow {
  final TextEditingController controller;
  final String hint;

  /// The clear button's tooltip — passed in like every other label here, so
  /// the primitives stay free of the localizations.
  final String clearTooltip;
  final ValueChanged<String> onChanged;

  /// Lands on the field's own text-field node, which is what a device script
  /// types into by id.
  final String? identifier;

  const FormSearchRow({
    super.key,
    required this.controller,
    required this.hint,
    required this.clearTooltip,
    required this.onChanged,
    this.identifier,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontSize: FormMetrics.labelSize,
      height: 20 / FormMetrics.labelSize,
      color: colorScheme.onSurface,
    );
    Widget field = TextField(
      controller: controller,
      autofocus: false,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      enableSuggestions: false,
      style: textStyle,
      // Collapsed, but padded to the row's height: a bare collapsed field is
      // its 20 px line, and a thumb landing in the row's other 28 px focused
      // nothing.
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        contentPadding: FormMetrics.searchFieldPadding,
        hintText: hint,
        // `onSurfaceVariant`, never `outline`: the latter is under AA for
        // text on `surface`.
        hintStyle: textStyle.copyWith(color: colorScheme.onSurfaceVariant),
      ),
      // A tap on the rows below drops the keyboard, so the list being ticked
      // is not left half-covered by it.
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      onChanged: onChanged,
    );
    if (identifier case final id?) {
      field = AutomationId(identifier: id, child: field);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.only(left: RowMetrics.groupInset),
        child: Row(
          children: [
            const FormGlyph(icon: Icons.search_rounded),
            const SizedBox(width: FormMetrics.gap),
            Expanded(child: field),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => controller.text.isEmpty
                  ? const SizedBox.square(
                      dimension: FormMetrics.trailingButtonSize,
                    )
                  : FormTrailingButton(
                      icon: Icons.close_rounded,
                      tooltip: clearTooltip,
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class FormMenuItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  /// A `SemanticsIds` value for an item a device script picks by id.
  final String? identifier;

  const FormMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.identifier,
  });
}

/// `label … value ›` opening a menu of [items] — the editor's Priority and
/// Day rail, the filter sheet's Repeat and Time of day.
///
/// A popup route in the header menus' anatomy ([FormMenuChoiceItem]), never a
/// `MenuAnchor`, whose items expose no semantics nodes on iOS. The menu is
/// right-aligned with the group and opens under the row, or above it when
/// there is no room below; focus is dropped before it opens, or the route's
/// return would hand focus back to a field and raise the keyboard.
class FormMenuRow<T> extends FormDividedRow {
  final IconData glyph;
  final String label;
  final String value;
  final T selected;
  final List<FormMenuItem<T>> items;

  /// Null draws the row disabled — 38 %, no ink, no tap, its node marked so
  /// — and the menu never opens: the agenda's Fasting rows while the fasting
  /// calendar is off, kept in place with its stored value rather than
  /// dropped, so nothing under it moves between two openings.
  final ValueChanged<T>? onSelected;
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
    // A `Builder` so the tap has the row's own render box to anchor to.
    return Builder(
      builder: (rowContext) => FormPickerRow(
        glyph: glyph,
        label: label,
        value: value,
        identifier: identifier,
        enabled: onSelected != null,
        onTap: () => _open(rowContext),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final select = onSelected;
    if (select == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final colorScheme = Theme.of(context).colorScheme;
    final picked = await showMenu<T>(
      context: context,
      positionBuilder: (_, constraints) => formMenuPosition(
        context,
        constraints,
        menuHeight: formMenuHeight(items.length),
      ),
      color: colorScheme.menuSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FormMetrics.menuRadius),
      ),
      menuPadding: FormMetrics.menuPadding,
      // `menuWidth` is the floor; a label that needs more widens the menu up
      // to the cap rather than breaking mid-word, which it did at 200 % in
      // German. The right edge stays on the group's whatever the width.
      constraints: BoxConstraints(
        minWidth: menuWidth,
        maxWidth: FormMetrics.menuMaxWidth,
      ),
      items: [
        for (final item in items)
          FormMenuChoiceItem<T>(
            value: item.value,
            checked: item.value == selected,
            child: FormMenuItemRow(
              identifier: item.identifier,
              icon: item.icon,
              label: item.label,
              checked: item.value == selected,
            ),
          ),
      ],
    );
    if (picked == null) return;
    select(picked);
  }
}
