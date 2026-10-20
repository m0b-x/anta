import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/utils/line_based_markdown_builder.dart';
import 'package:anta/utils/markdown_chunker.dart';

/// The chunker is the single source of truth for chunk boundaries shared by
/// the preview renderer and the editor's debug overlay, so the two surfaces
/// can never disagree about which source lines a chunk covers.
///
/// Two contracts are guarded here.
///
/// The first is the **block scan**: fenced code (including an unterminated
/// fence, which runs to EOF) and `> [!TYPE]` callouts are the only multi-line
/// blocks; everything else stays implicit line-by-line.
///
/// The second is **chunk alignment**. Both block kinds are deliberately
/// non-atomic — they render line-by-line, so a very large one may be divided
/// to keep virtualization alive. What must hold is the budget rule: a block
/// that fits entirely inside a chunk's line budget is never bisected.
void main() {
  String doc(List<String> lines) => lines.join('\n');

  List<String> filler(int count, [String prefix = 'text']) =>
      List<String>.generate(count, (i) => '$prefix $i');

  MarkdownChunkLayout layoutOf(String source, {int chunkSize = 10}) {
    final lines = source.split('\n');
    return MarkdownChunker.computeLayout(
      lineCount: lines.length,
      chunkSize: chunkSize,
      lineAt: (i) => lines[i],
    );
  }

  int chunkEnd(MarkdownChunkLayout layout, int index, int lineCount) =>
      index + 1 < layout.chunkStartLines.length
      ? layout.chunkStartLines[index + 1]
      : lineCount;

  /// Every block whose whole extent fits inside its chunk's budget window
  /// must be consumed by a single chunk.
  void expectBudgetedBlocksWhole(String source, int chunkSize) {
    final lineCount = source.split('\n').length;
    final layout = layoutOf(source, chunkSize: chunkSize);
    for (int i = 0; i < layout.chunkStartLines.length; i++) {
      final start = layout.chunkStartLines[i];
      final end = chunkEnd(layout, i, lineCount);
      for (final block in layout.blocks) {
        final fitsBudget =
            block.startLine >= start && block.endLine <= start + chunkSize;
        if (!fitsBudget) continue;
        final bisected = end > block.startLine && end < block.endLine;
        expect(
          bisected,
          isFalse,
          reason:
              'chunk $i [$start, $end) bisects block '
              '${block.kind} [${block.startLine}, ${block.endLine})',
        );
      }
    }
  }

  group('fence delimiter grammar', () {
    test('bare and language-tagged fences are delimiters', () {
      expect(MarkdownChunker.isFenceDelimiter('```'), isTrue);
      expect(MarkdownChunker.isFenceDelimiter('```dart'), isTrue);
      expect(MarkdownChunker.isFenceDelimiter('````'), isTrue);
    });

    test('any indent of spaces or tabs is tolerated', () {
      expect(MarkdownChunker.isFenceDelimiter('   ```'), isTrue);
      expect(MarkdownChunker.isFenceDelimiter('  ~~~ js'), isTrue);
      // A fence under a list item sits at the item's content column.
      expect(MarkdownChunker.isFenceDelimiter('    ```'), isTrue);
      expect(MarkdownChunker.isFenceDelimiter('\t```dart'), isTrue);
      expect(MarkdownChunker.isFenceDelimiter(' \t ```'), isTrue);
    });

    test('a trailing CR is a blank, so CRLF closers and markers hold', () {
      final int ticks = MarkdownChunker.fenceOpenerOf('```\r');
      expect(ticks, MarkdownChunker.fenceOpenerOf('```'));
      expect(MarkdownChunker.closesFence('```\r', ticks), isTrue);
      expect(
        MarkdownChunker.closesFence(
          '~~~\r',
          MarkdownChunker.fenceOpenerOf('~~~'),
        ),
        isTrue,
      );
      expect(MarkdownChunker.isCommentDelimiter('%%\r'), isTrue);
      expect(MarkdownChunker.closesFence('```js\r', ticks), isFalse);
    });

    test('tilde fences open with any info string', () {
      expect(MarkdownChunker.isFenceDelimiter('~~~'), isTrue);
      expect(MarkdownChunker.isFenceDelimiter('~~~~python'), isTrue);
      expect(MarkdownChunker.isFenceDelimiter('~~~ a ` b ~'), isTrue);
    });

    test('a backtick run with a backtick later in the line is inline code', () {
      expect(MarkdownChunker.isFenceDelimiter('```npm i```'), isFalse);
      expect(MarkdownChunker.isFenceDelimiter('``` a ` b'), isFalse);
    });

    test('anything else is not a delimiter', () {
      expect(MarkdownChunker.isFenceDelimiter(''), isFalse);
      expect(MarkdownChunker.isFenceDelimiter('``'), isFalse);
      expect(MarkdownChunker.isFenceDelimiter('~~'), isFalse);
      expect(MarkdownChunker.isFenceDelimiter('a```'), isFalse);
      expect(MarkdownChunker.isFenceDelimiter('  `` `'), isFalse);
    });

    test('a closer is the opener character, at least as long, bare', () {
      final int ticks = MarkdownChunker.fenceOpenerOf('```js');
      final int quad = MarkdownChunker.fenceOpenerOf('````');
      final int tildes = MarkdownChunker.fenceOpenerOf('~~~');
      expect(MarkdownChunker.closesFence('```', ticks), isTrue);
      expect(MarkdownChunker.closesFence('`````  ', ticks), isTrue);
      expect(MarkdownChunker.closesFence('```js', ticks), isFalse);
      expect(MarkdownChunker.closesFence('~~~', ticks), isFalse);
      expect(MarkdownChunker.closesFence('```', quad), isFalse);
      expect(MarkdownChunker.closesFence('````', quad), isTrue);
      expect(MarkdownChunker.closesFence('~~~', tildes), isTrue);
      expect(MarkdownChunker.closesFence('```', tildes), isFalse);
      expect(MarkdownChunker.closesFence('    ```', ticks), isTrue);
      expect(MarkdownChunker.closesFence('\t```', ticks), isTrue);
    });

    test('a comment marker is a bare %% line', () {
      expect(MarkdownChunker.isCommentDelimiter('%%'), isTrue);
      expect(MarkdownChunker.isCommentDelimiter('   %%  '), isTrue);
      expect(MarkdownChunker.isCommentDelimiter('\t%%'), isTrue);
      expect(MarkdownChunker.isCommentDelimiter('%%note%%'), isFalse);
      expect(MarkdownChunker.isCommentDelimiter('%'), isFalse);
      expect(MarkdownChunker.isCommentDelimiter('%%%'), isFalse);
    });

    test('a blank line is empty or whitespace', () {
      expect(MarkdownChunker.isBlankLine(''), isTrue);
      expect(MarkdownChunker.isBlankLine(' \t '), isTrue);
      expect(MarkdownChunker.isBlankLine(' b'), isFalse);
    });

    test('only prose continues a paragraph', () {
      bool goesOn(String line, String? next) =>
          MarkdownChunker.continuesParagraph(line, next);
      expect(goesOn('a', 'b'), isTrue);
      expect(goesOn('a', '  indented prose'), isTrue);
      expect(goesOn('> a', '> b'), isTrue);
      expect(goesOn('a', null), isFalse);
      expect(goesOn('a', ' \t'), isFalse);
      for (final next in [
        '- b',
        '1. b',
        '- [ ] b',
        '# H',
        '```',
        '~~~js',
        '***',
        '%%',
        '| a | b |',
        r'$+ 5 x',
        '> b',
      ]) {
        expect(goesOn('a', next), isFalse, reason: next);
      }
      expect(goesOn(r'- D:\a\', r'- D:\b\'), isFalse);
      expect(goesOn('> a', 'b'), isFalse);
      expect(goesOn('> a', '>'), isFalse);
      expect(goesOn('> a', '> - b'), isFalse);
      expect(goesOn('> a', '> # H'), isFalse);
    });

    test('a deeper quote, a callout lead or a setext text line ends it', () {
      expect(MarkdownChunker.continuesParagraph('> a', '> > b'), isFalse);
      expect(MarkdownChunker.continuesParagraph('> > a', '> > b'), isTrue);
      expect(
        MarkdownChunker.continuesParagraph('> > a', '> b'),
        isTrue,
        reason: 'a shallower line is a lazy continuation',
      );
      expect(MarkdownChunker.continuesParagraph('> a', '> [!TIP] x'), isFalse);
      expect(MarkdownChunker.continuesParagraph('a', 'b', '==='), isFalse);
      expect(MarkdownChunker.continuesParagraph('a', 'b', '---'), isFalse);
      expect(MarkdownChunker.continuesParagraph('a', 'b', 'c'), isTrue);
    });
  });

  group('block scan — fence pairing and comments', () {
    List<(MarkdownBlockKind, int, int)> blocksOf(List<String> lines) => [
      for (final b in layoutOf(doc(lines)).blocks)
        (b.kind, b.startLine, b.endLine),
    ];
    const fence = MarkdownBlockKind.codeFence;
    const comment = MarkdownBlockKind.comment;

    test('a one-line ```npm i``` opens no block', () {
      expect(blocksOf(['```npm i```', '#tag', 'more']), isEmpty);
    });

    group('front matter', () {
      const fm = MarkdownBlockKind.frontMatter;
      int endOf(List<String> lines) =>
          MarkdownChunker.frontMatterEnd(lines.length, (i) => lines[i]);

      test('closes at --- or ... and holds only properties', () {
        expect(endOf(['---', 'tags: [a, b]', 'aliases:', '  - x', '---']), 5);
        expect(endOf(['---', 'title: x', '...', '# H']), 3);
        expect(endOf(['---  ', 'k: v', '---\r', 'x']), 3);
        expect(endOf(['---', 'Übung: Kniebeuge', 'note.v2: a', '---']), 4);
        expect(blocksOf(['---', 'k: v', '---', '# H', '```', 'c', '```']), [
          (fm, 0, 3),
          (fence, 4, 7),
        ]);
      });

      test('a rule with no closer, or a broken candidate, is none', () {
        expect(endOf(['---', 'k: v']), 0);
        expect(endOf(['---', 'k: v', 'prose', '---']), 0);
        expect(endOf(['---', 'k: v', '', '---']), 0);
        expect(endOf(['---', '```', '---']), 0);
        expect(endOf(['---', '%%', '---']), 0);
        expect(endOf(['---', r'$+ 5: x', '---']), 0);
        expect(endOf(['---', '# k: v', '---']), 0);
        expect(endOf(['---', '---', 'k: v']), 0);
        expect(endOf([' ---', 'k: v', '---']), 0);
        expect(endOf(['---', 'k: v', ' ---']), 0);
        expect(endOf(['x', '---', 'k: v', '---']), 0);
        expect(endOf(['---', 'k:v', '---']), 0);
      });

      // C1 fix pass C2 — YAML front matter is a mapping: a list framed by
      // two rules at the top of a note stays rule, list, rule.
      test('the first property is a key; an item only continues one', () {
        expect(endOf(['---', '- a', '---']), 0);
        expect(endOf(['---', '- [ ] buy milk', '- [ ] eggs', '---', 'x']), 0);
        expect(endOf(['---', '-', 'k: v', '---']), 0);
        expect(endOf(['---', 'k:', '- a', '---']), 4);
        expect(blocksOf(['---', '- a', '---']), isEmpty);
      });

      // C1 fix pass C8 — where the scan stops is the line index's re-read
      // bound: nothing below it is read.
      test('frontMatterStop is the closer, the break, or the end', () {
        int stopOf(List<String> lines) =>
            MarkdownChunker.frontMatterStop(lines.length, (i) => lines[i]);
        expect(stopOf(['---', 'k: v', '---', 'x']), 2);
        expect(stopOf(['---', 'k: v', 'prose', 'k: v', '---']), 2);
        expect(stopOf(['---', 'k: v', '- a', '- b']), 4);
        expect(stopOf(['x', 'k: v', '---']), 0);
        expect(stopOf(['---', '- a', 'k: v']), 1);
      });

      test('blockStateAfter steps an open block to its closer', () {
        const open = MarkdownChunker.insideFrontMatter;
        expect(MarkdownChunker.blockStateAfter('```', open), open);
        expect(MarkdownChunker.blockStateAfter('%%', open), open);
        expect(MarkdownChunker.blockStateAfter('...', open), 0);
        expect(MarkdownChunker.blockStateAfter('---', open), 0);
        expect(MarkdownChunker.isFenceState(open), isFalse);
      });
    });

    test('```js inside an open fence does not close it', () {
      expect(blocksOf(['```', 'a', '```js', 'b', '```', 'after']), [
        (fence, 0, 5),
      ]);
    });

    test('a ```` fence stays open past a ``` line until ````', () {
      expect(blocksOf(['````', '```', 'x', '````', 'after']), [(fence, 0, 4)]);
    });

    test('~~~ pairs with ~~~ and never closes a backtick fence', () {
      expect(blocksOf(['~~~', 'a', '~~~', 'b']), [(fence, 0, 3)]);
      expect(blocksOf(['```', '~~~', 'x']), [(fence, 0, 3)]);
    });

    test('a fence under a list item pairs at any indent', () {
      expect(
        blocksOf(['- step', '    ```bash', '    npm i #tag', '    ```', 'x']),
        [(fence, 1, 4)],
      );
      expect(blocksOf(['- step', '\t```bash', '\tnpm i', '\t```', 'x']), [
        (fence, 1, 4),
      ]);
    });

    test('CRLF lines pair their fences and comments', () {
      expect(blocksOf(['```js\r', 'code\r', '```\r', 'after\r', 'more']), [
        (fence, 0, 3),
      ]);
      expect(blocksOf(['%%\r', 'x\r', '%%\r', 'after']), [(comment, 0, 3)]);
    });

    test('a %% block runs to the next %% line or the end', () {
      expect(blocksOf(['a', '%%', 'hidden ```', '%%', 'b']), [(comment, 1, 4)]);
      expect(blocksOf(['%%', 'x', 'y']), [(comment, 0, 3)]);
    });

    test('a %% line inside a fence is code', () {
      expect(blocksOf(['```', '%%', '```', 'b']), [(fence, 0, 3)]);
    });
  });

  group('block scan — fenced code', () {
    test('a paired fence is one non-atomic block covering both delimiters', () {
      final source = doc([
        '# Title',
        'intro',
        '```dart',
        'final x = 1;',
        '```',
        'outro',
      ]);

      final layout = layoutOf(source);

      expect(layout.blocks, hasLength(1));
      final block = layout.blocks.single;
      expect(block.kind, MarkdownBlockKind.codeFence);
      expect(block.startLine, 2);
      expect(block.endLine, 5);
      expect(block.atomic, isFalse);
      expect(block.contains(2), isTrue);
      expect(block.contains(4), isTrue);
      expect(block.contains(5), isFalse);
      expect(block.contains(1), isFalse);
    });

    test('an unterminated fence extends to EOF', () {
      final source = doc(['intro', '```dart', 'final x = 1;', 'more code']);

      final layout = layoutOf(source);

      expect(layout.blocks, hasLength(1));
      expect(layout.blocks.single.kind, MarkdownBlockKind.codeFence);
      expect(layout.blocks.single.startLine, 1);
      expect(layout.blocks.single.endLine, 4);
    });

    test('an unterminated fence stays inside one chunk', () {
      final source = doc(['intro', '```dart', 'final x = 1;', 'more code']);

      final layout = layoutOf(source, chunkSize: 10);

      expect(layout.chunkStartLines, [0]);
      expect(layout.blocks.single.endLine, source.split('\n').length);
    });

    test('two fences are two blocks emitted in source order', () {
      final source = doc([
        '```',
        'a',
        '```',
        'between',
        '```',
        'b',
        '```',
        'tail',
      ]);

      final layout = layoutOf(source);

      expect(layout.blocks, hasLength(2));
      expect(layout.blocks[0].startLine, 0);
      expect(layout.blocks[0].endLine, 3);
      expect(layout.blocks[1].startLine, 4);
      expect(layout.blocks[1].endLine, 7);
    });

    test('a fence swallows callout-looking lines inside it', () {
      final source = doc(['```', '> [!TIP]', '> not a callout', '```', 'tail']);

      final layout = layoutOf(source);

      expect(layout.blocks, hasLength(1));
      expect(layout.blocks.single.kind, MarkdownBlockKind.codeFence);
      expect(layout.blocks.single.startLine, 0);
      expect(layout.blocks.single.endLine, 4);
    });
  });

  group('block scan — callouts', () {
    test('a `> [!TYPE]` run is one non-atomic callout block', () {
      final source = doc([
        'intro',
        '> [!TIP] Rest longer',
        '> second line',
        '> third line',
        'after',
      ]);

      final layout = layoutOf(source);

      expect(layout.blocks, hasLength(1));
      final block = layout.blocks.single;
      expect(block.kind, MarkdownBlockKind.callout);
      expect(block.startLine, 1);
      expect(block.endLine, 4);
      expect(block.atomic, isFalse);
    });

    test('the first non-blockquote line ends the callout', () {
      final source = doc(['> [!WARNING]', '> body', '', '> [!NOTE]', '> body']);

      final layout = layoutOf(source);

      expect(layout.blocks, hasLength(2));
      expect(layout.blocks[0].startLine, 0);
      expect(layout.blocks[0].endLine, 2);
      expect(layout.blocks[1].startLine, 3);
      expect(layout.blocks[1].endLine, 5);
    });

    test('a callout runs to EOF when never closed by other content', () {
      final source = doc(['> [!CAUTION]', '> a', '> b']);

      final layout = layoutOf(source);

      expect(layout.blocks.single.startLine, 0);
      expect(layout.blocks.single.endLine, 3);
    });

    test('an unrecognised type still opens a callout block', () {
      final source = doc(['> [!FOO]', '> body', 'after']);

      final blocks = layoutOf(source).blocks;
      expect(blocks, hasLength(1));
      expect(blocks.single.kind, MarkdownBlockKind.callout);
      expect(blocks.single.endLine, 2);
    });

    test('a blank token stays a plain blockquote', () {
      final source = doc(['> [!]', '> body', 'after']);

      expect(layoutOf(source).blocks, isEmpty);
    });

    test('a plain blockquote without a lead token is not a block', () {
      final source = doc(['> just a quote', '> more', 'after']);

      expect(layoutOf(source).blocks, isEmpty);
    });

    test('fences and callouts interleave in sorted source order', () {
      final source = doc([
        'intro',
        '```',
        'code',
        '```',
        '> [!NOTE]',
        '> body',
        'tail',
      ]);

      final layout = layoutOf(source);

      expect(layout.blocks, hasLength(2));
      expect(layout.blocks[0].kind, MarkdownBlockKind.codeFence);
      expect(layout.blocks[1].kind, MarkdownBlockKind.callout);
      expect(layout.blocks[0].startLine, lessThan(layout.blocks[1].startLine));
    });
  });

  group('chunk layout invariants', () {
    test('starts are sorted, unique, in range and begin at zero', () {
      final source = doc([
        ...filler(7),
        '```',
        'code a',
        'code b',
        '```',
        ...filler(20, 'body'),
        '> [!TIP]',
        '> body',
        ...filler(15, 'tail'),
      ]);
      final lineCount = source.split('\n').length;

      final layout = layoutOf(source, chunkSize: 10);
      final starts = layout.chunkStartLines;

      expect(starts.first, 0);
      for (int i = 1; i < starts.length; i++) {
        expect(starts[i], greaterThan(starts[i - 1]));
      }
      expect(starts.last, lessThan(lineCount));
    });

    test('chunks tile the document with no gap and no overlap', () {
      final source = doc([
        ...filler(12),
        '```',
        'code',
        '```',
        ...filler(30, 'more'),
      ]);
      final lineCount = source.split('\n').length;

      final layout = layoutOf(source, chunkSize: 10);

      int covered = 0;
      for (int i = 0; i < layout.chunkStartLines.length; i++) {
        expect(layout.chunkStartLines[i], covered);
        covered = chunkEnd(layout, i, lineCount);
      }
      expect(covered, lineCount);
    });

    test('a fence inside the chunk budget is never bisected', () {
      final source = doc([
        'a',
        'b',
        '```',
        'code 1',
        '```',
        ...filler(30, 'tail'),
      ]);

      final layout = layoutOf(source, chunkSize: 10);

      for (final start in layout.chunkStartLines) {
        expect(start > 2 && start < 5, isFalse);
      }
      expectBudgetedBlocksWhole(source, 10);
    });

    test('a callout inside the chunk budget is never bisected', () {
      final source = doc([
        ...filler(3),
        '> [!IMPORTANT]',
        '> one',
        '> two',
        ...filler(30, 'tail'),
      ]);

      final layout = layoutOf(source, chunkSize: 10);

      for (final start in layout.chunkStartLines) {
        expect(start > 3 && start < 6, isFalse);
      }
      expectBudgetedBlocksWhole(source, 10);
    });

    test('the budget rule holds across several chunk sizes', () {
      final source = doc([
        ...filler(5),
        '```',
        'c1',
        'c2',
        '```',
        ...filler(9, 'mid'),
        '> [!NOTE]',
        '> q1',
        '> q2',
        ...filler(23, 'tail'),
        '```',
        'unterminated',
      ]);

      for (final size in [1, 2, 5, 7, 10, 16, 100]) {
        expectBudgetedBlocksWhole(source, size);
      }
    });

    test(
      'a block larger than the budget is divided so virtualization survives',
      () {
        final source = doc([
          ...filler(8),
          '```',
          ...filler(20, 'code'),
          '```',
          'tail',
        ]);

        final layout = layoutOf(source, chunkSize: 10);
        final block = layout.blocks.single;

        expect(block.startLine, 8);
        expect(block.endLine, 30);
        expect(
          layout.chunkStartLines.any(
            (s) => s > block.startLine && s < block.endLine,
          ),
          isTrue,
        );
      },
    );
  });

  group('adaptiveChunkSize', () {
    test('documents under 1000 lines keep the base size', () {
      expect(MarkdownChunker.adaptiveChunkSize(0, 10), 10);
      expect(MarkdownChunker.adaptiveChunkSize(1, 10), 10);
      expect(MarkdownChunker.adaptiveChunkSize(999, 10), 10);
    });

    test('the 1000-line boundary doubles the base size', () {
      expect(MarkdownChunker.adaptiveChunkSize(1000, 10), 20);
      expect(MarkdownChunker.adaptiveChunkSize(9999, 10), 20);
    });

    test('the 10000-line boundary scales the base size five-fold', () {
      expect(MarkdownChunker.adaptiveChunkSize(10000, 10), 50);
      expect(MarkdownChunker.adaptiveChunkSize(49999, 10), 50);
    });

    test('the 50000-line boundary scales ten-fold, landing on the cap', () {
      expect(MarkdownChunker.adaptiveChunkSize(50000, 10), 100);
      expect(
        MarkdownChunker.adaptiveChunkSize(50000, 10),
        MarkdownChunker.maxAdaptiveChunkSize,
      );
    });

    test('huge documents never exceed the cap', () {
      expect(
        MarkdownChunker.adaptiveChunkSize(1000000, 10),
        MarkdownChunker.maxAdaptiveChunkSize,
      );
      expect(
        MarkdownChunker.adaptiveChunkSize(1000000, 40),
        MarkdownChunker.maxAdaptiveChunkSize,
      );
      expect(
        MarkdownChunker.adaptiveChunkSize(10000, 25),
        MarkdownChunker.maxAdaptiveChunkSize,
      );
    });

    test('the result never drops below the base for in-range bases', () {
      for (final base in [1, 5, 10, 20, 50, 100]) {
        for (final lines in [0, 999, 1000, 9999, 10000, 49999, 50000, 200000]) {
          final size = MarkdownChunker.adaptiveChunkSize(lines, base);
          expect(size, greaterThanOrEqualTo(base));
          expect(size, lessThanOrEqualTo(MarkdownChunker.maxAdaptiveChunkSize));
        }
      }
    });

    test('a base already at the cap is returned unscaled', () {
      expect(MarkdownChunker.adaptiveChunkSize(0, 100), 100);
      expect(MarkdownChunker.adaptiveChunkSize(200000, 100), 100);
    });

    test('a base above the cap is clamped down to the cap', () {
      expect(MarkdownChunker.adaptiveChunkSize(0, 150), 100);
      expect(MarkdownChunker.adaptiveChunkSize(200000, 150), 100);
    });
  });

  group('degenerate input', () {
    test('an empty document yields one chunk start and no blocks', () {
      final layout = MarkdownChunker.computeLayout(
        lineCount: 0,
        chunkSize: 10,
        lineAt: (_) => '',
      );

      expect(layout.chunkStartLines, [0]);
      expect(layout.blocks, isEmpty);
    });

    test('a single-line document is one chunk', () {
      final layout = layoutOf('just one line');

      expect(layout.chunkStartLines, [0]);
      expect(layout.blocks, isEmpty);
    });

    test('a single fence line is a block running to EOF', () {
      final layout = layoutOf('```');

      expect(layout.chunkStartLines, [0]);
      expect(layout.blocks.single.startLine, 0);
      expect(layout.blocks.single.endLine, 1);
    });

    test('a document of blank lines still tiles', () {
      final source = doc(List<String>.filled(25, ''));

      final layout = layoutOf(source, chunkSize: 10);

      expect(layout.chunkStartLines, [0, 10, 20]);
      expect(layout.blocks, isEmpty);
    });

    test('a chunk size below one is clamped so progress is guaranteed', () {
      final source = doc(filler(4));

      expect(layoutOf(source, chunkSize: 0).chunkStartLines, [0, 1, 2, 3]);
      expect(layoutOf(source, chunkSize: -5).chunkStartLines, [0, 1, 2, 3]);
    });

    test('a chunk size of one still keeps blocks off the boundary rule', () {
      final source = doc(['a', '```', 'code', '```', 'b']);

      final layout = layoutOf(source, chunkSize: 1);

      expect(layout.chunkStartLines.first, 0);
      for (int i = 1; i < layout.chunkStartLines.length; i++) {
        expect(
          layout.chunkStartLines[i],
          greaterThan(layout.chunkStartLines[i - 1]),
        );
      }
    });

    test('a chunk size larger than the document is one chunk', () {
      final source = doc(filler(9));

      expect(layoutOf(source, chunkSize: 1000).chunkStartLines, [0]);
    });
  });

  group('chunkStartLine / chunkIndexForLine round-trip', () {
    const style = LineMarkdownStyle(
      baseFontSize: 14,
      textColor: Color(0xFF000000),
      primaryColor: Color(0xFF2196F3),
      codeBackground: Color(0xFFEEEEEE),
      blockquoteColor: Color(0xFFDDDDDD),
      highlightColor: Color(0xFFFFF176),
      currentHighlightColor: Color(0xFFFFB74D),
      ghostColor: Color(0x73000000),
      markColor: Color(0xFFFFF59D),
      isDark: false,
    );

    final source = doc([
      '# Heading',
      ...filler(6),
      '```dart',
      'final a = 1;',
      'final b = 2;',
      '```',
      ...filler(14, 'body'),
      '> [!TIP]',
      '> hydrate',
      '> stretch',
      ...filler(20, 'tail'),
      '```',
      'unterminated tail',
    ]);

    late LineBasedMarkdownBuilder builder;

    setUp(() {
      builder = LineBasedMarkdownBuilder(style: style, linesPerChunk: 10);
      builder.prepare(source);
    });

    tearDown(() => builder.dispose());

    test('the builder reproduces the chunker layout exactly', () {
      final layout = layoutOf(source, chunkSize: 10);

      expect(builder.lineCount, source.split('\n').length);
      expect(builder.chunkCount, layout.chunkStartLines.length);
      for (int i = 0; i < builder.chunkCount; i++) {
        expect(builder.chunkStartLine(i), layout.chunkStartLines[i]);
      }
    });

    test('the document spans more than one chunk', () {
      expect(builder.chunkCount, greaterThan(1));
    });

    test('every line maps back into the chunk that contains it', () {
      for (int line = 0; line < builder.lineCount; line++) {
        final index = builder.chunkIndexForLine(line);

        expect(index, inInclusiveRange(0, builder.chunkCount - 1));
        final start = builder.chunkStartLine(index);
        final end = start + builder.chunkLineCount(index);
        expect(
          line,
          inInclusiveRange(start, end - 1),
          reason: 'line $line resolved to chunk $index [$start, $end)',
        );
      }
    });

    test('chunk indices are monotonic across the document', () {
      int previous = 0;
      for (int line = 0; line < builder.lineCount; line++) {
        final index = builder.chunkIndexForLine(line);
        expect(index, anyOf(previous, previous + 1));
        previous = index;
      }
      expect(previous, builder.chunkCount - 1);
    });

    test('every chunk start round-trips to its own chunk index', () {
      for (int i = 0; i < builder.chunkCount; i++) {
        expect(builder.chunkIndexForLine(builder.chunkStartLine(i)), i);
      }
    });

    test('chunk line counts sum to the document line count', () {
      int total = 0;
      for (int i = 0; i < builder.chunkCount; i++) {
        expect(builder.chunkLineCount(i), greaterThan(0));
        total += builder.chunkLineCount(i);
      }
      expect(total, builder.lineCount);
    });

    test('out-of-range chunk indices are clamped rather than throwing', () {
      expect(builder.chunkStartLine(-1), 0);
      expect(builder.chunkStartLine(builder.chunkCount), 0);
      expect(builder.chunkLineCount(-1), 0);
      expect(builder.chunkLineCount(builder.chunkCount), 0);
    });

    test('lines outside the document clamp to the edge chunks', () {
      expect(builder.chunkIndexForLine(-1), 0);
      expect(
        builder.chunkIndexForLine(builder.lineCount + 500),
        builder.chunkCount - 1,
      );
    });
  });
}
