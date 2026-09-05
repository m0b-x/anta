import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Geometry contract of the fork's hanging-indent paragraph — the two-part
/// layout list lines get so soft-wrapped rows align under the content
/// instead of under the bullet.
///
/// **Round-trip restriction.** `getPosition(getOffset(p)) == p` is provable
/// only for a position with exactly one visual location. A soft-wrap
/// boundary offset has two (end of one row, start of the next) and the two
/// affinities resolve to different rows there, which is how
/// [_expectPositionRoundTrip] recognizes and skips it. Everywhere else the
/// downstream position must come back identical, and the upstream position
/// — which resolves to the same point — must come back with the same
/// offset (its affinity is the paragraph's answer, not ours).
///
/// The tests run against the test font, where every glyph advances by the
/// font size, so the marker widths below are exact rather than
/// platform-dependent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hanging paragraph', () {
    test('a bullet line splits into marker and content', () {
      final provider = _provider();
      final paragraph = provider.build(_bulletLine('buy milk'), _maxWidth);

      expect(provider.isHanging(paragraph), isTrue);
      expect(paragraph.length, '• buy milk'.length);
      expect(paragraph.trucated, isFalse);
    });

    test('word wrap off never takes the hanging path', () {
      final provider = _provider();
      final paragraph = provider.build(
        _bulletLine('buy milk'),
        double.infinity,
      );

      expect(provider.isHanging(paragraph), isFalse);
      // The bail-out precedes every paragraph build, so nothing was
      // measured on the way out.
      expect(provider.markerCacheLength, 0);
    });

    test(
      'a marker wider than half the viewport falls back to one paragraph',
      () {
        final provider = _provider();
        final span = CodeHangingTextSpan(
          hangingChars: 12,
          style: _base,
          children: const [
            TextSpan(text: '            ', style: _base),
            TextSpan(text: '• deeply nested', style: _base),
          ],
        );

        expect(provider.isHanging(provider.build(span, 100)), isFalse);
      },
    );

    test('positions round-trip through the marker and the content', () {
      final provider = _provider();

      for (final MapEntry<String, CodeHangingTextSpan> line
          in _sampleLines().entries) {
        _expectPositionRoundTrip(
          provider.build(line.value, _maxWidth),
          line.key,
        );
      }
    });

    test('the seam resolves to one x whatever the affinity', () {
      final provider = _provider();

      for (final MapEntry<String, CodeHangingTextSpan> line
          in _sampleLines().entries) {
        final IParagraph paragraph = provider.build(line.value, _maxWidth);
        final int seam = line.value.hangingChars;
        final Offset? downstream = paragraph.getOffset(
          TextPosition(offset: seam),
        );
        final Offset? upstream = paragraph.getOffset(
          TextPosition(offset: seam, affinity: TextAffinity.upstream),
        );

        expect(downstream, isNotNull, reason: line.key);
        expect(upstream, downstream, reason: line.key);
        expect(
          paragraph.getPosition(downstream!).offset,
          seam,
          reason: line.key,
        );
      }
    });

    test('range rects cover the marker and every row in visual order', () {
      final provider = _provider();
      final CodeHangingTextSpan span = _wrappingBulletLine();
      final IParagraph paragraph = provider.build(span, _maxWidth);
      final double indent = paragraph
          .getOffset(TextPosition(offset: span.hangingChars))!
          .dx;

      expect(
        paragraph.lineCount,
        greaterThan(1),
        reason: 'the sample content must wrap for this to mean anything',
      );

      final List<Rect> rects = paragraph.getRangeRects(
        TextRange(start: 0, end: paragraph.length),
      );

      expect(rects.first.left, 0);
      expect(rects.first.top, lessThan(paragraph.preferredLineHeight));
      expect(rects.map((rect) => rect.top).toSet().length, paragraph.lineCount);
      for (int i = 1; i < rects.length; i++) {
        final Rect previous = rects[i - 1];
        final Rect rect = rects[i];
        if (rect.top == previous.top) {
          // No gap along a row: the floored indent has the marker's rect
          // reach at least the content's left edge.
          expect(
            rect.left,
            lessThanOrEqualTo(previous.right),
            reason: 'gap between rect ${i - 1} and $i',
          );
        } else {
          expect(rect.top, greaterThan(previous.top));
          expect(rect.left, indent, reason: 'row $i starts under the content');
        }
      }
    });

    test(
      'height covers the taller part and keeps the line-height identity',
      () {
        final provider = _provider();
        final CodeHangingTextSpan span = _wrappingBulletLine();
        final IParagraph paragraph = provider.build(span, _maxWidth);
        final IParagraph markerOnly = provider.build(
          provider.truncate(span, span.hangingChars),
          _maxWidth,
        );

        expect(paragraph.height, greaterThanOrEqualTo(markerOnly.height));
        expect(paragraph.lineCount, greaterThanOrEqualTo(markerOnly.lineCount));
        expect(
          paragraph.height,
          paragraph.lineCount * paragraph.preferredLineHeight,
        );
      },
    );

    test('a fractional marker advance leaves no gap before the content', () {
      // 13.7 px glyphs put the marker's advance at 27.4: a ceiled indent
      // would start the content past the marker's rects and open a gap,
      // where the floored one has them overlap by 0.4 px.
      const TextStyle style = TextStyle(fontSize: 13.7, height: 1.4);
      final CodeParagraphProviderForTesting provider =
          CodeParagraphProviderForTesting()..updateBaseStyle(style);
      final CodeHangingTextSpan span = CodeHangingTextSpan(
        hangingChars: 2,
        style: style,
        children: const [
          TextSpan(text: '• ', style: style),
          TextSpan(text: 'buy milk', style: style),
        ],
      );
      final IParagraph paragraph = provider.build(span, _maxWidth);

      expect(paragraph.getOffset(const TextPosition(offset: 2))!.dx, 27);

      final List<Rect> rects = paragraph.getRangeRects(
        TextRange(start: 0, end: paragraph.length),
      );
      expect(rects, hasLength(2));
      expect(rects[1].left, lessThan(rects[0].right));
    });

    test('a heading-scaled list line lays out under its own line height', () {
      final provider = _provider();
      final IParagraph body = provider.build(
        _bulletLine('buy milk'),
        _maxWidth,
      );
      final IParagraph heading = provider.build(_headingLine(), _maxWidth);

      expect(provider.isHanging(heading), isTrue);
      expect(
        heading.preferredLineHeight,
        greaterThan(body.preferredLineHeight),
      );
      expect(heading.height, heading.lineCount * heading.preferredLineHeight);
    });
  });

  group('piecewise geometry queries', () {
    test('getWord resolves inside the marker and inside the content', () {
      final provider = _provider();
      final IParagraph paragraph = provider.build(
        _bulletLine('buy milk'),
        _maxWidth,
      );
      const int markerLen = 2;

      final TextRange inMarker = paragraph.getWord(const Offset(3, 5));
      expect(inMarker.start, 0);
      expect(
        inMarker.end,
        lessThanOrEqualTo(markerLen),
        reason: 'a marker word may never cross the seam',
      );

      // x = indent + one glyph: the second letter of 'buy'.
      final TextRange inContent = paragraph.getWord(
        const Offset(2 * kGlyph + kGlyph, 5),
      );
      expect(
        inContent,
        const TextRange(start: markerLen, end: markerLen + 3),
        reason: 'the content result is offset by the marker length',
      );
    });

    test('getLineBoundary maps the marker row and every wrapped row', () {
      final provider = _provider();
      final IParagraph paragraph = provider.build(
        _wrappingBulletLine(),
        _maxWidth,
      );
      expect(paragraph.lineCount, 4);

      // Content rows are [0,9) [9,20) [20,31) [31,36) at this width, so
      // the first visual row of the line is the marker plus [0,9).
      const TextRange firstRow = TextRange(start: 0, end: 11);
      expect(
        paragraph.getLineBoundary(const TextPosition(offset: 0)),
        firstRow,
      );
      expect(
        paragraph.getLineBoundary(const TextPosition(offset: 1)),
        firstRow,
      );
      expect(
        paragraph.getLineBoundary(const TextPosition(offset: 5)),
        firstRow,
      );

      final TextRange secondRow = paragraph.getLineBoundary(
        const TextPosition(offset: 15),
      );
      expect(secondRow, const TextRange(start: 11, end: 22));
      expect(
        secondRow.start,
        isNot(0),
        reason: 'Home on a wrapped row must stay on that row',
      );
      expect(
        paragraph.getLineBoundary(const TextPosition(offset: 25)),
        const TextRange(start: 22, end: 33),
      );
    });

    test('getRangeRects walks a mid-marker range through both parts', () {
      final provider = _provider();
      final IParagraph paragraph = provider.build(
        _wrappingBulletLine(),
        _maxWidth,
      );

      // From the middle of the marker to the middle of content row 2.
      final List<Rect> rects = paragraph.getRangeRects(
        const TextRange(start: 1, end: 25),
      );

      expect(rects, hasLength(4));
      expect(rects.first.left, kGlyph, reason: 'starts mid-marker');
      expect(rects.first.right, _indent);
      for (final Rect rect in rects.skip(1)) {
        expect(
          rect.left,
          greaterThanOrEqualTo(_indent),
          reason: 'content rects are translated by the indent',
        );
      }
      for (int i = 1; i < rects.length; i++) {
        expect(rects[i].top, greaterThanOrEqualTo(rects[i - 1].top));
      }
      expect(
        rects.last.top,
        greaterThan(paragraph.preferredLineHeight * 2 - 1),
        reason: 'the range ends on the third visual row',
      );
    });

    test('getRangeRects for a range inside one wrapped content row', () {
      final provider = _provider();
      final IParagraph paragraph = provider.build(
        _wrappingBulletLine(),
        _maxWidth,
      );

      // Content offsets [11,16): entirely inside row 1.
      final List<Rect> rects = paragraph.getRangeRects(
        const TextRange(start: 13, end: 18),
      );

      expect(rects, hasLength(1));
      expect(rects.single.left, _indent + 2 * kGlyph);
      expect(rects.single.right, _indent + 7 * kGlyph);
      expect(
        rects.single.top,
        greaterThanOrEqualTo(paragraph.preferredLineHeight),
      );
      expect(rects.single.top, lessThan(paragraph.preferredLineHeight * 2));
    });
  });

  group('hanging fallbacks', () {
    test('a non-positive hangingChars falls back to one paragraph', () {
      final provider = _provider();
      final span = CodeHangingTextSpan(
        hangingChars: 0,
        style: _base,
        children: const [TextSpan(text: '• buy milk', style: _base)],
      );

      expect(provider.isHanging(provider.build(span, _maxWidth)), isFalse);
      expect(provider.markerCacheLength, 0);
    });

    test('a hangingChars covering the whole line falls back', () {
      final provider = _provider();
      final CodeHangingTextSpan bullet = _bulletLine('buy milk');
      final span = CodeHangingTextSpan(
        hangingChars: bullet.toPlainText().length,
        style: _base,
        children: bullet.children,
      );

      expect(provider.isHanging(provider.build(span, _maxWidth)), isFalse);
      expect(provider.markerCacheLength, 0);
    });

    test('a truncated line falls back', () {
      final provider = _provider()..updateMaxLengthSingleLineRendering(4);
      final IParagraph paragraph = provider.build(
        _bulletLine('buy milk'),
        _maxWidth,
      );

      expect(paragraph.trucated, isTrue);
      expect(provider.isHanging(paragraph), isFalse);
      expect(provider.markerCacheLength, 0);
    });
  });

  group('marker measurement cache', () {
    test('equal markers are measured once, and clearCache empties it', () {
      final provider = _provider();

      provider.build(_bulletLine('buy milk'), _maxWidth);
      expect(provider.markerCacheLength, 1);

      provider.build(_bulletLine('call the gym'), _maxWidth);
      expect(provider.markerCacheLength, 1);

      provider.build(_orderedLine('first set'), _maxWidth);
      expect(provider.markerCacheLength, 2);

      provider.clearCache();
      expect(provider.markerCacheLength, 0);
    });

    test('a marker in another style is measured separately', () {
      final provider = _provider();

      provider.build(_bulletLine('buy milk'), _maxWidth);
      provider.build(_headingLine(), _maxWidth);

      expect(provider.markerCacheLength, 2);
    });

    test('the cache is bounded at 128 and touched on every hit', () {
      final provider = _provider();
      for (var i = 1; i <= 128; i++) {
        provider.build(_orderedLine('set $i', number: i), _maxWidth);
      }
      expect(provider.markerCacheLength, 128);

      // A different line under marker 1: the paragraph cache misses, so
      // the marker is looked up again and moves to the tail.
      provider.build(_orderedLine('again', number: 1), _maxWidth);
      expect(provider.markerCacheLength, 128);

      provider.build(_orderedLine('overflow', number: 129), _maxWidth);

      expect(provider.markerCacheLength, 128);
      expect(
        provider.markerCacheContains(_markerOf(provider, number: 1)),
        isTrue,
        reason: 'the re-used marker was touched, so it is not the head',
      );
      expect(
        provider.markerCacheContains(_markerOf(provider, number: 2)),
        isFalse,
        reason: 'the untouched head is the one that goes',
      );
    });

    test('updateBaseStyle empties the marker cache', () {
      final provider = _provider();
      provider.build(_bulletLine('buy milk'), _maxWidth);
      expect(provider.markerCacheLength, 1);

      provider.updateBaseStyle(_base.copyWith(color: const Color(0xFF123456)));
      expect(provider.markerCacheLength, 0);
    });

    test('updateMaxLengthSingleLineRendering empties the marker cache', () {
      final provider = _provider();
      provider.build(_bulletLine('buy milk'), _maxWidth);
      expect(provider.markerCacheLength, 1);

      provider.updateMaxLengthSingleLineRendering(4096);
      expect(provider.markerCacheLength, 0);
    });
  });

  group('span splitting', () {
    test('every split point preserves the line\'s plain text', () {
      final provider = _provider();

      for (final MapEntry<String, CodeHangingTextSpan> line
          in _sampleLines().entries) {
        final String plain = line.value.toPlainText(includePlaceholders: true);
        for (int split = 0; split <= plain.length; split++) {
          final TextSpan marker = provider.truncate(line.value, split);
          final TextSpan content = provider.dropPrefix(line.value, split);

          expect(
            marker.toPlainText(includePlaceholders: true) +
                content.toPlainText(includePlaceholders: true),
            plain,
            reason: '${line.key} split at $split',
          );
          _expectNoEmptyChildren(marker, '${line.key} marker at $split');
          _expectNoEmptyChildren(content, '${line.key} content at $split');
        }
      }
    });

    test('untouched subtrees survive both splits by identity', () {
      final provider = _provider();
      const TextSpan bullet = TextSpan(text: '• ', style: _base);
      const TextSpan lead = TextSpan(text: 'call ', style: _base);
      const CodeDecoratedTextSpan tag = CodeDecoratedTextSpan(
        decoration: CodeTextDecoration(color: Color(0xFF00FF00), radius: 4),
        text: '#gym',
        style: _base,
      );
      final CodeHangingTextSpan span = CodeHangingTextSpan(
        hangingChars: 2,
        style: _base,
        children: const [bullet, lead, tag],
      );

      final TextSpan content = provider.dropPrefix(span, 2);
      expect(content.children, hasLength(2));
      expect(identical(content.children!.first, lead), isTrue);
      expect(identical(content.children!.last, tag), isTrue);

      final TextSpan marker = provider.truncate(span, 4);
      expect(identical(marker.children!.first, bullet), isTrue);
      expect(marker.children, hasLength(2));
    });

    test('a decoration survives a split through the middle of its run', () {
      final provider = _provider();
      const CodeTextDecoration decoration = CodeTextDecoration(
        color: Color(0xFF00FF00),
        radius: 4,
      );
      const CodeDecoratedTextSpan chip = CodeDecoratedTextSpan(
        decoration: decoration,
        text: '#gym',
        style: _base,
      );
      const CodeHangingTextSpan span = CodeHangingTextSpan(
        hangingChars: 2,
        style: _base,
        children: [
          TextSpan(text: '• ', style: _base),
          chip,
        ],
      );

      // Cut the chip in half: '• #g' | 'ym'.
      final InlineSpan head = provider.truncate(span, 4).children!.last;
      final InlineSpan tail = provider.dropPrefix(span, 4).children!.single;

      expect(head, isA<CodeDecoratedTextSpan>());
      expect((head as CodeDecoratedTextSpan).decoration, decoration);
      expect(head.toPlainText(), '#g');
      expect(tail, isA<CodeDecoratedTextSpan>());
      expect((tail as CodeDecoratedTextSpan).decoration, decoration);
      expect(tail.toPlainText(), 'ym');
    });

    test('a fully consumed subtree is dropped, not emitted empty', () {
      final provider = _provider();
      final CodeHangingTextSpan span = _bulletLine('buy milk');

      final TextSpan content = provider.dropPrefix(span, 2);
      expect(content.text, isNull);
      expect(content.children, hasLength(1));

      final TextSpan nothing = provider.dropPrefix(
        span,
        span.toPlainText().length,
      );
      expect(nothing.text, isNull);
      expect(nothing.children, isNull);
    });
  });

  group('debug contracts', () {
    test('a scaled root that changes the strut font family is rejected', () {
      final provider = _provider();
      final TextStyle rootStyle = _base.copyWith(
        fontSize: 20,
        fontFamily: 'NotTheBaseFont',
      );

      expect(
        () => provider.build(
          TextSpan(
            style: rootStyle,
            children: [TextSpan(text: 'heading', style: rootStyle)],
          ),
          _maxWidth,
        ),
        throwsAssertionError,
      );
    });

    test('a scaled root that changes the strut height is rejected', () {
      final provider = _provider();
      final TextStyle rootStyle = _base.copyWith(fontSize: 20, height: 2.2);

      expect(
        () => provider.build(
          TextSpan(
            style: rootStyle,
            children: [TextSpan(text: 'heading', style: rootStyle)],
          ),
          _maxWidth,
        ),
        throwsAssertionError,
      );
    });

    test('a placeholder taller than the line is rejected', () {
      final provider = _provider();

      expect(
        () => provider.build(
          const TextSpan(
            style: _base,
            children: [
              TextSpan(text: 'a', style: _base),
              _TestBoxSpan(side: 99, tag: 'oversized'),
            ],
          ),
          _maxWidth,
        ),
        throwsAssertionError,
      );
    });
  });
}

