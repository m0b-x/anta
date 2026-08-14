part of re_editor;

class _ParagraphImpl extends IParagraph {
  // Unicode value for a zero width joiner character.
  static const int _zwjUtf16 = 0x200d;

  final String text;
  final TextSpan span;
  final ui.Paragraph paragraph;
  final bool _trucated;
  final double _preferredLineHeight;
  final int _lineCount;

  // For performance, do not init here
  Map<TextPosition, Offset?>? _offsets;

  // Lazily resolved on first draw; empty for the common no-placeholder
  // line so steady-state drawing stays a single drawParagraph call.
  List<_InlinePaintBox>? _inlinePaints;

  // Background chips for CodeDecoratedTextSpan runs, resolved with the
  // inline paints and drawn BEFORE the text so glyphs are never
  // occluded.
  List<_DecorPaintBox>? _decorPaints;

  static final Paint _decorPaint = Paint()..style = PaintingStyle.fill;

  _ParagraphImpl({
    required this.text,
    required this.span,
    required this.paragraph,
    required bool trucated,
    required double preferredLineHeight,
  })  : _trucated = trucated,
        _preferredLineHeight = preferredLineHeight,
        _lineCount = (paragraph.height / preferredLineHeight).ceil();

  int get runeLength => text.runes.length;

  int? codeUnitAt(int index) {
    if (index < 0 || index >= length) {
      return null;
    }
    return text.codeUnitAt(index);
  }

  @override
  double get width => _applyFloatingPointHack(max(0, paragraph.longestLine));

  @override
  double get height => lineCount * preferredLineHeight;

  @override
  double get preferredLineHeight => _preferredLineHeight;

  @override
  int get length => text.length;

  @override
  int get lineCount => _lineCount;

  @override
  bool get trucated => _trucated;

