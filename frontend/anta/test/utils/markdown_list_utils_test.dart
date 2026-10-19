import 'package:anta/utils/markdown_list_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two Enter decisions `EditorEditTracker` reads off the line above
/// the caret, pinned on line text alone: what the new line starts with
/// ([MarkdownListUtils.continuationPrefix]) and what an Enter on a bare
/// marker takes back ([MarkdownListUtils.emptyLineEnd]). The tracker
/// suite drives the same rules through a real controller; this one walks
/// the shapes the tracker cannot reach cheaply.
void main() {
  group('continuationPrefix', () {
    test('a list line continues with getListPrefix', () {
      for (final line in const [
        '- a',
        '  * nested',
        '3. third',
        '- [x] done',
        '\t- tabbed',
      ]) {
        expect(
          MarkdownListUtils.continuationPrefix(line),
          MarkdownListUtils.getListPrefix(line),
          reason: '"$line"',
        );
      }
    });

    test('a spaced rule continues nothing: it is not a bullet', () {
      for (final line in const ['- - -', '* * *', '  - - - -']) {
        expect(
          MarkdownListUtils.continuationPrefix(line),
          isNull,
          reason: line,
        );
      }
      expect(MarkdownListUtils.continuationPrefix('> * * *'), '> ');
      expect(MarkdownListUtils.continuationPrefix('- - x'), '- ');
    });

    test('a quote line continues its `>` run as written', () {
      expect(MarkdownListUtils.continuationPrefix('> a'), '> ');
      expect(MarkdownListUtils.continuationPrefix('> > a'), '> > ');
      expect(MarkdownListUtils.continuationPrefix('>> a'), '>> ');
      expect(MarkdownListUtils.continuationPrefix('>a'), '>');
      expect(MarkdownListUtils.continuationPrefix('  > a'), '  > ');
    });

    test('a callout lead continues into its body', () {
      expect(MarkdownListUtils.continuationPrefix('> [!TIP] title'), '> ');
      expect(MarkdownListUtils.continuationPrefix('> [!WARNING]'), '> ');
    });

    test('a list inside a quote continues both', () {
      expect(MarkdownListUtils.continuationPrefix('> - a'), '> - ');
      expect(MarkdownListUtils.continuationPrefix('> 1. a'), '> 2. ');
      expect(MarkdownListUtils.continuationPrefix('> - [x] a'), '> - [ ] ');
      expect(MarkdownListUtils.continuationPrefix('> >   - a'), '> >   - ');
    });

    test('a list item that quotes stays a list item', () {
      expect(MarkdownListUtils.continuationPrefix('- > a'), '- ');
    });

    test('prose continues nothing', () {
      expect(MarkdownListUtils.continuationPrefix('just prose'), isNull);
      expect(MarkdownListUtils.continuationPrefix(''), isNull);
      expect(MarkdownListUtils.continuationPrefix('a > b'), isNull);
    });
  });

  group('emptyLineEnd', () {
    MarkdownEmptyLineEnd? endOf(String line) =>
        MarkdownListUtils.emptyLineEnd(line);

    String? endText(String line) => switch (endOf(line)) {
      MarkdownEndMarker(:final text) => text,
      _ => null,
    };

    test('a top-level empty item ends on a bare line', () {
      for (final line in const ['- ', '* ', '1. ', '- [ ] ', ' - ', '-   ']) {
        expect(endText(line), '', reason: '"$line"');
      }
    });

    test('a nested empty item outdents, quote run kept apart', () {
      final end = endOf('    - [ ] ');
      expect(end, isA<MarkdownOutdentItem>());
      end as MarkdownOutdentItem;
      expect(end.quote, '');
      expect(end.item, '    - [ ] ');

      final quoted = endOf('>   - ');
      expect(quoted, isA<MarkdownOutdentItem>());
      quoted as MarkdownOutdentItem;
      expect(quoted.quote, '> ');
      expect(quoted.item, '  - ');

      expect(endOf('\t- '), isA<MarkdownOutdentItem>());
    });

    test('a top-level empty item in a quote ends into the quote', () {
      expect(endText('> - '), '> ');
      expect(endText('> > 2. '), '> > ');
    });

    test('an empty quote line ends the quote', () {
      for (final line in const ['>', '> ', '  > ', '>   ']) {
        expect(endText(line), '', reason: '"$line"');
      }
    });

    test('an empty nested quote line drops its innermost marker only', () {
      expect(endText('> > '), '> ');
      expect(endText('> > > '), '> > ');
      expect(endText('>>'), '>');
      expect(endText('  > >   '), '  > ');
    });

    test('a callout lead is never empty', () {
      expect(endOf('> [!TIP]'), isNull);
      expect(endOf('> [!NOTE] title'), isNull);
    });

    test('a line with content is not empty', () {
      for (final line in const ['- a', '  - a', '> a', '> - a', 'prose', '']) {
        expect(endOf(line), isNull, reason: '"$line"');
      }
    });
  });
}
