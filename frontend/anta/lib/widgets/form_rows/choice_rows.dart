part of '../form_rows.dart';

class FormSwitchRow extends FormDividedRow {
  final IconData? glyph;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? identifier;

  /// Every [subtitle] the row may show — each state's reading and the reason
  /// it is off. The subtitle sits in a slot as tall as the tallest, so the
  /// row is one height in every state and nothing under it moves when the
  /// state changes. Opting in (this or [onDisabledTap]) also keeps a
  /// disabled row's subtitle whole, as below.
  final List<String>? subtitleTemplates;

  /// Cuts [subtitle] with an ellipsis to the lines of the tallest of
  /// [subtitleTemplates], measured at the slot's width: the templates are
  /// then the fixed readings alone, and a reading that carries user text —
  /// a category's name — never makes the row taller than they do.
  final bool subtitleFitsTemplates;

  /// Run by a tap on the row while [onChanged] is null — the way to what
  /// would enable it (Sync & sharing, from a share switch that needs sync).
  /// Opting in (this or [subtitleTemplates]) dims only the glyph and the
  /// label of a disabled row: the subtitle says why the row is off and stays
  /// readable, the rule `FormPickerRow` and `FormCheckRow` follow, and the
  /// switch keeps Material's own disabled colours with nothing over them —
  /// at 38 % on top of those, an "on" read as off.
  ///
  /// While it runs, the disabled row is announced as what it is — an
  /// enabled button saying its label and its subtitle, with
  /// [onDisabledTapHint] — never as a disabled switch that acts on a tap.
  final VoidCallback? onDisabledTap;

  /// Where [onDisabledTap] goes ("Opens Sync & sharing"), the hint of the
  /// disabled row's node.
  final String? onDisabledTapHint;

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
    this.subtitleTemplates,
    this.subtitleFitsTemplates = false,
    this.onDisabledTap,
    this.onDisabledTapHint,
  });

  /// The most lines any of [templates] wraps to at [width], as a [Text] in
  /// [style] would draw it here — at least one.
  static int _templateLines(
    BuildContext context,
    List<String> templates,
    TextStyle style,
    double width,
  ) {
    var effective = DefaultTextStyle.of(context).style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    var most = 1;
    for (final template in templates) {
      final painter = TextPainter(
        text: TextSpan(text: template, style: effective),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout(maxWidth: width);
      most = math.max(most, painter.computeLineMetrics().length);
      painter.dispose();
    }
    return most;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final disabledTap = enabled ? null : onDisabledTap;
    final templates = subtitleTemplates;
    final twoLine = subtitle != null || templates != null;
    // The opted-in shape dims part by part; today's rows dim as a whole.
    final reasonStaysWhole = templates != null || onDisabledTap != null;
    Widget dim(Widget child) => enabled || !reasonStaysWhole
        ? child
        : Opacity(opacity: FormMetrics.disabledOpacity, child: child);
    final subtitleStyle = TextStyle(
      fontSize: FormMetrics.captionSize,
      height: FormMetrics.captionLineHeight / FormMetrics.captionSize,
      color: colorScheme.onSurfaceVariant,
    );
    final Widget? subtitleLine = subtitle == null
        ? null
        : Text(subtitle!, style: subtitleStyle);
    final text = twoLine
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              dim(
                Text(
                  label,
                  style: TextStyle(
                    fontSize: FormMetrics.labelSize,
                    height: 20 / FormMetrics.labelSize,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: RowMetrics.lineGap),
              if (templates == null)
                subtitleLine!
              else if (subtitleFitsTemplates)
                LayoutBuilder(
                  builder: (context, constraints) => FormCaptionSlot(
                    candidates: [
                      for (final template in templates)
                        Text(template, style: subtitleStyle),
                    ],
                    child: subtitle == null
                        ? const SizedBox.shrink()
                        : Text(
                            subtitle!,
                            style: subtitleStyle,
                            maxLines: _templateLines(
                              context,
                              templates,
                              subtitleStyle,
                              constraints.maxWidth,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                )
              else
                FormCaptionSlot(
                  candidates: [
                    for (final template in templates)
                      Text(template, style: subtitleStyle),
                  ],
                  child: subtitleLine ?? const SizedBox.shrink(),
                ),
            ],
          )
        : dim(FormLabelValue(label: label));
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
              dim(FormGlyph(icon: icon)),
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
    Widget well = Opacity(
      opacity: enabled || reasonStaysWhole ? 1 : FormMetrics.disabledOpacity,
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : onDisabledTap,
        child: row,
      ),
    );
    if (disabledTap != null) {
      well = Semantics(
        button: true,
        enabled: true,
        label: subtitle == null ? label : '$label\n$subtitle',
        hint: onDisabledTapHint,
        onTap: disabledTap,
        child: ExcludeSemantics(child: well),
      );
    }
    return MergeSemantics(
      child: identifier == null
          ? well
          : Semantics(identifier: identifier, child: well),
    );
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

  /// Null draws the row at the disabled opacity — all but its [caption],
  /// which says why and stays whole, as [FormPickerRow]'s does — with no tap
  /// and no ink.
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
    // A disabled row dims what it offers — the glyph, the label, the
    // control — and keeps its caption whole: the caption is what says why
    // the row is off, and at 38 % a held space's reason read at 1.94:1.
    Widget dim(Widget child) => enabled
        ? child
        : Opacity(opacity: FormMetrics.disabledOpacity, child: child);

    final labelText = dim(
      Text(
        label,
        style: TextStyle(
          fontSize: FormMetrics.labelSize,
          height: 20 / FormMetrics.labelSize,
          fontWeight: exclusive && checked ? FontWeight.w500 : FontWeight.w400,
          color: colorScheme.onSurface,
        ),
      ),
    );
    // The vertical air wraps the text alone: the 48 dp control slot beside it
    // would otherwise add the two-line padding to its own height and push a
    // 62 dp row to 66.
    final text = twoLine
        ? _CheckRowLines(
            label: labelText,
            caption: captionText,
            enabled: enabled,
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
              dim(avatar),
              const SizedBox(width: FormMetrics.gap),
            ] else if (glyph case final icon?) ...[
              dim(FormGlyph(icon: icon)),
              const SizedBox(width: FormMetrics.gap),
            ],
            Expanded(child: text),
            const SizedBox(width: FormMetrics.gap),
            dim(control),
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

/// [FormCheckRow]'s two lines — the label over its caption on the check
/// row's air — as one definition, so [FormPickerRow.checkRowShape] can never
/// drift from the row it matches.
class _CheckRowLines extends StatelessWidget {
  final Widget label;
  final String caption;
  final bool enabled;
  final int captionMaxLines;

  const _CheckRowLines({
    required this.label,
    required this.caption,
    required this.enabled,
    this.captionMaxLines = 2,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      vertical: RowMetrics.twoLinePadding.vertical / 2,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        label,
        const SizedBox(height: RowMetrics.lineGap),
        // Clamped like a value: a preset's description at 200 % German ran
        // four lines. A disabled row's caption is its reason, and a reason
        // cut short says nothing, so it wraps.
        FormCaption(text: caption, maxLines: enabled ? captionMaxLines : null),
      ],
    ),
  );
}