  @override
  void draw(Canvas canvas, Offset offset) {
    final List<_DecorPaintBox> decors = _decorPaints ??= _resolveDecorPaints();
    for (final _DecorPaintBox entry in decors) {
      _decorPaint.color = entry.decoration.color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          entry.rect.shift(offset),
          Radius.circular(entry.decoration.radius),
        ),
        _decorPaint,
      );
    }
    canvas.drawParagraph(paragraph, offset);
    final List<_InlinePaintBox> paints =
        _inlinePaints ??= _resolveInlinePaints();
    for (final _InlinePaintBox entry in paints) {
      entry.span.paint(canvas, entry.rect.shift(offset));
    }
  }

  /// Resolves the chip rect(s) for every [CodeDecoratedTextSpan] in the
  /// span tree. The walk tracks code-unit offsets exactly as the
  /// paragraph text counts them (placeholders are one unit), asks for
  /// strut-height boxes so chip height is uniform regardless of the
  /// run's glyphs, then applies the decoration's padding/inset.
  List<_DecorPaintBox> _resolveDecorPaints() {
    List<_DecorPaintBox>? found;
    int walk(InlineSpan node, int offset) {
      if (node is TextSpan) {
        final int start = offset;
        final String? nodeText = node.text;
        if (nodeText != null) {
          offset += nodeText.length;
        }
        final List<InlineSpan>? children = node.children;
        if (children != null) {
          for (final InlineSpan child in children) {
            offset = walk(child, offset);
          }
        }
        if (node is CodeDecoratedTextSpan &&
            offset > start &&
            offset <= text.length) {
          final CodeTextDecoration decoration = node.decoration;
          final List<ui.TextBox> boxes = paragraph.getBoxesForRange(
              start, offset,
              boxHeightStyle: ui.BoxHeightStyle.strut);
          for (final ui.TextBox box in boxes) {
            final Rect rect = Rect.fromLTRB(
              box.left - decoration.horizontalPadding,
              box.top + decoration.verticalInset,
              box.right + decoration.horizontalPadding,
              box.bottom - decoration.verticalInset,
            );
            if (!rect.isEmpty) {
              (found ??= []).add(_DecorPaintBox(decoration, rect));
            }
          }
        }
        return offset;
      }
      return offset + node.length;
    }

    walk(span, 0);
    return found ?? const [];
  }

  /// Pairs each [CodeInlinePaintSpan] in the span tree with its
  /// reserved box. Placeholder boxes come back in build order, so the
  /// pairing indexes over ALL placeholder spans (paint spans or not) to
  /// stay aligned if other placeholder kinds ever appear in a line.
  List<_InlinePaintBox> _resolveInlinePaints() {
    List<PlaceholderSpan>? placeholders;
    span.visitChildren((child) {
      if (child is PlaceholderSpan) {
        (placeholders ??= []).add(child);
      }
      return true;
    });
    final List<PlaceholderSpan>? found = placeholders;
    if (found == null) {
      return const [];
    }
    final List<ui.TextBox> boxes = paragraph.getBoxesForPlaceholders();
    final int count = min(found.length, boxes.length);
    final List<_InlinePaintBox> paints = [];
    for (int i = 0; i < count; i++) {
      final PlaceholderSpan placeholder = found[i];
      if (placeholder is CodeInlinePaintSpan) {
        paints.add(_InlinePaintBox(placeholder, boxes[i].toRect()));
      }
    }
    return paints;
  }

  @override
  TextPosition getPosition(Offset offset) {
    final TextPosition position = paragraph.getPositionForOffset(offset);
    return position;
  }

  @override
  InlineSpan? getSpanForPosition(TextPosition position) {
    if (position.offset >= length - 1) {
      return null;
    }
    return span.getSpanForPosition(position);
  }

  @override
  TextRange getRangeForSpan(InlineSpan span) {
    int offset = 0;
    this.span.visitChildren((child) {
      if (identical(child, span)) {
        return false;
      }
      offset += child.length;
      return true;
    });
    return TextRange(start: offset, end: offset + span.length);
  }

  @override
  TextRange getWord(Offset offset) {
    return paragraph.getWordBoundary(getPosition(offset));
  }

  @override
  TextRange getLineBoundary(TextPosition position) {
    return paragraph.getLineBoundary(position);
  }

  @override
  Offset? getOffset(TextPosition position) {
    Offset? offset = _offsets?[position];
    if (offset != null) {
      return offset;
    }
    if (text.isEmpty) {
      return Offset.zero;
    }
    if (position.offset == 0) {
      return Offset.zero;
    }
    if (position.affinity == TextAffinity.downstream) {
      offset = _getOffsetDownstream(position.offset) ??
          _getOffsetUpstream(position.offset);
    } else {
      offset = _getOffsetUpstream(position.offset) ??
          _getOffsetDownstream(position.offset);
    }
    (_offsets ??= {})[position] = offset;
    return offset;
  }

  @override
  List<Rect> getRangeRects(TextRange range) {
    if (text.isEmpty) {
      return [Rect.fromLTWH(0, 0, 0, _preferredLineHeight)];
    }
    if (range.isCollapsed) {
      return const [];
    }
    return paragraph
        .getBoxesForRange(range.start, range.end,
            boxHeightStyle: ui.BoxHeightStyle.max)
        .map((e) => e.toRect())
        .toList();
  }

  Offset? _getOffsetDownstream(int position) {
    final int? nextCodeUnit = codeUnitAt(min(position, text.length - 1));
    if (nextCodeUnit == null) {
      return null;
    }
    // Check for multi-code-unit glyphs such as emojis or zero width joiner.
    final int graphemeClusterLength = _isUtf16Surrogate(nextCodeUnit) ||
            _isUnicodeDirectionality(nextCodeUnit) ||
            codeUnitAt(position) == _zwjUtf16
        ? 2
        : 1;
    final List<TextBox> boxes = paragraph.getBoxesForRange(
        position, position + graphemeClusterLength,
        boxHeightStyle: ui.BoxHeightStyle.strut);
    if (boxes.isEmpty) {
      return null;
    }
    return Offset(boxes.first.left, boxes.first.top);
  }

  Offset? _getOffsetUpstream(int position) {
    final int? prevCodeUnit = codeUnitAt(max(0, position - 1));
    if (prevCodeUnit == null) {
      return null;
    }
    // Check for multi-code-unit glyphs such as emojis or zero width joiner.
    final int graphemeClusterLength = _isUtf16Surrogate(prevCodeUnit) ||
            _isUnicodeDirectionality(prevCodeUnit) ||
            codeUnitAt(position) == _zwjUtf16
        ? 2
        : 1;
    final List<TextBox> boxes = paragraph.getBoxesForRange(
        position - graphemeClusterLength, position,
        boxHeightStyle: ui.BoxHeightStyle.strut);
    if (boxes.isEmpty) {
      return null;
    }
    return Offset(boxes.first.right, boxes.first.top);
  }

  // Returns true if the given value is a valid UTF-16 surrogate. The value
  // must be a UTF-16 code unit, meaning it must be in the range 0x0000-0xFFFF.
  //
  // See also:
  //   * https://en.wikipedia.org/wiki/UTF-16#Code_points_from_U+010000_to_U+10FFFF
  bool _isUtf16Surrogate(int value) {
    return value & 0xF800 == 0xD800;
  }

  // Checks if the glyph is either [Unicode.RLM] or [Unicode.LRM]. These values take
  // up zero space and do not have valid bounding boxes around them.
  //
  // We do not directly use the [Unicode] constants since they are strings.
  bool _isUnicodeDirectionality(int value) {
    return value == 0x200F || value == 0x200E;
  }

  // Unfortunately, using full precision floating point here causes bad layouts
  // because floating point math isn't associative. If we add and subtract
  // padding, for example, we'll get different values when we estimate sizes and
  // when we actually compute layout because the operations will end up associated
  // differently. To work around this problem for now, we round fractional pixel
  // values up to the nearest whole pixel value. The right long-term fix is to do
  // layout using fixed precision arithmetic.
  double _applyFloatingPointHack(double layoutValue) {
    return layoutValue.ceilToDouble();
  }
}

