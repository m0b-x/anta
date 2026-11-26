part of '../form_rows.dart';

/// The row a form opens with: `[avatar] title` as one field that wraps and,
/// from [counterFrom] characters on, a counter under it — the event editor's
/// title, the quick alarm's, the template form's name.
///
/// A long title is read, not scrolled, so the field takes as many lines as
/// its text needs and refuses a line break: Enter is the keyboard's Done.
/// The counter is a line of the row's own because a collapsed decoration has
/// no counter slot, and it exists only near the limit, so an ordinary title
/// leaves the row at its 56 dp.
class FormTitleRow extends FormDividedRow {
  /// A 40 dp widget — an `EventAvatar` — previewing what the title names.
  /// Boxed to [FormMetrics.rowLeadingSize], so the field and the hairline
  /// under the row start where they do whatever the widget draws.
  final Widget leading;
  final TextEditingController controller;

  /// The field's focus node. Left out, the row owns one: the whole row is the
  /// field's tap target, and it needs the node to hand the focus over.
  final FocusNode? focusNode;

  /// The placeholder, and the field's accessible name whether or not it is
  /// drawn.
  final String hint;
  final int maxLength;

  /// The length the counter line appears from.
  final int counterFrom;

  /// The counter's text for a length and [maxLength] — passed in like every
  /// other label here, so the primitives stay free of the localizations.
  final String Function(int length, int maxLength) counterLabel;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;

  /// Lands on the field's own text-field node, which is what a device script
  /// types into by id.
  final String? identifier;

  /// A line of the row's own under the field, in the error colour at the
  /// caption size — the category editor's "already exists", which warns and
  /// never blocks. It takes the counter's line: alone while the counter is
  /// off, before the counter on the same line once the length reaches
  /// [counterFrom], so near the limit the row grows by one line and not two.
  final String? warning;

