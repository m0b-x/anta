part of '../form_rows.dart';

/// `[leading] label / caption / ▬▬▬──── [trailing]` — a row that shows a
/// thing's share of a total beside its name: the report's category headers,
/// where the meter says how this category compares with the busiest one and
/// the caption carries the numbers.
///
/// The caption shrinks to fit one line inside a box of its one-line height
/// (`AgendaPeriodNav`'s count rule) instead of truncating or wrapping, so a
/// refold that lengthens the numbers never changes the row's height under
/// the finger; a sentence caption takes a fixed [captionLines] for the same
/// reason (the report's goal rows). The meter is drawn only when [fraction]
/// is set; a fill above zero is never thinner than it is tall, so a sliver
/// of a share still shows, and zero draws the bare track.
///
/// One node: the row's words are spelled out in [semanticsLabel] (the
/// caption's figures read badly aloud), with [expanded] for a row that
/// folds what is under it.
class FormMeterRow extends FormDividedRow {
  /// A 40 dp widget — an `EventAvatar` — in the title row's leading box.
  final Widget leading;
  final String label;

  /// The row's numbers, on one line that shrinks rather than cuts.
  final String? caption;

  /// The share the meter fills, clamped to 0 to 1, a non-finite value read
  /// as 0; null draws no meter.
  final double? fraction;

  /// The fill's colour; the scheme's `primary` when null.
  final Color? meterColor;

  /// A share 0 to 1 of the track where an upright bar marks a reference
  /// value — last year's share on the year in review's Balance card —
  /// clamped like [fraction] and kept inside the track at both ends, its
  /// ring included. It overhangs the meter into the air around it, so it
  /// never changes the row's height. Only on a meter: a marker without
  /// [fraction] asserts.
  final double? marker;

  /// A widget in the meter's place, after [FormMetrics.meterGap] at the text
  /// column's width — the year in review's twelve-month strip — so a chart
  /// row keeps every meter row's geometry. No constant knows its height: the
  /// chart sizes itself, and its height sets the row's. A row draws a meter
  /// or a chart, never both, so [fraction] must be null; [meterColor] and
  /// [marker] have nothing to draw on.
  final Widget? chart;

  /// A trailing glyph — the fold chevron — after [FormMetrics.gap].
  final Widget? trailing;
  final VoidCallback? onTap;

  /// What a screen reader hears; [label] when null.
  final String? semanticsLabel;

  /// Whether what the row folds is open; null for a row that folds nothing.
  final bool? expanded;
  final String? identifier;

  /// The caption's line count, for a caption that is a sentence rather than
  /// a run of figures — a goal's read-back ("31 h of 40 · 9 h left this
  /// week") cannot shrink into one line at 1.3. The caption then wraps to at
  /// most this many lines at full width, and the row is always as tall as
  /// [captionLines] caption lines, centred: the caller decides the count
  /// from templates, never from the value, so a refold that lengthens the
  /// caption never changes the row's height. Null keeps the one-line slot
  /// that shrinks.
  final int? captionLines;

  /// A glyph at the label line's end, after [FormMetrics.gap] — a goal's
  /// state. Beside the label rather than in a reserved trailing column: the
  /// column's width came out of every name and broke "Measurement" at 1.3
  /// and German names at 2.0 mid-word.
  final Widget? labelTrailing;

  /// What stands in for [leading] from [RowMetrics.compactLeadingTextScale]
  /// up, in a [RowMetrics.glyphSize] box — the category's glyph for its
  /// avatar. The 18 dp it frees is what keeps a built-in name whole at 2.0
  /// on a small phone; decided by the scale, never by the name, so a row
  /// never changes shape with its data. Null keeps [leading] at every
  /// scale.
  final Widget? compactLeading;

  const FormMeterRow({
    super.key,
    required this.leading,
    required this.label,
    this.caption,
    this.fraction,
    this.meterColor,
    this.trailing,
    required this.onTap,
    this.semanticsLabel,
    this.expanded,
    this.identifier,
    this.captionLines,
    this.labelTrailing,
    this.compactLeading,
    this.marker,
    this.chart,
  }) : assert(
         fraction == null || chart == null,
         'a meter row draws a meter or a chart, not both',
       ),
       assert(
         marker == null || fraction != null,
         'a marker sits on a meter: it needs a fraction',
       );

  @override
  double get dividerIndent => FormMetrics.dividerIndentTitle;

  @override
  double dividerIndentIn(BuildContext context) => _compact(context)
      ? RowMetrics.dividerIndentWithGlyph
      : FormMetrics.dividerIndentTitle;