/// A [CodeInlinePaintSpan] paired with its reserved box (paragraph
/// coordinates), resolved once per built paragraph.
class _InlinePaintBox {
  final CodeInlinePaintSpan span;
  final Rect rect;

  const _InlinePaintBox(this.span, this.rect);
}

/// A [CodeTextDecoration] paired with one padded chip rect (paragraph
/// coordinates), resolved once per built paragraph.
class _DecorPaintBox {
  final CodeTextDecoration decoration;
  final Rect rect;

  const _DecorPaintBox(this.decoration, this.rect);
}

class _ScaledLineStyle {
  final ui.ParagraphStyle paragraphStyle;
  final double preferredLineHeight;

  const _ScaledLineStyle(this.paragraphStyle, this.preferredLineHeight);
}

class _CodeParagraphProvider {
  // Bound the cache so we don't retain `ui.Paragraph` (and its native skia
  // memory) for every line ever scrolled past. Tuned for ~10x a typical
  // viewport on mobile — large enough to hide cache misses during scroll,
  // small enough to keep peak memory bounded on long documents.
  static const int _kMaxCacheSize = 512;

  final Map<TextSpan, IParagraph> _cachedParagraphs;

  // Identity-keyed L1 in front of the deep-equality LRU: span builders
  // that memoize per line return the identical TextSpan instance on
  // every layout pass, but `TextSpan.hashCode` recurses through the
  // whole child tree (and every child's TextStyle), so even a cache HIT
  // in `_cachedParagraphs` costs hundreds of hash ops — three times per
  // hit with the LRU touch. This map collapses the steady-state hit to
  // one pointer hash. Misses fall through to the equality map, so
  // callers that rebuild fresh spans every frame keep today's behavior.
  final LinkedHashMap<TextSpan, IParagraph> _identityParagraphs;

  // A span whose root style sets a fontSize different from the base style
  // gets its own strut / preferred line height, so callers (span builders)
  // can render individual lines taller than the editor's base line height.
  final Map<double, _ScaledLineStyle> _scaledLineStyles;