  const FormTitleRow({
    super.key,
    required this.leading,
    required this.controller,
    this.focusNode,
    required this.hint,
    required this.maxLength,
    required this.counterFrom,
    required this.counterLabel,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.onSubmitted,
    this.identifier,
    this.warning,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentTitle;

  @override
  Widget build(BuildContext context) => _FormTitleRowBody(row: this);
}

/// The title row's state: the focus node the row owns when its caller passes
/// none. The collapsed field is one text line in a 56 dp row, and a thumb
/// landing above or below that line, right of it or on the avatar focused
/// nothing (the Tier 2 device pass); the whole row is the target now, as the
/// search row's padded field makes its whole row one.
class _FormTitleRowBody extends StatefulWidget {
  final FormTitleRow row;

  const _FormTitleRowBody({required this.row});

  @override
  State<_FormTitleRowBody> createState() => _FormTitleRowBodyState();
}

class _FormTitleRowBodyState extends State<_FormTitleRowBody> {
  FocusNode? _ownedNode;

  FocusNode get _focusNode =>
      widget.row.focusNode ??
      (_ownedNode ??= FocusNode(debugLabel: 'FormTitleRow'));

  @override
  void dispose() {
    _ownedNode?.dispose();
    super.dispose();
  }

  /// What a tap on the field's own line does, for the rest of the row. A
  /// field that already holds the focus is asked for its keyboard rather than
  /// for focus: Android's back leaves a focused field under no keyboard, and
  /// a tap on the text brings it back — so a tap beside the text does too.
  void _focusField() {
    final node = _focusNode;
    if (node.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      return;
    }
    node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final controller = row.controller;
    final hint = row.hint;
    final colorScheme = Theme.of(context).colorScheme;
    Widget field = TextField(
      controller: controller,
      focusNode: _focusNode,
      autofocus: row.autofocus,
      maxLines: null,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.done,
      textCapitalization: row.textCapitalization,
      inputFormatters: [FilteringTextInputFormatter.deny('\n')],
      maxLength: row.maxLength,
      buildCounter:
          (context, {required currentLength, required isFocused, maxLength}) =>
              null,
      style: TextStyle(
        fontSize: FormMetrics.titleFontSize,
        fontWeight: FontWeight.w500,
        height: FormMetrics.titleLineHeight,
        color: colorScheme.onSurface,
      ),
      decoration: InputDecoration.collapsed(
        hintText: hint,
        // The field is as tall as what it shows. A decoration keeps its
        // hint's size by default, so a hint that wraps — a long word at a
        // large text scale — left a typed title over the blank line the
        // hint had needed.
        maintainHintSize: false,
        hintStyle: TextStyle(
          fontSize: FormMetrics.titleFontSize,
          fontWeight: FontWeight.w400,
          height: FormMetrics.titleLineHeight,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      onSubmitted: row.onSubmitted,
    );
    // A collapsed decoration names the field through its hint alone, and the
    // hint goes with the first character typed — a screen reader then heard
    // the title and no name for it. The name is restored as a label, but only
    // while the field holds text: beside a drawn hint it would be said twice.
    field = ListenableBuilder(
      listenable: controller,
      builder: (context, child) =>
          Semantics(label: controller.text.isEmpty ? null : hint, child: child),
      child: field,
    );
    if (row.identifier case final id?) {
      field = AutomationId(identifier: id, child: field);
    }
    // A tap on the text line is the field's own (its recogniser wins the
    // arena); anywhere else in the row it is this one. Not a node of its own:
    // the field's node is where a screen reader already focuses the title.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: _focusField,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: FormMetrics.titleRowMinHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RowMetrics.groupInset,
            vertical: FormMetrics.titleRowVerticalPadding,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: FormMetrics.rowLeadingSize,
                child: Center(child: row.leading),
              ),
              const SizedBox(width: FormMetrics.gap),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: FormMetrics.titleFieldTopInset,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      field,
                      ListenableBuilder(
                        listenable: controller,
                        builder: (context, _) {
                          final length = controller.text.characters.length;
                          final warning = row.warning;
                          final counting = length >= row.counterFrom;
                          if (!counting && warning == null) {
                            return const SizedBox.shrink();
                          }
                          final counter = counting
                              ? Text(
                                  row.counterLabel(length, row.maxLength),
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontSize: FormMetrics.counterSize,
                                    height: 16 / FormMetrics.counterSize,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                    color: length >= row.maxLength
                                        ? colorScheme.error
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                )
                              : null;
                          return Padding(
                            padding: const EdgeInsets.only(
                              top: FormMetrics.titleCounterTopInset,
                            ),
                            child: warning == null
                                ? counter
                                // The warning leads and the counter keeps
                                // its end, on one line: two sizes of text
                                // share the line by their baselines.
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Expanded(
                                        child: FormCaption(
                                          text: warning,
                                          error: true,
                                        ),
                                      ),
                                      if (counter != null) ...[
                                        const SizedBox(width: FormMetrics.gap),
                                        counter,
                                      ],
                                    ],
                                  ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The row a read-only surface opens with: `[avatar] title` over a caption
/// of the row's own — [FormTitleRow]'s twin for a surface that names an
/// event without editing it. The detail sheet's first row (the category
/// under the title) and the ring screen's (the event's own time).
///
/// The title is the editor's 20 / 500 on the same line height, so the same
/// event is the same line on every surface that leads with it, and it wraps
/// freely: a title is read whole. With a [caption] the row is the two-line
/// row; without one it is the title row's 56 dp around the avatar.
///
/// One node — the title, then the caption. [leading] is decoration and is
/// kept out of it whatever it draws.
class FormReadTitleRow extends FormDividedRow {
  /// A 40 dp widget — an `EventAvatar` — previewing what the title names.
  /// Boxed to [FormMetrics.rowLeadingSize], so the text and the hairline
  /// under the row start where they do whatever the widget draws.
  final Widget leading;
  final String title;

  /// The line under the title, or null for a row that is the title alone.
  final String? caption;

  /// The box [leading] is centred in: the avatar's [FormMetrics.rowLeadingSize]
  /// by default, [FormMetrics.glyphSize] for a surface that trades the avatar
  /// for its glyph at large text — the 18 dp it frees keeps a one-word name
  /// whole at 2.0 on a small phone (the categories page's rule).
  final double leadingSize;

  const FormReadTitleRow({
    super.key,
    required this.leading,
    required this.title,
    this.caption,
    this.leadingSize = FormMetrics.rowLeadingSize,
  });

  @override
  double get dividerIndent =>
      RowMetrics.groupInset + leadingSize + FormMetrics.gap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final captionText = caption;
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: captionText == null
              ? FormMetrics.titleRowMinHeight
              : FormMetrics.twoLineRowMinHeight,
        ),
        child: Padding(
          padding: captionText == null
              ? const EdgeInsets.symmetric(
                  horizontal: RowMetrics.groupInset,
                  vertical: FormMetrics.titleRowVerticalPadding,
                )
              : RowMetrics.twoLinePadding,
          child: Row(
            children: [
              ExcludeSemantics(
                child: SizedBox.square(
                  dimension: leadingSize,
                  child: Center(child: leading),
                ),
              ),
              const SizedBox(width: FormMetrics.gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: FormMetrics.titleFontSize,
                        height: FormMetrics.titleLineHeight,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if (captionText != null) ...[
                      const SizedBox(height: RowMetrics.lineGap),
                      Text(
                        captionText,
                        style: TextStyle(
                          fontSize: FormMetrics.captionSize,
                          height:
                              FormMetrics.captionLineHeight /
                              FormMetrics.captionSize,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `[glyph] value / caption ›` — the one value a sheet leads with, drawn
/// large: the quick alarm's time over the day it lands on.
///
/// One target and one announcement. The node reads "value, caption" and
/// carries [tooltip] as its hint, which a screen reader speaks on focus; a
/// tooltip beside a label is not spoken on Android 9 and later. The value is
/// fitted to one line: at 200 % a 12-hour time is wider than a narrow
/// phone's row, and a time that wraps or ellipsizes is no longer read at a
/// glance.
///
/// The row is as tall as the text scale makes it and never as the string
/// does: the fitted value sits on a line reserved at its full size, so
/// "9:30 AM" becoming "10:20 AM" moves nothing under the row.
class FormHeroRow extends FormDividedRow {
  final IconData glyph;
  final String value;
  final String caption;

  /// What a tap does, as the node's hint. Never drawn.
  final String tooltip;
  final VoidCallback onTap;
  final String? identifier;

  const FormHeroRow({
    super.key,
    required this.glyph,
    required this.value,
    required this.caption,
    required this.tooltip,
    required this.onTap,
    this.identifier,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentPlain;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final valueStyle = TextStyle(
      fontSize: FormMetrics.heroValueSize,
      height: FormMetrics.heroValueLineHeight / FormMetrics.heroValueSize,
      fontWeight: FontWeight.w400,
      color: colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: FormMetrics.heroRowMinHeight,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: RowMetrics.groupInset,
          top: RowMetrics.twoLinePadding.top,
          right: FormMetrics.rowEndPadding,
          bottom: RowMetrics.twoLinePadding.bottom,
        ),
        child: Row(
          children: [
            FormGlyph(icon: glyph),
            const SizedBox(width: FormMetrics.gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A fitted box is only as tall as its child's aspect ratio
                  // leaves it, so on its own a wider time made a shorter row.
                  // One digit, laid out at full size and never drawn, holds
                  // the line open and the value is fitted inside that —
                  // measured, not worked out from the text scale, because
                  // the text engine rounds a line's height.
                  SizedBox(
                    width: double.infinity,
                    child: Stack(
                      children: [
                        Opacity(
                          opacity: 0,
                          child: Text('0', maxLines: 1, style: valueStyle),
                        ),
                        Positioned.fill(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              value,
                              maxLines: 1,
                              softWrap: false,
                              style: valueStyle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: RowMetrics.lineGap),
                  Text(
                    caption,
                    style: TextStyle(
                      fontSize: FormMetrics.captionSize,
                      height:
                          FormMetrics.captionLineHeight /
                          FormMetrics.captionSize,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: FormMetrics.gap),
            const FormChevron(),
          ],
        ),
      ),
    );
    final Widget well = Semantics(
      button: true,
      enabled: true,
      label: '$value, $caption',
      hint: tooltip,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(onTap: onTap, child: row),
      ),
    );
    if (identifier case final id?) {
      return AutomationId(identifier: id, child: well);
    }
    return MergeSemantics(child: well);
  }
}