const TextStyle _base = TextStyle(fontSize: 14, height: 1.4);
const double _maxWidth = 200;

/// The test font advances every glyph by the font size, so a column
/// index times this is an exact x offset.
const double kGlyph = 14;

/// Advance of the two-character `• ` marker — the indent every content
/// rect of a [_bulletLine] is translated by.
const double _indent = 2 * kGlyph;

CodeParagraphProviderForTesting _provider() =>
    CodeParagraphProviderForTesting()..updateBaseStyle(_base);

/// A bullet list line: `• ` marker, plain content.
CodeHangingTextSpan _bulletLine(String content) => CodeHangingTextSpan(
  hangingChars: 2,
  style: _base,
  children: [
    const TextSpan(text: '• ', style: _base),
    TextSpan(text: content, style: _base),
  ],
);

/// An ordered list line: `1. ` marker, or `$number. ` when given — the
/// cheapest way to mint many distinct markers in one style.
CodeHangingTextSpan _orderedLine(String content, {int number = 1}) {
  final String marker = '$number. ';
  return CodeHangingTextSpan(
    hangingChars: marker.length,
    style: _base,
    children: [
      TextSpan(text: marker, style: _base),
      TextSpan(text: content, style: _base),
    ],
  );
}

/// The marker span the provider keys its measurement cache on for
/// [_orderedLine] — the same `truncate` the hanging split runs.
TextSpan _markerOf(
  CodeParagraphProviderForTesting provider, {
  required int number,
}) {
  final CodeHangingTextSpan line = _orderedLine('anything', number: number);
  return provider.truncate(line, line.hangingChars);
}

