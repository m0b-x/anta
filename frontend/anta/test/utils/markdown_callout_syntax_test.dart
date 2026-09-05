import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/markdown_callout_syntax.dart';
import 'package:anta/utils/markdown_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

/// [MarkdownCalloutSyntax] is the one grammar three consumers scan with:
/// the chunker (block extents in the preview), the live editor's line
/// index (the per-line callout role) and both renderers (bars, icon,
/// title). Nothing here touches Flutter, so every rule below is pinned
/// as a pure function over one line — plus, for the block transition,
/// the block that was open on entry.
///
/// What this suite guards:
///   * [MarkdownCalloutSyntax.isBlockquoteLine] — the allocation-free
///     probe every line of the document pays. Its fast path answers from
///     code units, so the suite re-derives each answer from the
///     `trimLeft` definition it replaced and demands the two agree,
///     including on the non-ASCII whitespace that takes the fallback.
///   * [MarkdownCalloutSyntax.blockStep] — the single transition of the
///     block scan, so the chunker and the editor index can never disagree
///     about where a callout ends. Fences are the caller's business.
///   * [MarkdownCalloutSyntax.quoteMarkers] — the nested-quote shape both
///     surfaces render one `┃` per marker from; `depth`, the marker
///     columns and `contentStart` must describe the same line. It has to
///     answer `null` on exactly the lines
///     [MarkdownCalloutSyntax.isBlockquoteLine] rejects, or one surface
///     draws a bar the other does not.
///   * [MarkdownCalloutSyntax.parseLead] — unchanged behaviour, pinned
///     because the editor now tints and conceals by its exact offsets.
///   * The block extents [MarkdownChunker] derives from the transition:
///     the preview renders a callout out of those extents, not out of a
///     per-line probe of its own, so a line the transition misreads
///     changes what the reader sees a whole block away.
void main() {
  group('isBlockquoteLine matches the trimLeft definition', () {
    for (final (line, expected) in _blockquoteCases) {
      test('"${_visible(line)}"', () {
        expect(
          MarkdownCalloutSyntax.isBlockquoteLine(line),
          expected,
          reason: 'the fast path must answer $expected',
        );
        expect(
          MarkdownCalloutSyntax.isBlockquoteLine(line),
          _trimLeftDefinition(line),
          reason:
              'the fast path must stay byte-identical to the trimming form '
              'it replaced',
        );
      });
    }
  });

  // The fast path decides from code units, so every whitespace kind is
  // its own branch: the ASCII run it walks in place, and the non-ASCII
  // whitespace that has to fall back. [MarkdownCalloutSyntax.quoteMarkers]
  // walks the same indent, so the two must answer together — a line the
  // probe calls a quote but the shape declines would draw no bar on
  // either surface while still being scanned as callout body.
  group('every whitespace lead answers the same on both probes', () {
    for (final (unit, name) in _whitespaceLeads) {
      for (final (suffix, shape) in const <(String, String)>[
        ('> x', 'a quote'),
        ('x', 'plain text'),
      ]) {
        final line = '$unit$suffix';
        test('$name before $shape', () {
          final expected = _trimLeftDefinition(line);
          expect(
            MarkdownCalloutSyntax.isBlockquoteLine(line),
            expected,
            reason: 'the fast path must match the trimming definition',
          );
          final markers = MarkdownCalloutSyntax.quoteMarkers(line);
          expect(
            markers != null,
            expected,
            reason:
                'quoteMarkers must produce a shape for exactly the lines '
                'isBlockquoteLine accepts',
          );
          if (markers != null) {
            expect(
              markers.markerOffsets,
              <int>[1],
              reason: 'one unit of indent precedes the marker',
            );
            expect(
              markers.contentStart,
              3,
              reason: 'the marker and its single space are chrome',
            );
          }
        });
      }
    }

    test('a no-break space is indent, not content', () {
      final shape = MarkdownCalloutSyntax.quoteMarkers(' > body');
      expect(shape, isNotNull);
      expect(shape!.depth, 1);
      expect(shape.markerOffsets, <int>[1]);
      expect(shape.contentStart, 3);
    });

    test('an ideographic space is indent, not content', () {
      final shape = MarkdownCalloutSyntax.quoteMarkers('　> x');
      expect(shape, isNotNull);
      expect(shape!.depth, 1);
      expect(shape.markerOffsets, <int>[1]);
      expect(shape.contentStart, 3);
    });
  });

  group('blockStep', () {
    test('a lead line with no block open opens its own type', () {
      expect(
        MarkdownCalloutSyntax.blockStep('> [!TIP] hint', null),
        MarkdownCalloutType.tip,
      );
      expect(
        MarkdownCalloutSyntax.blockStep('> [!WARNING]', null),
        MarkdownCalloutType.warning,
      );
    });

    test('an indented lead still opens the block', () {
      expect(
        MarkdownCalloutSyntax.blockStep('  > [!TIP] x', null),
        MarkdownCalloutType.tip,
      );
    });

    test('a quote line inside an open block keeps that block', () {
      expect(
        MarkdownCalloutSyntax.blockStep('> body', MarkdownCalloutType.tip),
        MarkdownCalloutType.tip,
      );
      expect(
        MarkdownCalloutSyntax.blockStep('>> deeper', MarkdownCalloutType.tip),
        MarkdownCalloutType.tip,
      );
    });

    test('a nested lead inside an open block is body of the outer block', () {
      expect(
        MarkdownCalloutSyntax.blockStep('> [!NOTE] x', MarkdownCalloutType.tip),
        MarkdownCalloutType.tip,
        reason: 'the outer block wins; the inner lead is just quoted text',
      );
    });

    test('a blank or non-quote line closes the block', () {
      expect(
        MarkdownCalloutSyntax.blockStep('', MarkdownCalloutType.tip),
        isNull,
      );
      expect(
        MarkdownCalloutSyntax.blockStep('plain', MarkdownCalloutType.tip),
        isNull,
      );
    });

    test('an unrecognised token is a plain quote, not a callout', () {
      expect(MarkdownCalloutSyntax.blockStep('> [!FOO]', null), isNull);
      expect(MarkdownCalloutSyntax.blockStep('> quote', null), isNull);
    });

    test('a depth-2 quote is not a lead', () {
      expect(
        MarkdownCalloutSyntax.blockStep('>> [!TIP]', null),
        isNull,
        reason: 'the token is literal text inside a nested quote',
      );
    });

    // Most lines of a document are neither quotes nor leads, and the
    // transition runs on every one of them in both the chunker and the
    // editor's line index. A line that cannot be a quote cannot be a
    // lead either, so it must answer without a lead parse.
    test('a line that is not a quote answers null whatever is open', () {
      expect(MarkdownCalloutSyntax.blockStep('  - nested item', null), isNull);
      expect(
        MarkdownCalloutSyntax.blockStep('plain', MarkdownCalloutType.tip),
        isNull,
      );
    });

    test('exotic leading whitespace still continues an open block', () {
      expect(
        MarkdownCalloutSyntax.blockStep('> body', MarkdownCalloutType.tip),
        MarkdownCalloutType.tip,
        reason: 'a form feed is indent, so the line is still quoted',
      );
    });
  });

  // The chunker turns the transition into block extents, and the preview
  // renders a callout out of those. These cases are the extents — not the
  // chunk boundaries, which `markdown_chunker_test.dart` owns.
  group('chunker block extents', () {
    List<MarkdownBlock> calloutsOf(List<String> lines) =>
        MarkdownChunker.computeLayout(
          lineCount: lines.length,
          chunkSize: 100,
          lineAt: (i) => lines[i],
        ).blocks.where((b) => b.kind == MarkdownBlockKind.callout).toList();

    void expectSingleBlock(List<String> lines, int start, int end) {
      final blocks = calloutsOf(lines);
      expect(blocks, hasLength(1), reason: 'exactly one callout block');
      expect(blocks.single.startLine, start, reason: 'block start');
      expect(blocks.single.endLine, end, reason: 'block end (exclusive)');
    }

    test('a nested lead extends the open block instead of starting one', () {
      expectSingleBlock(
        const <String>['> [!TIP] a', '> [!NOTE] b', 'after'],
        0,
        2,
      );
    });

    test('an exotic-whitespace quote line stays inside the block', () {
      expectSingleBlock(const <String>['> [!TIP] a', '> b', 'after'], 0, 2);
    });

    test('a fenced lead opens no callout block at all', () {
      expect(
        calloutsOf(const <String>['```', '> [!TIP]', '```']),
        isEmpty,
        reason: 'the fence is consumed first, so the lead is code',
      );
    });
  });

  group('quoteMarkers', () {
    for (final (line, depth, offsets, contentStart) in _quoteCases) {
      test('"${_visible(line)}"', () {
        final shape = MarkdownCalloutSyntax.quoteMarkers(line);
        expect(shape, isNotNull, reason: 'the corpus is quote lines only');
        expect(shape!.depth, depth, reason: 'marker count');
        expect(shape.markerOffsets, offsets, reason: 'marker columns');
        expect(
          shape.contentStart,
          contentStart,
          reason: 'content begins past the last marker and its one space',
        );
        expect(
          shape.depth,
          shape.markerOffsets.length,
          reason: 'one offset per marker, or a renderer would drop a bar',
        );
        for (final at in shape.markerOffsets) {
          expect(
            line.codeUnitAt(at),
            0x3E,
            reason: 'every reported column must actually hold a `>`',
          );
        }
      });
    }

    test('a non-quote line has no shape', () {
      expect(MarkdownCalloutSyntax.quoteMarkers('a'), isNull);
      expect(MarkdownCalloutSyntax.quoteMarkers(''), isNull);
      expect(MarkdownCalloutSyntax.quoteMarkers('  '), isNull);
      expect(MarkdownCalloutSyntax.quoteMarkers('a > b'), isNull);
    });
  });

  group('parseLead', () {
    test('the token is case-insensitive', () {
      final lead = MarkdownCalloutSyntax.parseLead('> [!tip] T');
      expect(lead, isNotNull);
      expect(lead!.type, MarkdownCalloutType.tip);
      expect(lead.title, 'T');
    });

    test('the space after `>` is optional', () {
      final lead = MarkdownCalloutSyntax.parseLead('>[!TIP]');
      expect(lead, isNotNull);
      expect(lead!.type, MarkdownCalloutType.tip);
      expect(lead.tokenStart, 1);
      expect(lead.tokenEnd, 7);
      expect(lead.title, isEmpty);
      expect(lead.titleStart, 7);
    });

    test('spacing inside the token is trimmed away', () {
      final lead = MarkdownCalloutSyntax.parseLead('> [! TIP ]');
      expect(lead, isNotNull);
      expect(lead!.type, MarkdownCalloutType.tip);
    });

    test('an unclosed token is not a lead', () {
      expect(MarkdownCalloutSyntax.parseLead('> [!TIP'), isNull);
      expect(MarkdownCalloutSyntax.parseLead('> [!FOO] x'), isNull);
      expect(MarkdownCalloutSyntax.parseLead('>> [!TIP]'), isNull);
      expect(MarkdownCalloutSyntax.parseLead('plain'), isNull);
    });

    test('indent shifts every offset; the title is trimmed', () {
      const line = '  > [!WARNING]  Heads up ';
      final lead = MarkdownCalloutSyntax.parseLead(line);
      expect(lead, isNotNull);
      expect(lead!.type, MarkdownCalloutType.warning);
      expect(lead.tokenStart, 4);
      expect(lead.tokenEnd, 14);
      expect(line.substring(lead.tokenStart, lead.tokenEnd), '[!WARNING]');
      expect(lead.titleStart, 16);
      expect(lead.title, 'Heads up');
      expect(line.substring(lead.titleStart), 'Heads up ');
    });
  });

  group('shared constants', () {
    test('every callout type paints its own icon', () {
      final icons = MarkdownCalloutType.values
          .map(MarkdownConstants.calloutIcon)
          .toSet();
      expect(
        icons.length,
        MarkdownCalloutType.values.length,
        reason:
            'the editor paints one icon glyph per lead; a shared icon would '
            'make two callout kinds indistinguishable',
      );
    });

    test('inline code renders at 0.9 of its context size', () {
      expect(
        MarkdownConstants.inlineCodeScale,
        0.9,
        reason: 'both surfaces read the scale from here, not from a literal',
      );
    });
  });
}

