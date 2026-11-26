part of '../form_rows.dart';

class FormActionRow extends FormDividedRow {
  final IconData glyph;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
  final String? identifier;

  /// Whether what a [FormActionRow.disclosure] row folds is open; null for
  /// an action.
  final bool? expanded;

  /// What a screen reader hears in place of [label] — "2 more in Gym",
  /// where the label alone does not say which group grows.
  final String? semanticsLabel;

  /// The glyph trails the label instead of leading it.
  final bool _trailingGlyph;

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
  }) : expanded = null,
       semanticsLabel = null,
       _trailingGlyph = false;

  /// `label ▾` — a row that shows or hides the rows of a group it ends ("2
  /// more", "Show less"): the label at the title column, under the rows'
  /// text it extends, the glyph at the row's end in the chevron's place, so
  /// it reads as the group's continuation rather than as one more action.
  const FormActionRow.disclosure({
    super.key,
    required this.glyph,
    required this.label,
    required this.onTap,
    this.expanded,
    this.semanticsLabel,
    this.identifier,
  }) : destructive = false,
       dividerIndent = FormMetrics.dividerIndentTitle,
       _trailingGlyph = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = destructive ? colorScheme.error : colorScheme.primary;
    final enabled = onTap != null;
    final text = Expanded(
      child: FormLabelValue(
        label: label,
        labelColor: color,
        labelWeight: FontWeight.w500,
      ),
    );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
      child: Padding(
        padding: _trailingGlyph
            ? const EdgeInsets.only(
                left: FormMetrics.dividerIndentTitle,
                right: FormMetrics.rowEndPadding,
              )
            : const EdgeInsets.only(
                left: RowMetrics.groupInset,
                right: FormMetrics.rowEndPadding,
              ),
        child: Row(
          children: _trailingGlyph
              ? [
                  text,
                  const SizedBox(width: FormMetrics.gap),
                  FormTrailingGlyph(icon: glyph, color: color),
                ]
              : [
                  FormGlyph(icon: glyph, color: color),
                  const SizedBox(width: FormMetrics.gap),
                  text,
                ],
        ),
      ),
    );
    if (_trailingGlyph) {
      // One node carrying the spoken label and the fold state; the visible
      // label alone would not say which group it opens.
      return Semantics(
        container: true,
        button: true,
        enabled: enabled,
        expanded: expanded,
        label: semanticsLabel ?? label,
        identifier: identifier,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Opacity(
            opacity: enabled ? 1 : FormMetrics.disabledOpacity,
            child: InkWell(onTap: onTap, child: row),
          ),
        ),
      );
    }
    // An ink well with no tap is nothing to a screen reader: the row faded
    // to 38 % and was read out as plain text, with no word that it is an
    // action or that it is off. Said here, and inside the merge below, so
    // the role and the state land on the row's one node beside its label.
    final well = Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : FormMetrics.disabledOpacity,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
    if (identifier case final id?) {
      return AutomationId(identifier: id, child: well);
    }
    return well;
  }
}
