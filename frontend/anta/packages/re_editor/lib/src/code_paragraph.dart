part of re_editor;

/// A root span for a single editor line whose soft-wrapped continuation
/// lines should align under the content instead of the line start — a
/// hanging indent, as list items get in Obsidian.
///
/// The first [hangingChars] code units (the list-marker prefix: indent,
/// bullet/number/checkbox, trailing space) become their own single-line
/// paragraph at the line's left edge, and the remaining content is laid
/// out at the marker's exact advance width, so the first line looks
/// unchanged while wrapped lines start under the content.
///
/// Only meaningful as the root span a span builder returns for a line;
/// the paragraph provider falls back to a plain single paragraph when
/// the prefix is empty, covers the whole line, is wider than half the
/// viewport, or the line got truncated for length.
class CodeHangingTextSpan extends TextSpan {
  final int hangingChars;

  const CodeHangingTextSpan({
    required this.hangingChars,
    super.style,
    super.children,
  });

  @override
  bool operator ==(Object other) =>
      other is CodeHangingTextSpan &&
      other.hangingChars == hangingChars &&
      super == other;

  @override
  int get hashCode => Object.hash(super.hashCode, hangingChars);
}

/// An inline glyph that reserves a fixed-size box in the line's text
/// layout (a placeholder run) and paints itself directly onto the
/// editor canvas after the paragraph's text is drawn.
///
/// This is the escape hatch for marks that shouldn't be built from font
/// glyphs (checkboxes, chips): the reserved box is laid out, measured
/// and hit-tested by the paragraph like any other cluster — no widget
/// or RenderObject is involved — and [paint] receives the box's
/// resolved rect in canvas coordinates on every frame the line draws.
///
/// Contract for span builders: a placeholder is exactly **one UTF-16
/// code unit** (U+FFFC) in the paragraph's plain text, so it must
/// substitute 1:1 for a single source character — never more, never
/// fewer — or caret/selection/search offsets desync. Keep [height] no
/// taller than the line's strut height: placeholders are not clamped
/// by forceStrutHeight, so a taller box would grow the line.
abstract class CodeInlinePaintSpan extends PlaceholderSpan {
  const CodeInlinePaintSpan({
    required this.width,
    required this.height,
    super.alignment = ui.PlaceholderAlignment.middle,
    super.baseline,
    super.style,
  });

  /// Reserved box width in logical pixels.
  final double width;

  /// Reserved box height in logical pixels.
  final double height;

  /// Paints the glyph into [rect] — the reserved box in canvas
  /// coordinates. Runs per visible line per frame; keep it
  /// allocation-light (reuse [Paint] objects).
  void paint(Canvas canvas, Rect rect);

  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    final bool hasStyle = style != null;
    if (hasStyle) {
      builder.pushStyle(style!.getTextStyle(textScaler: textScaler));
    }
    builder.addPlaceholder(width, height, alignment, baseline: baseline);
    if (hasStyle) {
      builder.pop();
    }
  }

  @override
  bool visitChildren(InlineSpanVisitor visitor) => visitor(this);

  @override
  bool visitDirectChildren(InlineSpanVisitor visitor) => true;

  @override
  InlineSpan? getSpanForPositionVisitor(
      TextPosition position, Accumulator offset) {
    if (position.offset == offset.value) {
      return this;
    }
    offset.increment(1);
    return null;
  }

  @override
  int? codeUnitAtVisitor(int index, Accumulator offset) {
    final int localOffset = index - offset.value;
    offset.increment(1);
    return localOffset == 0 ? PlaceholderSpan.placeholderCodeUnit : null;
  }

  @override
  RenderComparison compareTo(InlineSpan other) {
    if (identical(this, other)) {
      return RenderComparison.identical;
    }
    return this == other
        ? RenderComparison.identical
        : RenderComparison.layout;
  }

  // [PlaceholderSpan]'s base implementation unconditionally asserts
  // false ("consider implementing WidgetSpan instead") — it assumes
  // WidgetSpan is the only legitimate subclass. This IS the legitimate
  // non-widget subclass the message doesn't anticipate: [build] never
  // touches `dimensions` (mirroring [WidgetSpan]'s own override), so
  // there's nothing left to assert.
  @override
  bool debugAssertIsValid() => true;
}

/// A rounded background chip painted behind a decorated text run,
/// before the paragraph's text draws. All values are logical pixels;
/// the box comes from the run's strut-height glyph boxes, inflated by
/// [horizontalPadding] and shrunk by [verticalInset] top and bottom so
/// chips read uniform regardless of which glyphs the run contains.
class CodeTextDecoration {
  final Color color;
  final double radius;
  final double horizontalPadding;
  final double verticalInset;

  const CodeTextDecoration({
    required this.color,
    required this.radius,
    this.horizontalPadding = 1.5,
    this.verticalInset = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeTextDecoration &&
          other.color == color &&
          other.radius == radius &&
          other.horizontalPadding == horizontalPadding &&
          other.verticalInset == verticalInset;

  @override
  int get hashCode =>
      Object.hash(color, radius, horizontalPadding, verticalInset);
}

/// A text run that paints a [CodeTextDecoration] chip behind itself.
///
/// Unlike [CodeInlinePaintSpan] this does NOT reserve layout space —
/// the text stays ordinary editable text; only paint changes. The
/// paragraph resolves the run's boxes once (lazily, on first draw) and
/// paints every chip before the text, so decorations never occlude
/// glyphs. Wrapped runs get one chip per visual-line box.
class CodeDecoratedTextSpan extends TextSpan {
  final CodeTextDecoration decoration;

  const CodeDecoratedTextSpan({
    required this.decoration,
    super.text,
    super.style,
    super.children,
  });

  @override
  bool operator ==(Object other) =>
      other is CodeDecoratedTextSpan &&
      other.decoration == decoration &&
      super == other;

  @override
  int get hashCode => Object.hash(super.hashCode, decoration);
}

abstract class IParagraph {
  double get width;
  double get height;
  double get preferredLineHeight;
  bool get trucated;
  int get length;
  int get lineCount;

  void draw(Canvas canvas, Offset offset);

  TextPosition getPosition(Offset offset);

  TextRange getWord(Offset offset);

  InlineSpan? getSpanForPosition(TextPosition position);

  TextRange getRangeForSpan(InlineSpan span);

  TextRange getLineBoundary(TextPosition position);

  Offset? getOffset(TextPosition position);

  List<Rect> getRangeRects(TextRange range);
}
