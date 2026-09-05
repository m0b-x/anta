import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/line_based_markdown_builder.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/money_display_config.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Preview-side guards for the three things `LineBasedMarkdownBuilder`
/// owns beyond span shape: which tap recognizer a nested zone resolves
/// to, that search highlighting never duplicates or drops a code unit,
/// and that the recognizer cache is pruned when a chunk is evicted.
///
/// Nothing here pumps a widget — the builder takes a resolved
/// [LineMarkdownStyle], not a `BuildContext` — but the binding is still
/// needed because built runs lay out through dart:ui.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nested tap zones', () {
    test('a ghost inside link text keeps its own tap', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = 'a [see {{ what }}](https://x.dev) b';
      builder.prepare(line);
      final span = builder.buildLine(line, 0);

      _fire(span, ' what ');
      expect(calls.ghosts, 1, reason: 'the ghost never fired');
      expect(calls.links, isEmpty, reason: 'the link stole the ghost tap');
    });

    test('the link text around a ghost still opens the link', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = 'a [see {{ what }}](https://x.dev) b';
      builder.prepare(line);
      final span = builder.buildLine(line, 0);

      _fire(span, 'see ');
      expect(calls.links, <String>['https://x.dev']);
      expect(calls.ghosts, 0);
    });

    test('a tag inside link text yields to the link', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = '[see #tag](https://x.dev)';
      builder.prepare(line);
      final span = builder.buildLine(line, 0);

      _fire(span, '#tag');
      expect(calls.links, <String>['https://x.dev']);
      expect(calls.tags, isEmpty, reason: 'only ghosts outrank a link');
    });
  });

  group('search highlighting', () {
    const line = 'abcdefgh';

    void expectRoundTrip(List<TextRange> highlights, String reason) {
      final builder = LineBasedMarkdownBuilder(
        style: _style,
        colorPalette: MarkdownColorPalette.presets,
        searchHighlights: highlights,
      );
      addTearDown(builder.dispose);
      builder.prepare(line);
      expect(_text(builder.buildLine(line, 0)), line, reason: reason);
    }

    test('a range starting inside the previous one emits each unit once', () {
      expectRoundTrip(const <TextRange>[
        TextRange(start: 0, end: 4),
        TextRange(start: 2, end: 6),
      ], 'overlapping ranges duplicated text');
    });

    test('a range nested in the previous one emits each unit once', () {
      expectRoundTrip(const <TextRange>[
        TextRange(start: 0, end: 6),
        TextRange(start: 2, end: 4),
      ], 'a nested range duplicated text');
    });

    test('coincident ranges emit each unit once', () {
      expectRoundTrip(const <TextRange>[
        TextRange(start: 1, end: 5),
        TextRange(start: 1, end: 5),
      ], 'coincident ranges duplicated text');
    });

    test('adjacent ranges are unchanged', () {
      expectRoundTrip(const <TextRange>[
        TextRange(start: 0, end: 2),
        TextRange(start: 2, end: 4),
      ], 'adjacent ranges changed the text');
    });

    test('the current match wins when two ranges coincide', () {
      final builder = LineBasedMarkdownBuilder(
        style: _style,
        colorPalette: MarkdownColorPalette.presets,
        searchHighlights: const <TextRange>[
          TextRange(start: 1, end: 5),
          TextRange(start: 1, end: 5),
        ],
        currentHighlightIndex: 1,
      );
      addTearDown(builder.dispose);
      builder.prepare(line);
      final painted = _leaves(builder.buildLine(line, 0))
          .where(
            (l) => l.style?.backgroundColor == _style.currentHighlightColor,
          )
          .map((l) => l.text)
          .join();
      expect(painted, 'bcde');
    });
  });

  // The recognizer cache is keyed by construct and source offset and
  // pruned per chunk on LRU eviction. A link key that the prune cannot
  // parse leaks its recognizer for the life of the builder, so pin that
  // an evicted chunk really drops it: rebuilding the chunk must mint a
  // new instance, not hand back the stale one.
  test('an evicted chunk drops its link recognizers', () {
    final calls = _Calls();
    final lines = <String>[
      '[a](https://x.dev)',
      for (var i = 0; i < 80; i++) 'line $i',
    ];
    final builder = LineBasedMarkdownBuilder(
      style: _style,
      colorPalette: MarkdownColorPalette.presets,
      onLinkTap: calls.onLink,
      linesPerChunk: 1,
    );
    addTearDown(builder.dispose);
    builder.prepare(lines.join('\n'));

    final first = _recognizerOf(builder.buildChunk(0), 'a');
    expect(first, isNotNull);
    for (var i = 1; i < 80; i++) {
      builder.buildChunk(i);
    }
    final second = _recognizerOf(builder.buildChunk(0), 'a');
    expect(second, isNotNull);
    expect(
      identical(first, second),
      isFalse,
      reason: 'the evicted chunk kept its link recognizer alive',
    );
  });

  test('clearCache drops every recognizer', () {
    final calls = _Calls();
    final builder = _builder(calls);
    const line = '[a](https://x.dev)';
    builder.prepare(line);
    final first = _recognizerOf(<InlineSpan>[builder.buildLine(line, 0)], 'a');
    builder.clearCache();
    final second = _recognizerOf(<InlineSpan>[builder.buildLine(line, 0)], 'a');
    expect(identical(first, second), isFalse);
  });

  // The bullet glyph cycles by nesting depth, and both list surfaces —
  // a plain bullet row and a money row wearing list chrome — read it
  // from the one [MarkdownListSyntax.bulletGlyph] table, so a nested
  // `- $+ 5` cannot end up with a different marker than the `- b` above
  // it.
  group('bullet glyph by depth', () {
    test('cycles through the three glyphs as the indent grows', () {
      const lines = <String>['- a', '  - b', '    - c', '      - d'];
      final builder = LineBasedMarkdownBuilder(
        style: _style,
        colorPalette: MarkdownColorPalette.presets,
      );
      addTearDown(builder.dispose);
      builder.prepare(lines.join('\n'));

      expect(
        [
          for (var i = 0; i < lines.length; i++)
            _listMarker(builder.buildLine(lines[i], i)),
        ],
        ['• ', '◦ ', '▪ ', '• '],
      );
    });

    test('a nested money row wears the same marker as its depth', () {
      const line = '  - \$+ 5 x';
      final builder = LineBasedMarkdownBuilder(
        style: _style,
        colorPalette: MarkdownColorPalette.presets,
        moneyConfig: const MoneyDisplayConfig(enabled: true),
      );
      addTearDown(builder.dispose);
      builder.prepare(line);

      expect(_listMarker(builder.buildLine(line, 0)), '◦ ');
    });
  });

  // A nested quote draws one bar per `>` marker, whatever spacing the
  // source uses between them, and a callout body nests inside its block
  // the same way.
  group('nested quote bars', () {
    String barsOf(String line, {List<String> above = const <String>[]}) {
      final source = <String>[...above, line];
      final builder = LineBasedMarkdownBuilder(
        style: _style,
        colorPalette: MarkdownColorPalette.presets,
      );
      addTearDown(builder.dispose);
      builder.prepare(source.join('\n'));
      return _text(builder.buildLine(line, above.length));
    }

    test('one bar per marker, packed however the source spaced them', () {
      expect(barsOf('>> a'), '┃┃ a');
      expect(barsOf('> > a'), '┃┃ a');
      expect(barsOf('>>> a'), '┃┃┃ a');
    });

    test('a callout body nests inside its block', () {
      expect(barsOf('>> note', above: <String>['> [!TIP] x']), '┃┃ note');
    });
  });

  // The table predicates are [MarkdownLineShape]'s, shared with the
  // live editor and the paste policies. A row with trailing whitespace
  // is a table row now — the preview used to reject it, which is the
  // one behaviour delta of moving the regexes.
  group('table rows', () {
    String render(String line) {
      final builder = LineBasedMarkdownBuilder(
        style: _style,
        colorPalette: MarkdownColorPalette.presets,
      );
      addTearDown(builder.dispose);
      builder.prepare(line);
      return _text(builder.buildLine(line, 0));
    }

    test('a row with trailing whitespace is still a row', () {
      expect(render('| a | b |  '), 'a │ b');
    });

    test('a separator row draws the rule', () {
      expect(render('|---|'), '─' * 30);
    });
  });

  test('inline code renders at the shared scale', () {
    final builder = LineBasedMarkdownBuilder(
      style: _style,
      colorPalette: MarkdownColorPalette.presets,
    );
    addTearDown(builder.dispose);
    const line = 'a `code` b';
    builder.prepare(line);
    final code = _leaves(
      builder.buildLine(line, 0),
    ).firstWhere((leaf) => leaf.text == 'code');

    expect(
      code.style?.fontSize,
      _style.baseFontSize * MarkdownConstants.inlineCodeScale,
    );
  });

  // A quote's content keeps its true source offset even when the marker
  // run is followed by more blanks than the grammar consumes: the shape
  // hands back one space, the extra two belong to the content, and a
  // search highlight on the `a` must land on the `a`.
  test('quote content keeps its source offset past extra blanks', () {
    const line = '>   a';
    final at = line.indexOf('a');
    final builder = LineBasedMarkdownBuilder(
      style: _style,
      colorPalette: MarkdownColorPalette.presets,
      searchHighlights: <TextRange>[TextRange(start: at, end: at + 1)],
    );
    addTearDown(builder.dispose);
    builder.prepare(line);

    final painted = _leaves(builder.buildLine(line, 0))
        .where((leaf) => leaf.style?.backgroundColor == _style.highlightColor)
        .map((leaf) => leaf.text)
        .join();
    expect(painted, 'a');
  });
}