String _visible(String s) => s
    .replaceAll('\t', '\\t')
    .replaceAll(' ', '\\u00a0')
    .replaceAll('　', '\\u3000');

/// The definition [MarkdownCalloutSyntax.isBlockquoteLine] replaced: a
/// blockquote line is one whose left-trimmed form starts with `>`.
bool _trimLeftDefinition(String line) {
  final trimmed = line.trimLeft();
  return trimmed.isNotEmpty && trimmed.codeUnitAt(0) == 0x3E;
}

/// Every whitespace unit a line may lead with, split across the fast
/// path's two halves: `0x09`–`0x0D` and `0x20` are walked in place, and
/// everything from `0x85` up (`U+FEFF` included, which Dart trims and
/// Unicode does not call a space) falls back to `trimLeft`. The suite
/// derives the answer for each from that fallback rather than hard-coding
/// it, so the table stays right if Dart's definition ever moves.
const List<(String, String)> _whitespaceLeads = <(String, String)>[
  ('\u0009', 'a tab'),
  ('\u000A', 'a line feed'),
  ('\u000B', 'a vertical tab'),
  ('\u000C', 'a form feed'),
  ('\u000D', 'a carriage return'),
  ('\u0020', 'a space'),
  ('\u0085', 'a next line'),
  ('\u00A0', 'a no-break space'),
  ('\u1680', 'an ogham space mark'),
  ('\u2003', 'an em space'),
  ('\u3000', 'an ideographic space'),
  ('\uFEFF', 'a byte-order mark'),
];