/// A task line whose marker carries a painted placeholder box in place of
/// the `[` code unit, exactly as the app's checkbox span does.
CodeHangingTextSpan _taskLine(String content) => CodeHangingTextSpan(
  hangingChars: 6,
  style: _base,
  children: [
    const TextSpan(text: '- ', style: _base),
    const _TestBoxSpan(side: 12),
    const TextSpan(text: ' ] ', style: _base),
    TextSpan(text: content, style: _base),
  ],
);

/// A nested bullet: four spaces of indent before the marker.
CodeHangingTextSpan _nestedLine(String content) => CodeHangingTextSpan(
  hangingChars: 6,
  style: _base,
  children: [
    const TextSpan(text: '    • ', style: _base),
    TextSpan(text: content, style: _base),
  ],
);

/// A line whose content carries a decorated (chip-painted) run.
CodeHangingTextSpan _decoratedLine() => const CodeHangingTextSpan(
  hangingChars: 2,
  style: _base,
  children: [
    TextSpan(text: '• ', style: _base),
    TextSpan(text: 'call ', style: _base),
    CodeDecoratedTextSpan(
      decoration: CodeTextDecoration(color: Color(0xFF00FF00), radius: 4),
      text: '#gym',
      style: _base,
    ),
    TextSpan(text: ' later', style: _base),
  ],
);