  ui.TextStyle? _style;
  TextStyle? _baseStyle;
  ui.ParagraphConstraints? _constraints;
  ui.ParagraphStyle? _paragraphStyle;
  double? _preferredLineHeight;
  int? _maxLengthSingleLineRendering;

  _CodeParagraphProvider()
      : _cachedParagraphs = {},
        _identityParagraphs = LinkedHashMap.identity(),
        _scaledLineStyles = {};

  void updateBaseStyle(TextStyle style) {
    // Called once per line per layout pass with the render's stable
    // _textStyle, so short-circuit on the Flutter style before paying
    // the ui.TextStyle allocation + native comparison below.
    if (identical(style, _baseStyle) || style == _baseStyle) {
      return;
    }
    final ui.TextStyle uiStyle = style.getTextStyle();
    if (uiStyle == _style) {
      return;
    }
    _paragraphStyle = style.getParagraphStyle(
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
        strutStyle: StrutStyle(
          fontSize: style.fontSize,
          fontFamily: style.fontFamily,
          height: style.height,
          forceStrutHeight: true,
        ));
    _style = uiStyle;
    _baseStyle = style;
    _scaledLineStyles.clear();
    final TextPainter painter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    painter.text = TextSpan(text: '0', style: style);
    _preferredLineHeight = painter.preferredLineHeight;
    clearCache();
  }

  _ScaledLineStyle _scaledLineStyle(double fontSize) {
    final _ScaledLineStyle? cached = _scaledLineStyles[fontSize];
    if (cached != null) {
      return cached;
    }
    final TextStyle style = _baseStyle!.copyWith(fontSize: fontSize);
    final ui.ParagraphStyle paragraphStyle = style.getParagraphStyle(
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
        strutStyle: StrutStyle(
          fontSize: fontSize,
          fontFamily: style.fontFamily,
          height: style.height,
          forceStrutHeight: true,
        ));
    final TextPainter painter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    painter.text = TextSpan(text: '0', style: style);
    final _ScaledLineStyle scaled =
        _ScaledLineStyle(paragraphStyle, painter.preferredLineHeight);
    _scaledLineStyles[fontSize] = scaled;
    return scaled;
  }

  void updateMaxLengthSingleLineRendering(int? maxLengthSingleLineRendering) {
    if (_maxLengthSingleLineRendering == maxLengthSingleLineRendering) {
      return;
    }
    _maxLengthSingleLineRendering = maxLengthSingleLineRendering;
    clearCache();
  }

  IParagraph build(TextSpan span, double maxWidth) {
    if (maxWidth != _constraints?.width) {
      _constraints = ui.ParagraphConstraints(width: maxWidth);
      clearCache();
    }
    // Identity fast path: no deep span hashing. The equality LRU is NOT
    // touched here — if it evicts an entry still hot in the identity
    // map, the identity map keeps serving it (both maps are bounded).
    IParagraph? cache = _identityParagraphs[span];
    if (cache != null) {
      _identityParagraphs.remove(span);
      _identityParagraphs[span] = cache;
      return cache;
    }
    cache = _cachedParagraphs[span];
    if (cache != null) {
      // Touch for LRU: re-insert at the tail (insertion order = recency).
      _cachedParagraphs.remove(span);
      _cachedParagraphs[span] = cache;
      _rememberIdentity(span, cache);
      return cache;
    }
    final IParagraph impl;
    // Trucate the span if it's too long.
    final String plainText = span.toPlainText();
    final int? renderingLength = _maxLengthSingleLineRendering;
    if (renderingLength != null && plainText.length > renderingLength) {
      impl = _build(trucate(span, renderingLength),
          plainText.substring(0, renderingLength), true);
    } else {
      impl = _build(span, plainText, false);
    }
    _cachedParagraphs[span] = impl;
    if (_cachedParagraphs.length > _kMaxCacheSize) {
      // Evict the oldest entry (head of the insertion-ordered map) from
      // both maps: the identity entry for the same span instance must
      // not outlive the equality entry, or its native paragraph memory
      // would be pinned past eviction.
      final TextSpan evicted = _cachedParagraphs.keys.first;
      _cachedParagraphs.remove(evicted);
      _identityParagraphs.remove(evicted);
    }
    _rememberIdentity(span, impl);
    return impl;
  }