/// Both sides of the fast path: the ASCII shortcut (space, tab, `>`, any
/// other ASCII), the empty and blank lines, and the non-ASCII whitespace
/// that has to take the `trimLeft` fallback.
const List<(String, bool)> _blockquoteCases = <(String, bool)>[
  ('', false),
  (' ', false),
  ('>', true),
  (' >', true),
  ('\t>', true),
  ('a>', false),
  (' a', false),
  ('　>', true),
  (' > x', true),
  ('　a', false),
];

/// The nested-quote shapes both renderers draw bars from: plain and
/// nested, tight and spaced, indented, marker-hugging content, and the
/// depth-3 spellings.
const List<(String, int, List<int>, int)> _quoteCases =
    <(String, int, List<int>, int)>[
      ('> a', 1, <int>[0], 2),
      ('>> a', 2, <int>[0, 1], 3),
      ('> > a', 2, <int>[0, 2], 4),
      ('>>', 2, <int>[0, 1], 2),
      ('>', 1, <int>[0], 1),
      ('  > a', 1, <int>[2], 4),
      ('>  a', 1, <int>[0], 2),
      ('>text', 1, <int>[0], 1),
      ('>>> deep', 3, <int>[0, 1, 2], 4),
      ('> > > deep', 3, <int>[0, 2, 4], 6),
      ('> [!TIP] x', 1, <int>[0], 2),
      ('\t> a', 1, <int>[1], 3),
    ];