/// A bullet line whose content is long enough to soft-wrap at [_maxWidth].
CodeHangingTextSpan _wrappingBulletLine() =>
    _bulletLine('buy milk bread eggs and coffee beans');

/// A heading-scaled list line: the root sets a larger fontSize and a bolder
/// weight, but keeps the base style's strut inputs.
CodeHangingTextSpan _headingLine() {
  final TextStyle style = _base.copyWith(
    fontSize: 20,
    fontWeight: FontWeight.bold,
  );
  return CodeHangingTextSpan(
    hangingChars: 2,
    style: style,
    children: [
      TextSpan(text: '• ', style: style),
      TextSpan(text: 'weekly plan', style: style),
    ],
  );
}

Map<String, CodeHangingTextSpan> _sampleLines() => {
  'bullet': _bulletLine('buy milk'),
  'ordered': _orderedLine('first set'),
  'task': _taskLine('warm up'),
  'nested': _nestedLine('sub item'),
  'decorated': _decoratedLine(),
  'wrapping': _wrappingBulletLine(),
  'heading': _headingLine(),
};

/// Asserts the position/offset round trip for every unambiguous offset of
/// [paragraph] — see the file's doc comment for which offsets those are.
void _expectPositionRoundTrip(IParagraph paragraph, String label) {
  var checked = 0;
  for (int offset = 0; offset < paragraph.length; offset++) {
    final TextPosition position = TextPosition(offset: offset);
    final Offset? downstream = paragraph.getOffset(position);
    expect(downstream, isNotNull, reason: '$label: no offset for $offset');
    final Offset? upstream = paragraph.getOffset(
      TextPosition(offset: offset, affinity: TextAffinity.upstream),
    );
    if (upstream == null || upstream.dy != downstream!.dy) {
      // A soft-wrap boundary: the offset sits at the end of one row and
      // the start of the next, so no single point identifies it.
      continue;
    }
    expect(
      paragraph.getPosition(downstream),
      position,
      reason: '$label: offset $offset',
    );
    if (upstream == downstream) {
      expect(
        paragraph.getPosition(upstream).offset,
        offset,
        reason: '$label: upstream offset $offset',
      );
    }
    checked++;
  }
  expect(
    checked,
    greaterThan(paragraph.length ~/ 2),
    reason: '$label: too many offsets skipped to prove anything',
  );
}