  void _rememberIdentity(TextSpan span, IParagraph paragraph) {
    _identityParagraphs[span] = paragraph;
    if (_identityParagraphs.length > _kMaxCacheSize) {
      _identityParagraphs.remove(_identityParagraphs.keys.first);
    }
  }

  TextSpan trucate(TextSpan span, int maxLength) {
    int currentLength = 0;
    TextSpan truncateSpan(TextSpan span) {
      if (currentLength >= maxLength) {
        return const TextSpan(text: '');
      }
      String? text = span.text;
      String? keptText;
      if (text != null) {
        final int remainingLength = maxLength - currentLength;
        keptText =
            text.length > remainingLength ? text.substring(0, remainingLength) : text;
        currentLength += keptText.length;
      }
      List<InlineSpan>? children;
      if (span.children != null) {
        children = [];
        for (InlineSpan child in span.children!) {
          if (currentLength >= maxLength) {
            break;
          }
          if (child is TextSpan) {
            // A subtree that fits entirely is kept by identity — no
            // rebuild allocations, and subclass spans (decorations,
            // hanging tags) survive the copy.
            final int childLength = child.length;
            if (currentLength + childLength <= maxLength) {
              currentLength += childLength;
              children.add(child);
            } else {
              children.add(truncateSpan(child));
            }
          } else {
            // Placeholders count for their code-unit length so the
            // truncated tree stays aligned with the truncated text.
            currentLength += child.length;
            children.add(child);
          }
        }
      }
      return TextSpan(text: keptText, style: span.style, children: children);
    }

    return truncateSpan(span);
  }

  void clearCache() {
    _cachedParagraphs.clear();
    _identityParagraphs.clear();
  }

  IParagraph _build(TextSpan span, String plainText, bool trucated) {
    ui.ParagraphStyle? style = _paragraphStyle;
    double? preferredLineHeight = _preferredLineHeight;
    if (style == null) {
      throw AssertionError('Must call updateBaseStyle before build Paragraph.');
    }
    final double? rootFontSize = span.style?.fontSize;
    final double? baseFontSize = _baseStyle?.fontSize;
    if (rootFontSize != null &&
        baseFontSize != null &&
        rootFontSize != baseFontSize) {
      final _ScaledLineStyle scaled = _scaledLineStyle(rootFontSize);
      style = scaled.paragraphStyle;
      preferredLineHeight = scaled.preferredLineHeight;
    }
    if (!trucated && span is CodeHangingTextSpan) {
      final IParagraph? hanging =
          _buildHanging(span, plainText, style, preferredLineHeight!);
      if (hanging != null) {
        return hanging;
      }
    }
    final ui.ParagraphBuilder builder = ui.ParagraphBuilder(style);
    span.build(builder);
    final ui.Paragraph paragraph = builder.build();
    paragraph.layout(_constraints!);
    return _ParagraphImpl(
      text: plainText,
      span: span,
      paragraph: paragraph,
      trucated: trucated,
      preferredLineHeight: preferredLineHeight!,
    );
  }