  /// Whether [scaler] is past [RowMetrics.compactLeadingTextScale], where a
  /// row with a [compactLeading] narrows its leading box. Public so a caller
  /// that measures the row's text width ahead of it (the report's goal
  /// captions) reads the same rule rather than a copy.
  static bool isCompact(TextScaler scaler) =>
      scaler.scale(RowMetrics.titleFontSize) / RowMetrics.titleFontSize >=
      RowMetrics.compactLeadingTextScale;

  /// Whether [compactLeading] replaces [leading] at [context]'s text scale.
  bool _compact(BuildContext context) =>
      compactLeading != null && isCompact(MediaQuery.textScalerOf(context));

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final captionText = caption;
    final share = fraction;
    final graphic = chart;
    final lines = captionLines;
    final captionStyle = TextStyle(
      fontSize: FormMetrics.captionSize,
      height: FormMetrics.captionLineHeight / FormMetrics.captionSize,
      color: colorScheme.onSurfaceVariant,
    );
    Widget labelLine = Text(
      label,
      style: TextStyle(
        fontSize: FormMetrics.labelSize,
        height: FormMetrics.labelLineHeight / FormMetrics.labelSize,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurface,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    if (labelTrailing case final end?) {
      labelLine = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: labelLine),
          const SizedBox(width: FormMetrics.gap),
          SizedBox(
            height: scaler.scale(FormMetrics.labelLineHeight),
            child: Center(child: end),
          ),
        ],
      );
    }
    final words = [
      labelLine,
      if (captionText != null && lines != null)
        Text(
          captionText,
          style: captionStyle,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
        )
      else if (captionText != null)
        SizedBox(
          height: scaler.scale(FormMetrics.captionLineHeight),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              captionText,
              style: captionStyle,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
    ];
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Under a chart no constant knows the row's height, so the reserved
        // caption lines are held around the words themselves, centred.
        if (graphic != null && lines != null)
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  scaler.scale(FormMetrics.labelLineHeight) +
                  scaler.scale(FormMetrics.captionLineHeight) * lines,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: words,
            ),
          )
        else
          ...words,
        if (share != null) ...[
          const SizedBox(height: FormMetrics.meterGap),
          _FormMeter(
            fraction: share,
            color: meterColor ?? colorScheme.primary,
            track: colorScheme.rowDivider,
            marker: marker,
            markerColor: colorScheme.onSurfaceVariant,
            markerRing: colorScheme.rowGroup,
          ),
        ],
        if (graphic != null) ...[
          const SizedBox(height: FormMetrics.meterGap),
          SizedBox(width: double.infinity, child: graphic),
        ],
      ],
    );
    // A caption shorter than its lines leaves the spare one as air around
    // the centred content, never as a hole under it.
    final minHeight = lines == null || graphic != null
        ? FormMetrics.twoLineRowMinHeight
        : math.max(
            FormMetrics.twoLineRowMinHeight,
            RowMetrics.twoLinePadding.vertical +
                scaler.scale(FormMetrics.labelLineHeight) +
                scaler.scale(FormMetrics.captionLineHeight) * lines +
                (share == null
                    ? 0
                    : FormMetrics.meterGap + FormMetrics.meterHeight),
          );
    final compact = _compact(context);
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: EdgeInsets.only(
          left: RowMetrics.groupInset,
          right: FormMetrics.rowEndPadding,
          top: RowMetrics.twoLinePadding.top,
          bottom: RowMetrics.twoLinePadding.bottom,
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: compact
                  ? RowMetrics.glyphSize
                  : FormMetrics.rowLeadingSize,
              child: Center(child: compact ? compactLeading : leading),
            ),
            const SizedBox(width: FormMetrics.gap),
            Expanded(child: text),
            if (trailing case final end?) ...[
              const SizedBox(width: FormMetrics.gap),
              end,
            ],
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      button: onTap != null,
      expanded: expanded,
      label: semanticsLabel ?? label,
      identifier: identifier,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

