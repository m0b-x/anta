import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/line_based_markdown_builder.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/markdown_link_patterns.dart';
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

  group('link destinations and autolinks', () {
    String opened(String line, String leaf) {
      final calls = _Calls();
      final builder = _builder(calls);
      builder.prepare(line);
      _fire(builder.buildLine(line, 0), leaf);
      return calls.links.single;
    }

    test('a link title is never opened', () {
      expect(opened('[t](https://x.com/s "Guide")', 't'), 'https://x.com/s');
    });

    test('balanced parentheses open whole and leave no stray paren', () {
      const line = '[w](https://en.wikipedia.org/wiki/Foo_(bar)) x';
      final calls = _Calls();
      final builder = _builder(calls);
      builder.prepare(line);
      final span = builder.buildLine(line, 0);
      expect(_text(span), 'w x');
      _fire(span, 'w');
      expect(calls.links.single, 'https://en.wikipedia.org/wiki/Foo_(bar)');
    });

    test('an angle destination opens without its brackets', () {
      expect(opened('[t](<a b>)', 't'), 'a b');
    });

    test('a bare url keeps its balanced parentheses', () {
      const url = 'https://en.wikipedia.org/wiki/Squat_(exercise)';
      expect(opened('see $url.', url), url);
      expect(opened('(https://x.y).', 'https://x.y'), 'https://x.y');
    });

    test('an angle autolink drops its brackets and opens its inside', () {
      const line = 'see <https://x.y> now';
      final calls = _Calls();
      final builder = _builder(calls);
      builder.prepare(line);
      final span = builder.buildLine(line, 0);
      expect(_text(span), 'see https://x.y now');
      final url = _leaves(span).singleWhere((s) => s.text == 'https://x.y');
      expect(url.style?.color, _style.primaryColor);
      _fire(span, 'https://x.y');
      expect(calls.links, <String>['https://x.y']);
    });

    test('an address in angle brackets opens as mailto', () {
      expect(
        opened('<me@example.com>', 'me@example.com'),
        'mailto:me@example.com',
      );
    });
  });

  group('images', () {
    test('a mid-line image shows the glyph and its alt dimmed', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = 'a ![leg day](https://x.y/a.png "T") b';
      builder.prepare(line);
      final span = builder.buildLine(line, 0);

      expect(_text(span), 'a ${MarkdownLinkPatterns.imageGlyph}leg day b');
      final alt = _leaves(span).singleWhere((s) => s.text == 'leg day');
      expect(alt.style?.color, _style.ghostColor);
      _fire(span, 'leg day');
      expect(calls.links, <String>['https://x.y/a.png']);
    });

    test('a whole-line image keeps its placeholder and opens the dest', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = '![plan](https://x.y/a.png "T")';
      builder.prepare(line);
      final span = builder.buildLine(line, 0);

      expect(_text(span), '🖼 plan');
      _fire(span, 'plan');
      expect(calls.links, <String>['https://x.y/a.png']);
    });

    test('balanced parens in a whole-line image keep the placeholder', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = '![a](https://x/Foo_(b))';
      builder.prepare(line);
      final span = builder.buildLine(line, 0);

      expect(_text(span), '🖼 a');
      _fire(span, 'a');
      expect(calls.links, <String>['https://x/Foo_(b)']);
    });

    test('a whole-line image with an empty alt keeps the placeholder', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = '![](https://x.y/a.png)';
      builder.prepare(line);
      final span = builder.buildLine(line, 0);

      expect(_text(span), '🖼 Image');
      _fire(span, 'Image');
      expect(calls.links, <String>['https://x.y/a.png']);
    });

    test('a mid-line image with an empty alt is the glyph alone', () {
      final builder = _builder(_Calls());
      const line = 'a ![](https://x.y/a.png) b';
      builder.prepare(line);
      expect(
        _text(builder.buildLine(line, 0)),
        'a ${MarkdownLinkPatterns.imageGlyph} b',
      );
    });
  });

  // `[[note]]` drops its brackets here (the editor conceals them) and the
  // title carries the tap. The title is the whole payload, so it reaches
  // the callback exactly as typed — resolving a name is the page's job,
  // not the renderer's.
  group('wiki links', () {
    test('the title renders in the link style with the brackets gone', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = 'see [[a]] now';
      builder.prepare(line);
      final span = builder.buildLine(line, 0);

      expect(_text(span), 'see a now');
      final title = _leaves(span).singleWhere((leaf) => leaf.text == 'a');
      expect(title.style?.color, _style.primaryColor);
      expect(
        title.style?.decoration?.contains(TextDecoration.underline),
        isTrue,
      );
    });

    test('tapping the title hands the raw title over untrimmed', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = 'see [[ a ]] now';
      builder.prepare(line);
      final span = builder.buildLine(line, 0);

      _fire(span, ' a ');
      expect(calls.wikis, <String>[' a ']);
      expect(calls.links, isEmpty, reason: 'a wiki link is not a url link');
    });

    test('a wiki link inside bold still carries its recognizer', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = '**[[a]]**';
      builder.prepare(line);
      final span = builder.buildLine(line, 0);

      final title = _leaves(span).singleWhere((leaf) => leaf.text == 'a');
      expect(title.style?.fontWeight, FontWeight.bold);
      _fire(span, 'a');
      expect(calls.wikis, <String>['a']);
    });

    test('a tag beside a wiki link keeps its own recognizer', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = '[[a]] #t';
      builder.prepare(line);
      final span = builder.buildLine(line, 0);

      _fire(span, '#t');
      expect(calls.tags, <String>['#t']);
      expect(calls.wikis, isEmpty, reason: 'the two constructs never nest');

      _fire(span, 'a');
      expect(calls.wikis, <String>['a']);
      expect(calls.tags, <String>['#t'], reason: 'the tag fired only once');
    });

    test('a nested or digit-led tag taps whole; an all-digit one is prose', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = 'run #program/5x5 then #1rm or #123';
      builder.prepare(line);
      final span = builder.buildLine(line, 0);

      _fire(span, '#program/5x5');
      _fire(span, '#1rm');
      expect(calls.tags, <String>['#program/5x5', '#1rm']);
      expect(
        _leaves(span).where(
          (leaf) => leaf.text!.contains('#123') && leaf.recognizer != null,
        ),
        isEmpty,
      );
    });

    // The two list pins in markdown_inline_agreement_test.dart name this
    // file as the preview half of their coverage: a list row is laid out
    // as a `WidgetSpan`, so that suite can only compare the editor side
    // and these two cases are the preview side it points at.
    test('a bulleted wiki link drops its brackets and keeps its tap', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = '- [[a]]';
      builder.prepare(line);
      final content = _listRowContent(builder.buildLine(line, 0));

      expect(_text(content), 'a');
      _fire(content, 'a');
      expect(calls.wikis, <String>['a']);
    });

    test('a task item wiki link drops its brackets and keeps its tap', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = '- [ ] [[a]]';
      builder.prepare(line);
      final content = _listRowContent(builder.buildLine(line, 0));

      expect(_text(content), 'a');
      _fire(content, 'a');
      expect(calls.wikis, <String>['a']);
    });

    test('an alias renders in place and the tap hands over the title', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = 'see [[Squat Day|legs]] now';
      builder.prepare(line);
      final span = builder.buildLine(line, 0);

      expect(_text(span), 'see legs now');
      _fire(span, 'legs');
      expect(calls.wikis, <String>['Squat Day']);
    });

    test('an embed shows the picture glyph before its link', () {
      final calls = _Calls();
      final builder = _builder(calls);
      const line = 'a ![[plan.png]] b';
      builder.prepare(line);
      final span = builder.buildLine(line, 0);

      expect(_text(span), 'a ${MarkdownLinkPatterns.imageGlyph}plan.png b');
      _fire(span, 'plan.png');
      expect(calls.wikis, <String>['plan.png']);
    });

    test('no callback means no recognizer is allocated', () {
      final builder = LineBasedMarkdownBuilder(
        style: _style,
        colorPalette: MarkdownColorPalette.presets,
      );
      addTearDown(builder.dispose);
      const line = 'see [[a]] now';
      builder.prepare(line);

      final title = _leaves(
        builder.buildLine(line, 0),
      ).singleWhere((leaf) => leaf.text == 'a');
      expect(title.recognizer, isNull);
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

  // The same prune, for the `wiki:` prefix: a key the range test cannot
  // parse leaks its recognizer, and a prefix left off the list leaks
  // every one of them.
  test('an evicted chunk drops its wiki-link recognizers', () {
    final calls = _Calls();
    final lines = <String>['[[a]]', for (var i = 0; i < 80; i++) 'line $i'];
    final builder = LineBasedMarkdownBuilder(
      style: _style,
      colorPalette: MarkdownColorPalette.presets,
      onWikiLinkTap: calls.onWiki,
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
      reason: 'the evicted chunk kept its wiki-link recognizer alive',
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

  test('clearCache drops a wiki-link recognizer too', () {
    final calls = _Calls();
    final builder = _builder(calls);
    const line = '[[a]]';
    builder.prepare(line);
    final first = _recognizerOf(<InlineSpan>[builder.buildLine(line, 0)], 'a');
    expect(first, isNotNull);
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

    // The shape walks every whitespace kind Dart trims, not just the
    // space and the tab, so a line the block scan already counts as
    // quoted cannot end up rendered as plain prose here.
    test('exotic leading whitespace is indent, and the bar still draws', () {
      expect(barsOf('\u000C> a'), '┃ a');
      expect(barsOf('\u00A0> a'), '┃ a');
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

  // Rules are tested before the list grammar, and a heading's closing
  // hash run is chrome — both shapes from [MarkdownLineShape].
  group('entities and hard breaks', () {
    String render(String document, [int index = 0]) {
      final builder = LineBasedMarkdownBuilder(
        style: _style,
        colorPalette: MarkdownColorPalette.presets,
      );
      addTearDown(builder.dispose);
      builder.prepare(document);
      return _text(builder.buildLine(document.split('\n')[index], index));
    }

    test('named and numeric entities decode', () {
      expect(render('a &amp; b &copy; &#x2014; &#169;'), 'a & b © — ©');
    });

    test('unknown and code-span entities stay literal', () {
      expect(render('&nope; `&amp;`'), '&nope; &amp;');
    });

    test('an entity keeps the offset of its ampersand', () {
      const line = 'x &amp; y';
      final builder = LineBasedMarkdownBuilder(
        style: _style,
        colorPalette: MarkdownColorPalette.presets,
        searchHighlights: const <TextRange>[TextRange(start: 2, end: 3)],
      );
      addTearDown(builder.dispose);
      builder.prepare(line);
      final painted = _leaves(builder.buildLine(line, 0))
          .where((leaf) => leaf.style?.backgroundColor == _style.highlightColor)
          .map((leaf) => leaf.text)
          .join();
      expect(painted, '&');
    });

    test('a trailing backslash is dropped on every line it ends', () {
      expect(render('first\\\nsecond\\', 0), 'first');
      expect(render('first\\\nsecond\\', 1), 'second');
      expect(render(r'> quoted\'), contains('quoted'));
      expect(render(r'> quoted\'), isNot(contains(r'\')));
    });

    test('an escaped or lone backslash stays', () {
      expect(render(r'a\\'), r'a\');
      expect(render(r'\'), r'\');
    });

    test('a backslash before a table pipe is not a hard break', () {
      expect(render(r'| a\ | b |'), contains(r'a\'));
    });
  });

  group('rules and closing hashes', () {
    String render(String line) {
      final builder = LineBasedMarkdownBuilder(
        style: _style,
        colorPalette: MarkdownColorPalette.presets,
      );
      addTearDown(builder.dispose);
      builder.prepare(line);
      return _text(builder.buildLine(line, 0));
    }

    test('a spaced rule draws the rule, not a bullet', () {
      for (final line in <String>['- - -', '* * *', '_ _ _', ' -  -\t-']) {
        expect(render(line), '─' * 40, reason: line);
      }
      final builder = LineBasedMarkdownBuilder(
        style: _style,
        colorPalette: MarkdownColorPalette.presets,
      );
      addTearDown(builder.dispose);
      builder.prepare('- - x');
      expect(_listMarker(builder.buildLine('- - x', 0)), '• ');
    });

    // The rule is read on the untrimmed line, like the editor and the
    // list grammar: an NBSP is list indent, never rule indent.
    test('an NBSP-indented spaced rule is a bullet, as in the editor', () {
      const line = ' - - -';
      final builder = LineBasedMarkdownBuilder(
        style: _style,
        colorPalette: MarkdownColorPalette.presets,
      );
      addTearDown(builder.dispose);
      builder.prepare(line);
      expect(_listMarker(builder.buildLine(line, 0)), '• ');
    });

    test('a closing hash run is dropped with the leading hashes', () {
      expect(render('## Week 3 ##'), 'Week 3');
      expect(render('## Week 3 ##  '), 'Week 3');
      expect(render('## ##'), '');
    });

    test('hashes glued to the content stay', () {
      expect(render('## Title##'), 'Title##');
      expect(render('## C#'), 'C#');
      expect(render(r'## foo \##'), 'foo ##', reason: 'an escape is content');
    });

    test('a heading whose content is one hash run is empty', () {
      expect(render('## #'), '');
      expect(render('# #'), '');
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
  final List<String> wikis = <String>[];
  final List<String> tags = <String>[];
  int ghosts = 0;

  void onLink(String url) => links.add(url);
  void onWiki(String title) => wikis.add(title);
  void onTag(String tag) => tags.add(tag);
  void onGhost(int start, int end) => ghosts++;
}

LineBasedMarkdownBuilder _builder(_Calls calls) {
  final builder = LineBasedMarkdownBuilder(
    style: _style,
    colorPalette: MarkdownColorPalette.presets,
    onLinkTap: calls.onLink,
    onWikiLinkTap: calls.onWiki,
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

/// The inline content of a preview list row. A bullet or task row is a
/// single `WidgetSpan` — a `Row` holding the marker and an `Expanded`
/// `Text.rich` — so the row's own spans are unreachable from the root
/// through [_leaves], which walks [TextSpan] children only.
InlineSpan _listRowContent(InlineSpan root) {
  final WidgetSpan row = (root as TextSpan).children!.single as WidgetSpan;
  final Padding padding = row.child as Padding;
  final DefaultTextStyle styled = padding.child! as DefaultTextStyle;
  final Row layout = styled.child as Row;
  final Expanded content = layout.children.last as Expanded;
  return (content.child as Text).textSpan!;
}

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