  /// Builds the two-part hanging-indent paragraph for [span], or null
  /// when the split is degenerate and the plain single paragraph should
  /// be used instead: an empty/whole-line prefix, a marker wider than
  /// half the viewport (deeply indented list on a narrow screen), or a
  /// marker that would itself wrap.
  IParagraph? _buildHanging(
    CodeHangingTextSpan span,
    String plainText,
    ui.ParagraphStyle style,
    double preferredLineHeight,
  ) {
    final int hangingChars = span.hangingChars;
    if (hangingChars <= 0 || hangingChars >= plainText.length) {
      return null;
    }
    final double maxWidth = _constraints!.width;
    final TextSpan markerSpan = trucate(span, hangingChars);
    final ui.ParagraphBuilder markerBuilder = ui.ParagraphBuilder(style);
    markerSpan.build(markerBuilder);
    final ui.Paragraph markerParagraph = markerBuilder.build();
    markerParagraph.layout(_constraints!);
    // A marker that wraps can't anchor a hanging indent.
    if (markerParagraph.height > preferredLineHeight * 1.5) {
      return null;
    }
    // Measure the marker via glyph boxes instead of longestLine: the
    // prefix always ends in the separator space and longestLine excludes
    // trailing whitespace, which would collapse the marker-content gap.
    final List<ui.TextBox> markerBoxes = markerParagraph.getBoxesForRange(
        0, hangingChars,
        boxHeightStyle: ui.BoxHeightStyle.strut);
    double markerRight = 0;
    for (final ui.TextBox box in markerBoxes) {
      if (box.right > markerRight) {
        markerRight = box.right;
      }
    }
    // Placeholder boxes (inline-painted marks like checkboxes) are
    // queried separately so the measured indent always covers them,
    // whether or not getBoxesForRange reports placeholder clusters.
    for (final ui.TextBox box in markerParagraph.getBoxesForPlaceholders()) {
      if (box.right > markerRight) {
        markerRight = box.right;
      }
    }
    final double indent = markerRight.ceilToDouble();
    if (indent <= 0 || (maxWidth.isFinite && indent > maxWidth / 2)) {
      return null;
    }
    final TextSpan contentSpan = _dropPrefix(span, hangingChars);
    final ui.ParagraphBuilder contentBuilder = ui.ParagraphBuilder(style);
    contentSpan.build(contentBuilder);
    final ui.Paragraph contentParagraph = contentBuilder.build();
    contentParagraph.layout(ui.ParagraphConstraints(
        width: maxWidth.isFinite ? max(0, maxWidth - indent) : maxWidth));
    return _HangingParagraphImpl(
      rootSpan: span,
      marker: _ParagraphImpl(
        text: plainText.substring(0, hangingChars),
        span: markerSpan,
        paragraph: markerParagraph,
        trucated: false,
        preferredLineHeight: preferredLineHeight,
      ),
      content: _ParagraphImpl(
        text: plainText.substring(hangingChars),
        span: contentSpan,
        paragraph: contentParagraph,
        trucated: false,
        preferredLineHeight: preferredLineHeight,
      ),
      indent: indent,
    );
  }

  /// The mirror of [trucate]: drops the first [skip] code units while
  /// keeping the span structure and styles, so the content part of a
  /// hanging line renders exactly as it would inside the full span.
  /// Non-TextSpan children consume their code-unit length (a placeholder
  /// is one unit in the plain text), so mixed span trees never desync
  /// the content paragraph from `plainText.substring(skip)`.
  TextSpan _dropPrefix(TextSpan span, int skip) {
    int remaining = skip;
    TextSpan dropSpan(TextSpan span) {
      // Everything after the drop point is untouched — keep those
      // subtrees by identity so subclass spans (decorated tag/code
      // runs in list-item content) survive into the content paragraph.
      if (remaining <= 0) {
        return span;
      }
      final String? text = span.text;
      String? keptText;
      if (text != null) {
        if (remaining <= 0) {
          keptText = text;
        } else if (text.length <= remaining) {
          remaining -= text.length;
          keptText = '';
        } else {
          keptText = text.substring(remaining);
          remaining = 0;
        }
      }
      List<InlineSpan>? children;
      if (span.children != null) {
        children = [];
        for (final InlineSpan child in span.children!) {
          if (child is TextSpan) {
            children.add(dropSpan(child));
          } else if (remaining >= child.length) {
            remaining -= child.length;
          } else {
            remaining = 0;
            children.add(child);
          }
        }
      }
      return TextSpan(text: keptText, style: span.style, children: children);
    }

    return dropSpan(span);
  }
}

