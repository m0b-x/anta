part of '../form_rows.dart';

/// The width a one-line row leaves its trailing text: all of it but the gap
/// before it, so the text never overflows and the label takes what is left.
double _besideGap(double width) =>
    width > FormMetrics.gap ? width - FormMetrics.gap : 0;

class FormLabelValue extends StatelessWidget {
  final String label;
  final String? value;

  final Widget? valueLeading;
  final Color? labelColor;
  final Color? valueColor;
  final FontWeight labelWeight;

  /// False keeps the pair on one line whatever the width: the label
  /// ellipsizes on its line and the value — one line too — is never dropped
  /// under it. For a list that sizes its rows by kind (the overview's exact
  /// extents), where a row's height must never depend on its text.
  final bool wrap;

  const FormLabelValue({
    super.key,
    required this.label,
    this.value,
    this.valueLeading,
    this.labelColor,
    this.valueColor,
    this.labelWeight = FontWeight.w400,
    this.wrap = true,
  });

  /// The label's style — [FormMetrics.labelSize] on its 20 px line — as one
  /// definition, so a row that has to measure a label the way it is drawn
  /// (the stepper row, deciding whether its label fits beside the stepper)
  /// measures the same text.
  static TextStyle labelStyle(
    Color color, {
    FontWeight weight = FontWeight.w400,
  }) {
    return TextStyle(
      fontSize: FormMetrics.labelSize,
      height: FormMetrics.labelLineHeight / FormMetrics.labelSize,
      fontWeight: weight,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelText = Text(
      label,
      maxLines: wrap ? null : 1,
      overflow: wrap ? null : TextOverflow.ellipsis,
      style: labelStyle(
        labelColor ?? colorScheme.onSurface,
        weight: labelWeight,
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
      maxLines: wrap ? FormMetrics.valueMaxLines : 1,
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
    if (!wrap) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: FormMetrics.pairVerticalPadding,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Expanded(child: labelText),
              const SizedBox(width: FormMetrics.gap),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _besideGap(constraints.maxWidth),
                ),
                child: valueCell,
              ),
            ],
          ),
        ),
      );
    }
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

/// A glyph at a row's end in the chevron's place, on
/// [FormMetrics.trailingIconSize] — what a row wears when its end shows
/// what a tap does to the rows around it (a disclosure's ▾ / ▴, a fold
/// glyph) rather than that it opens somewhere, which is [FormChevron]'s.
class FormTrailingGlyph extends StatelessWidget {
  final IconData icon;
  final Color? color;

  const FormTrailingGlyph({super.key, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: FormMetrics.trailingIconSize,
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
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

/// The colour dot before a row's value — a `valueLeading:` — which is how
/// Icon & color reads back the colour an event or a template wears.
///
/// One widget on [FormMetrics.valueDotSize], so a colour dot is the same dot
/// on every row that shows one. Kept out of semantics: the row announces its
/// value, and a colour has no name to add to it.
class FormValueDot extends StatelessWidget {
  final Color color;

  const FormValueDot({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: FormMetrics.valueDotSize,
        height: FormMetrics.valueDotSize,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class FormTrailingButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  /// The glyph while [onPressed] is null, for a button on a ground other
  /// than the surface — the practice band's `primaryContainer` — where the
  /// theme's disabled grey, an `onSurface` tint, reads as a foreign colour.
  final Color? disabledColor;

  /// A `SemanticsIds` value for a button a device script has to hit by id —
  /// the Saved filter row's bookmark, a preset's ⋮ — whose tooltip changes
  /// with the locale and, for the bookmark, with the state.
  final String? identifier;

  /// Narrower than the square for a pair that has to fit a pinned row — the
  /// practice band's back and forward (D87) — where two full targets would
  /// wrap the line beside them; the height stays the 48 dp target.
  final double width;

  const FormTrailingButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.disabledColor,
    this.identifier,
    this.width = FormMetrics.trailingButtonSize,
  });

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: width,
      height: FormMetrics.trailingButtonSize,
      child: IconButton(
        tooltip: tooltip,
        iconSize: FormMetrics.trailingIconSize,
        color: color ?? Theme.of(context).colorScheme.outline,
        disabledColor: disabledColor,
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