/// The marker text of a list row. The preview lays a list item — plain
/// or money — out as a [WidgetSpan] holding a `Row` whose first child is
/// the bullet / number.
String _listMarker(InlineSpan root) {
  final widgets = <WidgetSpan>[];
  void visit(InlineSpan span) {
    if (span is WidgetSpan) widgets.add(span);
    if (span is TextSpan) span.children?.forEach(visit);
  }

  visit(root);
  expect(widgets, hasLength(1), reason: 'the row is one WidgetSpan');
  final padding = widgets.single.child as Padding;
  final styled = padding.child! as DefaultTextStyle;
  final row = styled.child as Row;
  return (row.children.first as Text).data!;
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

const Color _baseColor = Color(0xFF202124);

final LineMarkdownStyle _style = LineMarkdownStyle.fromTheme(
  ThemeData(useMaterial3: true, brightness: Brightness.light),
  16.0,
  textColor: _baseColor,
);

/// Records which of the builder's tap callbacks fired.
class _Calls {
  final List<String> links = <String>[];
  final List<String> tags = <String>[];
  int ghosts = 0;

  void onLink(String url) => links.add(url);
  void onTag(String tag) => tags.add(tag);
  void onGhost(int start, int end) => ghosts++;
}

LineBasedMarkdownBuilder _builder(_Calls calls) {
  final builder = LineBasedMarkdownBuilder(
    style: _style,
    colorPalette: MarkdownColorPalette.presets,
    onLinkTap: calls.onLink,
    onTagTap: calls.onTag,
    onGhostTap: calls.onGhost,
  );
  addTearDown(builder.dispose);
  return builder;
}

/// Every [TextSpan] in [root] carrying text, in document order.
List<TextSpan> _leaves(InlineSpan root) {
  final out = <TextSpan>[];
  void visit(InlineSpan span) {
    if (span is TextSpan) {
      final text = span.text;
      if (text != null && text.isNotEmpty) out.add(span);
      final children = span.children;
      if (children != null) children.forEach(visit);
    }
  }

  visit(root);
  return out;
}

String _text(InlineSpan root) => _leaves(root).map((s) => s.text).join();

/// Invokes the tap recognizer of the first leaf whose text is [text],
/// which is exactly what a tap landing on that glyph would do.
void _fire(InlineSpan root, String text) {
  final leaf = _leaves(root).firstWhere(
    (s) => s.text == text,
    orElse: () => throw StateError('no leaf renders "$text"'),
  );
  final recognizer = leaf.recognizer;
  expect(recognizer, isA<TapGestureRecognizer>(), reason: 'leaf "$text"');
  (recognizer! as TapGestureRecognizer).onTap!();
}

GestureRecognizer? _recognizerOf(List<InlineSpan> spans, String text) {
  for (final span in spans) {
    for (final leaf in _leaves(span)) {
      if (leaf.text == text) return leaf.recognizer;
    }
  }
  return null;
}