/// [FormMeterRow]'s track and fill, sized to the text column's width, with
/// its marker painted past the track's 4 dp box.
class _FormMeter extends StatelessWidget {
  const _FormMeter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.marker,
    required this.markerColor,
    required this.markerRing,
  });

  final double fraction;
  final Color color;
  final Color track;
  final double? marker;
  final Color markerColor;
  final Color markerRing;

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(FormMetrics.meterHeight / 2),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: FormMetrics.meterHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // A share of an empty total (0 / 0) arrives as NaN: nothing to fill.
          final share = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
          final meter = DecoratedBox(
            decoration: BoxDecoration(color: track, borderRadius: _radius),
            child: share <= 0
                ? const SizedBox.expand()
                : Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SizedBox(
                      width: math.min(
                        width,
                        math.max(FormMetrics.meterHeight, share * width),
                      ),
                      height: FormMetrics.meterHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: _radius,
                        ),
                      ),
                    ),
                  ),
          );
          final at = marker;
          if (at == null) return meter;
          const ring = FormMetrics.meterMarkerRing;
          const barWidth = FormMetrics.meterMarkerWidth;
          final position = at.isFinite ? at.clamp(0.0, 1.0) : 0.0;
          // The bar centred on its share, then its ring held inside the
          // track, so a marker at either end still shows whole and neither
          // the bar nor its ring reaches past the track's ends.
          final start = (position * width - barWidth / 2 - ring)
              .clamp(0.0, math.max(0.0, width - barWidth - 2 * ring))
              .toDouble();
          return Stack(
            clipBehavior: Clip.none,
            children: [
              meter,
              PositionedDirectional(
                start: start,
                top: -FormMetrics.meterMarkerOverhang - ring,
                width: barWidth + 2 * ring,
                height:
                    FormMetrics.meterHeight +
                    2 * (FormMetrics.meterMarkerOverhang + ring),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: markerRing),
                  child: Padding(
                    padding: const EdgeInsets.all(ring),
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: markerColor),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// `label … [−] value [+]` — a small number stepped one at a time: the
/// Repeat sheet's interval, a custom alert offset.
///
/// The row holds no number and no bounds. [value] is the text to show, and a
/// null [onDecrement] or [onIncrement] *is* the bound, drawn as that button
/// disabled in place — so the caller's rule decides where stepping stops and
/// the row cannot disagree with it.
///
/// Nothing about the row follows the number (the Tier 2 device pass, German
/// at 200 %, found both): the value box is as wide as [widestValue] laid out
/// unseen, so the minus button stands still while the user steps; and when
/// the label cannot sit beside the stepper without a word breaking, the
/// stepper drops under the label, end-aligned — decided from the locale, the
/// text scale and the row's width, never from the value on show.
class FormStepperRow extends FormDividedRow {
  final String label;
  final String value;

  /// The widest text [value] will ever be — the unit's ceiling in its longer
  /// plural, "99 weeks" — which sizes the value box once for every value,
  /// never past what the row holds beside its two buttons (a value wider
  /// than that wraps inside the box). Left out, the box is
  /// [FormMetrics.stepperValueMinWidth] and grows with a wider value.
  final String? widestValue;

  /// Every label the row can carry in its place, for a row whose label
  /// changes under the finger (the goal sheet's unit, Aufgaben or Tage):
  /// the longest word among them decides beside or stacked, so a switch
  /// between them never moves the buttons. Left out, [label] decides.
  final String? widestLabel;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final String decrementTooltip;
  final String incrementTooltip;

  /// `SemanticsIds` values for the two buttons, whose tooltips change with
  /// the locale.
  final String? decrementIdentifier;
  final String? incrementIdentifier;

  /// Makes the value typeable: the box holds a collapsed digits-only field
  /// over [controller] in place of the text, in the same style and the same
  /// box, so a stepper that can also be typed into moves nothing (the goal
  /// sheet's amount, where seven digits are too many to step). [value] is
  /// then unread; the caller steps by rewriting the controller.
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// The most digits the field takes.
  final int? maxDigits;

  /// A `SemanticsIds` value for the field's own node, the one a script
  /// types into.
  final String? fieldIdentifier;

  const FormStepperRow({
    super.key,
    required this.label,
    required this.value,
    this.widestValue,
    this.widestLabel,
    required this.onDecrement,
    required this.onIncrement,
    required this.decrementTooltip,
    required this.incrementTooltip,
    this.decrementIdentifier,
    this.incrementIdentifier,
    this.controller,
    this.focusNode,
    this.maxDigits,
    this.fieldIdentifier,
  }) : assert(
         controller == null || widestValue != null,
         'A field needs the fixed box widestValue gives it.',
       ),
       assert(
         controller == null || focusNode != null,
         'A tap on the field\'s box focuses it through its node.',
       );

  @override
  double get dividerIndent => FormMetrics.dividerIndentPlain;

  /// The text, or the field standing in for it. The field is named by the
  /// row's label, as a title field is by its hint: the value it shows is
  /// not a name.
  ///
  /// The field wears an underline, the text field's own mark, so it reads
  /// as typeable beside the stepped text it otherwise matches; and its box
  /// is the buttons' height, every point of it focusing the field — the
  /// digits alone were a 20 dp target.
  Widget _buildValue(TextStyle style, ColorScheme colorScheme) {
    final field = controller;
    if (field == null) {
      return Text(value, textAlign: TextAlign.center, style: style);
    }
    UnderlineInputBorder underline(Color color, double width) =>
        UnderlineInputBorder(
          borderSide: BorderSide(color: color, width: width),
        );
    Widget input = TextField(
      controller: field,
      focusNode: focusNode,
      autofocus: false,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      textAlign: TextAlign.center,
      style: style,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        if (maxDigits case final digits?)
          LengthLimitingTextInputFormatter(digits),
      ],
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          vertical: FormMetrics.stepperFieldUnderlineGap,
        ),
        border: underline(colorScheme.onSurfaceVariant, 1),
        enabledBorder: underline(colorScheme.onSurfaceVariant, 1),
        focusedBorder: underline(colorScheme.primary, 2),
      ),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
    );
    // A tap region of the field's own, so a tap on the box around a focused
    // field is not a tap outside it that drops the keyboard to raise it again.
    input = TextFieldTapRegion(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: focusNode!.requestFocus,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: FormMetrics.trailingButtonSize,
          ),
          child: Center(child: input),
        ),
      ),
    );
    input = MergeSemantics(
      child: Semantics(label: label, textField: true, child: input),
    );
    if (fieldIdentifier case final id?) {
      input = AutomationId(identifier: id, child: input);
    }
    return input;
  }

  /// [text] laid out as its `Text` lays it out here — the ambient default
  /// style and bold-text setting merged in, the text scale, the direction —
  /// so a width read off it is the width the drawn text has. The caller
  /// disposes it.
  static TextPainter _measure(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    var effective = DefaultTextStyle.of(context).style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    return TextPainter(
      text: TextSpan(text: text, style: effective),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final valueStyle = TextStyle(
      fontSize: FormMetrics.labelSize,
      height: FormMetrics.labelLineHeight / FormMetrics.labelSize,
      fontWeight: FontWeight.w500,
      color: colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    var widestWidth = 0.0;
    if (widestValue case final widest?) {
      final painter = _measure(context, widest, valueStyle);
      widestWidth = painter.width;
      painter.dispose();
    }
    // The widest run the label cannot break: its longest word, as the text
    // engine sees it — or the longest of every label the row can carry.
    final labelPainter = _measure(
      context,
      widestLabel == null ? label : '$label $widestLabel',
      FormLabelValue.labelStyle(colorScheme.onSurface),
    );
    final labelWordWidth = labelPainter.minIntrinsicWidth;
    labelPainter.dispose();

    const buttons = 2 * FormMetrics.trailingButtonSize;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.only(left: RowMetrics.groupInset),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bounded = constraints.hasBoundedWidth;
            // The floor, or the widest value — but never past what the row
            // leaves beside the two buttons: a value box the row cannot hold
            // would overflow it, where a value wrapped inside the box only
            // takes a second line, on a phone narrower than any this was
            // drawn for.
            var boxWidth = widestWidth > FormMetrics.stepperValueMinWidth
                ? widestWidth
                : FormMetrics.stepperValueMinWidth;
            final room = constraints.maxWidth - buttons;
            if (bounded && boxWidth > room) boxWidth = room > 0 ? room : 0;
            final stepper = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FormTrailingButton(
                  icon: Icons.remove_rounded,
                  tooltip: decrementTooltip,
                  color: colorScheme.primary,
                  identifier: decrementIdentifier,
                  onPressed: onDecrement,
                ),
                ConstrainedBox(
                  constraints: widestValue == null
                      ? BoxConstraints(minWidth: boxWidth)
                      : BoxConstraints.tightFor(width: boxWidth),
                  child: _buildValue(valueStyle, colorScheme),
                ),
                FormTrailingButton(
                  icon: Icons.add_rounded,
                  tooltip: incrementTooltip,
                  color: colorScheme.primary,
                  identifier: incrementIdentifier,
                  onPressed: onIncrement,
                ),
              ],
            );
            final beside =
                !bounded ||
                labelWordWidth <= constraints.maxWidth - buttons - boxWidth;
            if (beside) {
              return Row(
                children: [
                  Expanded(child: FormLabelValue(label: label)),
                  stepper,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FormLabelValue(label: label),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: stepper,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