/// Asserts no node inside a `children` list is empty — a split must drop a
/// fully consumed subtree rather than emit `TextSpan(text: '')`.
void _expectNoEmptyChildren(InlineSpan span, String reason) {
  if (span is! TextSpan) {
    return;
  }
  final List<InlineSpan>? children = span.children;
  if (children == null) {
    return;
  }
  for (final InlineSpan child in children) {
    if (child is TextSpan) {
      final String? text = child.text;
      final List<InlineSpan>? grandChildren = child.children;
      expect(
        (text != null && text.isNotEmpty) ||
            (grandChildren != null && grandChildren.isNotEmpty),
        isTrue,
        reason: '$reason: empty child span',
      );
      _expectNoEmptyChildren(child, reason);
    }
  }
}

/// A painted placeholder standing in for the app's checkbox/money spans:
/// one code unit wide in the plain text, value-equal so the marker cache
/// can key on the span that holds it.
class _TestBoxSpan extends CodeInlinePaintSpan {
  const _TestBoxSpan({required double side, this.tag = 'box'})
    : super(width: side, height: side);

  final String tag;

  @override
  void paint(Canvas canvas, Rect rect) {}

  @override
  bool operator ==(Object other) =>
      other is _TestBoxSpan &&
      other.width == width &&
      other.height == height &&
      other.tag == tag;

  @override
  int get hashCode => Object.hash(width, height, tag);
}
