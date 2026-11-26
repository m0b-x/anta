part of '../form_rows.dart';

class FormSectionLabel extends StatelessWidget {
  final String text;

  /// A count at the label's end, in the label's own capitals — the palette's
  /// "24 of 24" — so a section can say how full it is without a row of its
  /// own. The label takes what the count leaves, and the two are one node:
  /// a screen reader hears the section and its count as one line.
  final String? trailing;

  /// Keeps the label and its count on one line — the label ellipsizes, the
  /// count never wraps — for a list that sizes its rows by kind (the
  /// overview's exact extents), where a label that wrapped at a large text
  /// scale would outgrow its slot.
  final bool singleLine;

  /// Lets the count drop under the label when the two do not fit one line —
  /// [FormLabelValue]'s wrap — while the label keeps one line: the two-line
  /// shape a list that sizes its rows by kind gives its section labels where
  /// the widest of them does not fit one line. [singleLine] wins.
  final bool wrapTrailing;

  const FormSectionLabel({
    super.key,
    required this.text,
    this.trailing,
    this.singleLine = false,
    this.wrapTrailing = false,
  });

  /// Dart's `toUpperCase` is the simple case mapping, which leaves ß alone:
  /// "Außerdem anzeigen" came out "AUßERDEM ANZEIGEN" on the device. German
  /// capitals write it SS. Public with [textStyle], so a list that has to
  /// find its widest label measures the text as it is drawn.
  static String capitals(String text) =>
      text.toUpperCase().replaceAll('ß', 'SS');

  /// The label's and the count's style, as one definition.
  static TextStyle? textStyle(ThemeData theme) {
    return theme.textTheme.labelSmall?.copyWith(
      fontSize: RowMetrics.sectionLabelFontSize,
      height: 14 / RowMetrics.sectionLabelFontSize,
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: RowMetrics.sectionLabelLetterSpacing,
      fontWeight: RowMetrics.sectionLabelFontWeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = textStyle(Theme.of(context));
    final oneLineLabel = singleLine || wrapTrailing;
    final label = Text(
      capitals(text),
      style: style,
      maxLines: oneLineLabel ? 1 : null,
      overflow: oneLineLabel ? TextOverflow.ellipsis : null,
    );
    final count = trailing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RowMetrics.sectionLabelInset,
        0,
        RowMetrics.sectionLabelInset,
        RowMetrics.sectionLabelBottomPadding,
      ),
      child: count == null
          ? label
          : MergeSemantics(
              child: singleLine
                  ? LayoutBuilder(
                      builder: (context, constraints) => Row(
                        children: [
                          Expanded(child: label),
                          const SizedBox(width: FormMetrics.gap),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: _besideGap(constraints.maxWidth),
                            ),
                            child: Text(
                              capitals(count),
                              style: style,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  : wrapTrailing
                  ? LayoutBuilder(
                      builder: (context, constraints) => Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: FormMetrics.gap,
                        runSpacing: FormMetrics.pairRunSpacing,
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth,
                            ),
                            child: label,
                          ),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth,
                            ),
                            child: Text(
                              capitals(count),
                              style: style,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: label),
                        const SizedBox(width: FormMetrics.gap),
                        Text(capitals(count), style: style),
                      ],
                    ),
            ),
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
          height: FormMetrics.captionLineHeight / FormMetrics.captionSize,
          color: error ? colorScheme.error : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A caption in a slot as tall as the tallest thing it may ever say, so the
/// text can change — with a choice, or with an answer that arrives after the
/// sheet has opened — and nothing under it moves.
///
/// Every one of [candidates] is laid out invisibly under [child] at the
/// width the slot is given, which is what sizes it for the locale and the
/// text scale in use rather than for a guessed line count. Only [child] is
/// drawn, focusable and announced.
class FormCaptionSlot extends StatelessWidget {
  /// Everything the slot may show, [child]'s own twin included.
  final List<Widget> candidates;

  /// What the slot shows now.
  final Widget child;

  /// Where [child] sits in a slot taller than itself. At the top by default,
  /// as a caption under a row reads; centred for a caption that is a row's
  /// own line beside a glyph and a button (the ring screen's remove row),
  /// where a short line at the top of a two-line slot would hang above
  /// both.
  final AlignmentGeometry alignment;

  const FormCaptionSlot({
    super.key,
    required this.candidates,
    required this.child,
    this.alignment = AlignmentDirectional.topStart,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: alignment,
      children: [
        for (final candidate in candidates)
          ExcludeSemantics(
            child: ExcludeFocus(
              child: IgnorePointer(
                child: Opacity(opacity: 0, child: candidate),
              ),
            ),
          ),
        child,
      ],
    );
  }
}
