part of '../form_rows.dart';

class FormChip extends StatelessWidget {
  final String label;
  final bool selected;

  /// Null draws the chip at the disabled opacity with no ink and no tap, its
  /// node marked disabled — a choice that is off the table for now (Tonight
  /// once 21:00 has passed) keeps its place, so the chips beside it do not
  /// close up under the finger.
  final VoidCallback? onTap;
  final double tapTarget;

  /// A `SemanticsIds` value for a chip a device script has to hit by id —
  /// the presence pair, whose labels change with the locale.
  final String? identifier;

  /// A glyph before the label, in its ink, for a chip that is a prop rather
  /// than a choice — a guide stage's "Fill it in" with the practice mark.
  final IconData? glyph;

  const FormChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tapTarget = FormMetrics.chipTapTarget,
    this.identifier,
    this.glyph,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ink = selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant;
    final Widget text = Text(
      label,
      style: TextStyle(
        fontSize: FormMetrics.chipFontSize,
        fontWeight: FontWeight.w500,
        color: ink,
      ),
    );
    final leading = glyph;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(FormMetrics.chipRadius),
      side: BorderSide(
        color: selected ? Colors.transparent : colorScheme.outlineVariant,
      ),
    );
    final enabled = onTap != null;
    final Widget body = Material(
      color: selected ? colorScheme.secondaryContainer : Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // A minimum, never a fixed height: past 160 % the label's line is
        // taller than the chip, and a fixed box cut its descenders. Up to
        // there the chip is its 32 dp; past it the 48 dp target around the
        // chip still has room at 200 %, so no row moves.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: FormMetrics.chipHeight),
          child: Padding(
            padding: FormMetrics.chipPadding,
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: leading == null
                  ? text
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          leading,
                          size: FormMetrics.chipGlyphSize,
                          color: ink,
                        ),
                        const SizedBox(width: FormMetrics.chipGlyphGap),
                        Flexible(child: text),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
    final chip = Semantics(
      button: true,
      selected: selected,
      // Only a disabled chip says so: an enabled one keeps the node it has
      // always had, with no enabled state on it.
      enabled: enabled ? null : false,
      child: TapTargetPadding(
        minHeight: tapTarget,
        child: enabled
            ? body
            : Opacity(opacity: FormMetrics.disabledOpacity, child: body),
      ),
    );
    if (identifier case final id?) {
      return AutomationId(identifier: id, child: chip);
    }
    return chip;
  }
}

/// A chip body smaller than the touch target keeps the target without
/// growing the body: the box is at least [minHeight] tall, the child sits
/// centred in it, and a tap anywhere in the band lands on the child.
class TapTargetPadding extends SingleChildRenderObjectWidget {
  final double minHeight;

  const TapTargetPadding({
    super.key,
    required this.minHeight,
    required Widget child,
  }) : super(child: child);

  @override
  RenderTapTargetPadding createRenderObject(BuildContext context) =>
      RenderTapTargetPadding(minHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTapTargetPadding renderObject,
  ) {
    renderObject.minHeight = minHeight;
  }
}

class RenderTapTargetPadding extends RenderShiftedBox {
  double _minHeight;

  RenderTapTargetPadding(this._minHeight, [RenderBox? child]) : super(child);

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
  /// reveals: the detail sheet's presence pair, an alert's Type.
  final IconData? glyph;
  final String? label;

  /// Read only without a [label]. True is the sub-row a switch reveals, set
  /// in under the switch's label. False is a chip row that stands alone — a
  /// custom offset's units, the quick alarm's presets: it starts at the
  /// group's inset, is one 48 dp row per run of chips and draws its hairline
  /// from the group's edge.
  final bool indented;

  const FormChipRow({
    super.key,
    required this.chips,
    this.caption,
    this.glyph,
    this.label,
    this.indented = true,
  });

  @override
  double get dividerIndent => label == null && !indented
      ? FormMetrics.dividerIndentPlain
      : FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    final chipWrap = Wrap(
      spacing: FormMetrics.chipSpacing,
      runSpacing: 0,
      children: chips,
    );
    final labelText = label;
    if (labelText == null && indented) {
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
    final icon = labelText == null ? null : glyph;
    final labelIndent = icon == null
        ? 0.0
        : FormMetrics.glyphSize + FormMetrics.gap;
    // A standalone row is the labelled row without its label: the same line
    // at the group's inset, with no air of its own because every chip already
    // carries a 48 dp target.
    final line = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.only(
          left: RowMetrics.groupInset,
          right: FormMetrics.rowEndPadding,
        ),
        child: labelText == null
            ? chipWrap
            : Row(
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