/// Two-part paragraph giving list items a hanging indent: the marker
/// prefix is its own single-line paragraph at the line's left edge and
/// the content is laid out at [indent] — the marker's exact advance
/// width — so soft-wrapped continuation lines align under the content.
/// Every geometry query (caret offsets, selection/search rects, hit
/// tests, word and line boundaries) maps piecewise through the two
/// parts; the seam at the marker/content boundary is invisible because
/// both sides resolve to the same x.
class _HangingParagraphImpl extends IParagraph {
  final TextSpan rootSpan;
  final _ParagraphImpl marker;
  final _ParagraphImpl content;
  final double indent;

  _HangingParagraphImpl({
    required this.rootSpan,
    required this.marker,
    required this.content,
    required this.indent,
  });

  int get _markerLen => marker.length;

  @override
  double get width => indent + content.width;

  @override
  double get height => content.height;

  @override
  double get preferredLineHeight => content.preferredLineHeight;

  @override
  int get length => marker.length + content.length;

  @override
  int get lineCount => content.lineCount;

  @override
  bool get trucated => false;

  @override
  void draw(Canvas canvas, Offset offset) {
    marker.draw(canvas, offset);
    content.draw(canvas, offset.translate(indent, 0));
  }

  @override
  TextPosition getPosition(Offset offset) {
    if (offset.dx < indent && offset.dy < preferredLineHeight) {
      return marker.getPosition(offset);
    }
    final TextPosition position =
        content.getPosition(offset.translate(-indent, 0));
    return TextPosition(
      offset: position.offset + _markerLen,
      affinity: position.affinity,
    );
  }

  @override
  TextRange getWord(Offset offset) {
    if (offset.dx < indent && offset.dy < preferredLineHeight) {
      return marker.getWord(offset);
    }
    final TextRange range = content.getWord(offset.translate(-indent, 0));
    return TextRange(
      start: range.start + _markerLen,
      end: range.end + _markerLen,
    );
  }

  @override
  InlineSpan? getSpanForPosition(TextPosition position) {
    // Resolve against the ORIGINAL span tree, not the rebuilt marker/
    // content copies: callers pair this with the identity-based
    // getRangeForSpan and rely on recognizer/annotation spans surviving.
    if (position.offset >= length - 1) {
      return null;
    }
    return rootSpan.getSpanForPosition(position);
  }

  @override
  TextRange getRangeForSpan(InlineSpan span) {
    int offset = 0;
    rootSpan.visitChildren((child) {
      if (identical(child, span)) {
        return false;
      }
      offset += child.length;
      return true;
    });
    return TextRange(start: offset, end: offset + span.length);
  }

  @override
  TextRange getLineBoundary(TextPosition position) {
    if (position.offset < _markerLen) {
      final TextRange first =
          content.getLineBoundary(const TextPosition(offset: 0));
      return TextRange(start: 0, end: first.end + _markerLen);
    }
    final TextRange range = content.getLineBoundary(TextPosition(
      offset: position.offset - _markerLen,
      affinity: position.affinity,
    ));
    // The first visual line includes the marker chars, so Home reaches
    // the real line start.
    return TextRange(
      start: range.start == 0 ? 0 : range.start + _markerLen,
      end: range.end + _markerLen,
    );
  }

  @override
  Offset? getOffset(TextPosition position) {
    if (position.offset < _markerLen ||
        (position.offset == _markerLen &&
            position.affinity == TextAffinity.upstream)) {
      return marker.getOffset(position);
    }
    final Offset? offset = content.getOffset(TextPosition(
      offset: position.offset - _markerLen,
      affinity: position.affinity,
    ));
    return offset?.translate(indent, 0);
  }

  @override
  List<Rect> getRangeRects(TextRange range) {
    final List<Rect> rects = [];
    if (range.start < _markerLen) {
      rects.addAll(marker.getRangeRects(TextRange(
        start: range.start,
        end: min(range.end, _markerLen),
      )));
    }
    if (range.end > _markerLen) {
      rects.addAll(content
          .getRangeRects(TextRange(
            start: max(0, range.start - _markerLen),
            end: range.end - _markerLen,
          ))
          .map((rect) => rect.translate(indent, 0)));
    }
    return rects;
  }
}
