import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/ghost_text.dart';
import 'package:anta/utils/markdown_line_height_calculator.dart';
import 'package:anta/utils/markdown_line_shape.dart';
import 'package:flutter_test/flutter_test.dart';

double scale(String line, {bool code = false}) =>
    MarkdownLineHeightCalculator.getLineHeightScale(
      line,
      isInsideCodeBlock: code,
    );

void main() {
  group('headingAt', () {
    test('levels 1-6 with their content offsets', () {
      for (var level = 1; level <= 6; level++) {
        final line = '${'#' * level} title';
        final h = MarkdownLineShape.headingAt(line);
        expect(h, isNotNull, reason: line);
        expect(h!.level, level, reason: line);
        expect(h.hashStart, 0, reason: line);
        expect(h.hashEnd, level, reason: line);
        expect(h.contentStart, level + 1, reason: line);
        expect(line.substring(h.contentStart), 'title', reason: line);
      }
    });

    test('seven hashes are prose, not a level-7 heading', () {
      expect(MarkdownLineShape.headingAt('####### x'), isNull);
      expect(MarkdownLineShape.headingAt('#######'), isNull);
    });

    test('a hash with no space is a tag, not a heading', () {
      expect(MarkdownLineShape.headingAt('#tag'), isNull);
      expect(MarkdownLineShape.headingAt(r'##$$'), isNull);
    });

    test('a bare run of hashes is an empty heading', () {
      final h = MarkdownLineShape.headingAt('###');
      expect(h, isNotNull);
      expect(h!.level, 3);
      expect(h.contentStart, 3);
      expect('###'.substring(h.contentStart), isEmpty);
    });

    test('indent shifts hashStart and contentStart together', () {
      final spaces = MarkdownLineShape.headingAt('  ## x');
      expect(spaces, isNotNull);
      expect(spaces!.level, 2);
      expect(spaces.hashStart, 2);
      expect(spaces.hashEnd, 4);
      expect(spaces.contentStart, 5);

      final tab = MarkdownLineShape.headingAt('\t# x');
      expect(tab, isNotNull);
      expect(tab!.level, 1);
      expect(tab.hashStart, 1);
      expect(tab.contentStart, 3);
      expect('\t# x'.substring(tab.contentStart), 'x');
    });

    test('only one space is chrome; the rest belongs to the content', () {
      final h = MarkdownLineShape.headingAt('#  two spaces');
      expect(h, isNotNull);
      expect(h!.contentStart, 2);
      expect('#  two spaces'.substring(h.contentStart), ' two spaces');
    });

    test('a trailing space still leaves an empty heading', () {
      final h = MarkdownLineShape.headingAt('# ');
      expect(h, isNotNull);
      expect(h!.level, 1);
      expect(h.contentStart, 2);
    });

    test('a tab after the hashes is not the chrome space', () {
      expect(MarkdownLineShape.headingAt('#\tfoo'), isNull);
      expect(MarkdownLineShape.headingAt('###\tfoo'), isNull);
    });

    test('a lone hash is an empty level-1 heading', () {
      final h = MarkdownLineShape.headingAt('#');
      expect(h, isNotNull);
      expect(h!.level, 1);
      expect(h.hashStart, 0);
      expect(h.hashEnd, 1);
      expect(h.contentStart, 1);
    });

    test('the indent is unbounded — four spaces still lead a heading', () {
      final h = MarkdownLineShape.headingAt('    # indented');
      expect(h, isNotNull);
      expect(h!.level, 1);
      expect(h.hashStart, 4);
      expect(h.contentStart, 6);
      expect('    # indented'.substring(h.contentStart), 'indented');
    });

    test('empty and blank lines are not headings', () {
      expect(MarkdownLineShape.headingAt(''), isNull);
      expect(MarkdownLineShape.headingAt('   '), isNull);
      expect(MarkdownLineShape.headingAt('\t'), isNull);
    });
  });

  group('headingAt contentEnd', () {
    String content(String line) {
      final h = MarkdownLineShape.headingAt(line)!;
      return line.substring(h.contentStart, h.contentEnd);
    }

    test('without a closing run the content runs to the line end', () {
      expect(MarkdownLineShape.headingAt('## Title')!.contentEnd, 8);
      expect(content('## Title  '), 'Title  ');
      expect(MarkdownLineShape.headingAt('###')!.contentEnd, 3);
    });

    test('a closing run after a blank is not content, nor the blanks', () {
      expect(content('## Week 3 ##'), 'Week 3');
      expect(content('# Title #'), 'Title');
      expect(content('### Title   ###'), 'Title');
      expect(content('## Title\t##'), 'Title');
    });

    test('blanks after the closing run belong to it', () {
      expect(content('## Week 3 ##  '), 'Week 3');
    });

    test('a closing run of any length counts', () {
      expect(content('# Title ######'), 'Title');
    });

    test('hashes glued to the content stay content', () {
      expect(content('## Title##'), 'Title##');
      expect(content('## C#'), 'C#');
      expect(content(r'## foo \##'), r'foo \##');
    });

    test('a heading of only closing hashes is empty', () {
      final h = MarkdownLineShape.headingAt('## ##')!;
      expect(h.contentStart, 3);
      expect(h.contentEnd, 3);
      expect(content('#   #'), '');
    });

    test('a tag or prose hash before the end is untouched', () {
      expect(content('# Log #gym'), 'Log #gym');
      expect(content('# Week #3 done'), 'Week #3 done');
    });
  });

  group('isHorizontalRule', () {
    test('three or more of one marker', () {
      expect(MarkdownLineShape.isHorizontalRule('---'), isTrue);
      expect(MarkdownLineShape.isHorizontalRule('***'), isTrue);
      expect(MarkdownLineShape.isHorizontalRule('_____'), isTrue);
      expect(MarkdownLineShape.isHorizontalRule('  ---  '), isTrue);
    });

    test('short, mixed, or trailed runs are prose', () {
      expect(MarkdownLineShape.isHorizontalRule('--'), isFalse);
      expect(MarkdownLineShape.isHorizontalRule('-*-'), isFalse);
      expect(MarkdownLineShape.isHorizontalRule('--- x'), isFalse);
      expect(MarkdownLineShape.isHorizontalRule(''), isFalse);
    });

    test('spaces or tabs between the markers still make a rule', () {
      expect(MarkdownLineShape.isHorizontalRule('- - -'), isTrue);
      expect(MarkdownLineShape.isHorizontalRule('* * *'), isTrue);
      expect(MarkdownLineShape.isHorizontalRule('_ _ _'), isTrue);
      expect(MarkdownLineShape.isHorizontalRule('-  --\t-'), isTrue);
      expect(MarkdownLineShape.isHorizontalRule('   * * * *  '), isTrue);
    });

    test('spaced runs still need three of one marker and nothing else', () {
      expect(MarkdownLineShape.isHorizontalRule('- -'), isFalse);
      expect(MarkdownLineShape.isHorizontalRule('- * -'), isFalse);
      expect(MarkdownLineShape.isHorizontalRule('- - - x'), isFalse);
      expect(MarkdownLineShape.isHorizontalRule('- - x -'), isFalse);
    });

    test('tabs count as indent and as trailing blanks', () {
      expect(MarkdownLineShape.isHorizontalRule('---\t'), isTrue);
      expect(MarkdownLineShape.isHorizontalRule('\t---'), isTrue);
    });

    test('only spaces and tabs are blanks; other whitespace is not', () {
      expect(MarkdownLineShape.isHorizontalRule('\u00a0- - -'), isFalse);
      expect(MarkdownLineShape.isHorizontalRule('- -\u00a0-'), isFalse);
      expect(MarkdownLineShape.isHorizontalRule('   '), isFalse);
      expect(MarkdownLineShape.isHorizontalRule('+++'), isFalse);
    });

    // CommonMark: a rule beats a list item, so opening bold on a `* `
    // bullet reads as a rule until the first letter is typed.
    test('a bold opener on an asterisk bullet is a rule until a letter', () {
      expect(MarkdownLineShape.isHorizontalRule('* **'), isTrue);
      expect(MarkdownLineShape.isHorizontalRule('* ****'), isTrue);
      expect(MarkdownLineShape.isHorizontalRule('* **b'), isFalse);
    });
  });

  group('isTableRow', () {
    test('a line fenced by pipes, at least two units wide', () {
      expect(MarkdownLineShape.isTableRow('| a | b |'), isTrue);
      expect(MarkdownLineShape.isTableRow('|a|'), isTrue);
      expect(MarkdownLineShape.isTableRow('||'), isTrue);
    });

    test('leading whitespace is indent, not content', () {
      expect(MarkdownLineShape.isTableRow('  | a |'), isTrue);
      expect(MarkdownLineShape.isTableRow('\t| a |'), isTrue);
    });

    test('trailing whitespace is ignored — the row still counts', () {
      expect(MarkdownLineShape.isTableRow('| a |  '), isTrue);
      expect(MarkdownLineShape.isTableRow('| a |\t'), isTrue);
    });

    test('an unclosed, unopened or lone pipe is prose', () {
      expect(MarkdownLineShape.isTableRow('| a'), isFalse);
      expect(MarkdownLineShape.isTableRow('a |'), isFalse);
      expect(MarkdownLineShape.isTableRow('|'), isFalse);
    });

    test('empty and blank lines are not rows', () {
      expect(MarkdownLineShape.isTableRow(''), isFalse);
      expect(MarkdownLineShape.isTableRow('  '), isFalse);
    });
  });

  group('isTableSeparator', () {
    test('dashes, colons and spacing between the pipes', () {
      expect(MarkdownLineShape.isTableSeparator('|---|---|'), isTrue);
      expect(MarkdownLineShape.isTableSeparator('| --- | --- |'), isTrue);
      expect(MarkdownLineShape.isTableSeparator('|:--:|'), isTrue);
      expect(MarkdownLineShape.isTableSeparator('| :-- | --: |'), isTrue);
      expect(MarkdownLineShape.isTableSeparator('|---|'), isTrue);
    });

    test('a cell holding content is a body row, not a delimiter', () {
      expect(MarkdownLineShape.isTableSeparator('| a | b |'), isFalse);
      expect(MarkdownLineShape.isTableSeparator('| --- | b |'), isFalse);
    });

    test('a separator must first be a table row', () {
      expect(MarkdownLineShape.isTableSeparator('---'), isFalse);
      expect(MarkdownLineShape.isTableSeparator(''), isFalse);
    });

    test('an escaped pipe in a cell leaves the delimiter rule alone', () {
      expect(MarkdownLineShape.isTableSeparator('| --- | --- |'), isTrue);
      expect(MarkdownLineShape.isTableSeparator(r'| --- \| --- |'), isFalse);
      expect(MarkdownLineShape.isTableSeparator(r'| a \| b | c |'), isFalse);
    });
  });

  group('nextTableCellPipe', () {
    List<int> boundaries(String line, [List<GhostMatch>? ghosts]) {
      final out = <int>[];
      final g = ghosts ?? GhostText.findGhosts(line);
      for (
        var i = MarkdownLineShape.nextTableCellPipe(line, 0, g);
        i >= 0;
        i = MarkdownLineShape.nextTableCellPipe(line, i + 1, g)
      ) {
        out.add(i);
      }
      return out;
    }

    test('every bare pipe is a boundary', () {
      expect(boundaries('| a | b |'), [0, 4, 8]);
      expect(boundaries('||'), [0, 1]);
      expect(boundaries('no pipes'), isEmpty);
    });

    test('an escaped pipe is cell content, so the row has two cells', () {
      const line = r'| a \| b | c |';
      expect(boundaries(line), [0, 9, 13]);
    });

    test('an escaped backslash leaves the pipe after it a boundary', () {
      expect(boundaries(r'| a \\| b |'), [0, 6, 10]);
    });

    test('a backslash before a letter escapes nothing', () {
      expect(boundaries(r'| \a | b |'), [0, 5, 9]);
    });

    test('a wiki alias pipe belongs to the link, so the row has two cells', () {
      const line = '| [[Session 1|legs]] | x |';
      expect(boundaries(line), [0, 21, 25]);
    });

    test('a bracket run that is no wiki link leaves its pipe a boundary', () {
      expect(boundaries('| [[a | b |'), [0, 6, 10]);
      expect(boundaries(r'| \[[a|b]] |'), [0, 6, 11]);
    });

    test('a pipe inside a ghost is the ghost\'s content', () {
      expect(boundaries('| {{a|b}} | c |'), [0, 10, 14]);
    });

    test('a backslash before a ghost escapes nothing', () {
      // `\{{` is no escape — the ghost wins, as it does in the tokenizer —
      // and the ghost's own pipe stays inside it.
      expect(boundaries(r'| \{{a|b}} |'), [0, 11]);
    });

    test('a wiki link overlapping a ghost is not one', () {
      // The tokenizer never builds a link that cuts into a ghost, so the
      // `|` before the ghost is a boundary again.
      expect(boundaries('| [[a|{{g]]}} |'), [0, 5, 14]);
    });

    test('a scan resumes from any boundary it returned', () {
      const line = '| [[a|b]] | c |';
      expect(MarkdownLineShape.nextTableCellPipe(line, 1), 10);
      expect(MarkdownLineShape.nextTableCellPipe(line, 11), 14);
      expect(MarkdownLineShape.nextTableCellPipe(line, 15), -1);
    });

    test('a resumed scan finds the ghosts after its start', () {
      const line = '| {{a|b}} | {{c|d}} | e |';
      final ghosts = GhostText.findGhosts(line);
      expect(MarkdownLineShape.nextTableCellPipe(line, 11, ghosts), 20);
      expect(boundaries(line), [0, 10, 20, 24]);
    });

    test(
      'a wiki link holding an escape is refused, as tokenize refuses it',
      () {
        expect(boundaries(r'| [[a|b\_c]] | x |'), [0, 5, 13, 17]);
        // Obsidian's in-table alias spelling: no link, and no split either.
        expect(boundaries(r'| [[Squat\|legs]] | 3x5 |'), [0, 18, 24]);
      },
    );

    test('a wiki link holding a closed code span is refused', () {
      expect(boundaries('| [[Bench|`PR`]] | x |'), [0, 9, 17, 21]);
    });

    test('a lone backtick inside a wiki link leaves the link whole', () {
      expect(boundaries('| [[a`b|c]] | x |'), [0, 12, 16]);
    });

    test('a [[ inside a code span opens no wiki link', () {
      expect(boundaries('| `[[x` | y]] |'), [0, 8, 14]);
      expect(boundaries('| `[[a`|b]] | c |'), [0, 7, 12, 16]);
    });

    test('a code span never reaches across a bare pipe', () {
      expect(boundaries('| `a | b` |'), [0, 5, 10]);
      expect(boundaries(r'| `a\|b` | c |'), [0, 9, 13]);
      expect(boundaries(r'| `a\\|b` | c |'), [0, 6, 10, 14]);
    });
  });

  group('isLineLedConstruct', () {
    test('headings and heading-prefixed money rows', () {
      expect(MarkdownLineShape.isLineLedConstruct('## x'), isTrue);
      expect(MarkdownLineShape.isLineLedConstruct(r'## $$'), isTrue);
      // A space-less money heading (`##$$` == `## $$` to the money
      // grammar) is not a heading, but it is a money row and stays
      // line-led through the money fallback.
      expect(MarkdownLineShape.isLineLedConstruct(r'##$$'), isTrue);
      expect(MarkdownLineShape.isLineLedConstruct(r'##x'), isFalse);
      expect(MarkdownLineShape.isLineLedConstruct(r'- ## $$ x'), isTrue);
    });

    test('a tag is not a heading and not line-led', () {
      expect(MarkdownLineShape.isLineLedConstruct('#tag'), isFalse);
    });

    test('quotes, table rows and fences', () {
      expect(MarkdownLineShape.isLineLedConstruct('> quote'), isTrue);
      expect(MarkdownLineShape.isLineLedConstruct('>'), isTrue);
      expect(MarkdownLineShape.isLineLedConstruct('> [!TIP] hint'), isTrue);
      expect(MarkdownLineShape.isLineLedConstruct('| a |'), isTrue);
      expect(
        MarkdownLineShape.isLineLedConstruct('| a |  '),
        isTrue,
        reason:
            'a trailing blank no longer disqualifies a row on either surface, '
            'so the paste policies must keep the line intact too',
      );
      expect(MarkdownLineShape.isLineLedConstruct('a | b'), isFalse);
      expect(MarkdownLineShape.isLineLedConstruct('```'), isTrue);
      expect(MarkdownLineShape.isLineLedConstruct('```dart'), isTrue);
    });

    test('a lead reads as the dispatchers read it, not as trim does', () {
      // A no-break space leads no heading, rule or table row on either
      // surface, while the quote grammar skips it; space and tab lead all.
      expect(MarkdownLineShape.isLineLedConstruct('\u00a0## x'), isFalse);
      expect(MarkdownLineShape.isLineLedConstruct('\u00a0---'), isFalse);
      expect(MarkdownLineShape.isLineLedConstruct('\u00a0| a |'), isFalse);
      expect(MarkdownLineShape.isLineLedConstruct('\u00a0> quote'), isTrue);
      expect(MarkdownLineShape.isLineLedConstruct(' \t## x'), isTrue);
      expect(MarkdownLineShape.isLineLedConstruct('\u00a0'), isFalse);
    });

    test('a no-break-space lead leads no money row and no fence', () {
      const shapes = <String>['\$- 12.50 coffee', '- \$+ 12.50', '```'];
      for (final shape in shapes) {
        expect(
          MarkdownLineShape.isLineLedConstruct('\u00a0$shape'),
          isFalse,
          reason: 'no-break space before "$shape"',
        );
        expect(
          MarkdownLineShape.isLineLedConstruct('  $shape'),
          isTrue,
          reason: 'spaces before "$shape"',
        );
      }
    });

    test('plain prose and empty lines are free to reflow', () {
      expect(MarkdownLineShape.isLineLedConstruct('just words'), isFalse);
      expect(MarkdownLineShape.isLineLedConstruct(''), isFalse);
      expect(MarkdownLineShape.isLineLedConstruct(r'$5 coffee'), isFalse);
    });
  });

  group('line height calculator', () {
    test('headings scale by level', () {
      expect(scale('# h1'), MarkdownConstants.h1Scale);
      expect(scale('###### h6'), MarkdownConstants.h6Scale);
      expect(scale('###'), MarkdownConstants.h3Scale);
    });

    test('non-headings keep the normal scale', () {
      expect(scale('#tag'), MarkdownConstants.normalLineScale);
      expect(scale('####### x'), MarkdownConstants.normalLineScale);
      expect(scale('- item'), MarkdownConstants.normalLineScale);
    });

    test('rules and empty lines are half height', () {
      expect(scale('---'), MarkdownConstants.horizontalRuleScale);
      expect(scale('***'), MarkdownConstants.horizontalRuleScale);
      expect(scale('- - -'), MarkdownConstants.horizontalRuleScale);
      expect(scale('* * *'), MarkdownConstants.horizontalRuleScale);
      expect(scale('- - x'), MarkdownConstants.normalLineScale);
      expect(scale(''), MarkdownConstants.emptyLineScale);
      expect(scale('   '), MarkdownConstants.emptyLineScale);
    });

    test('code-block lines outrank every other shape', () {
      expect(scale('# h1', code: true), MarkdownConstants.codeBlockScale);
      expect(scale('', code: true), MarkdownConstants.codeBlockScale);
      expect(scale('plain', code: true), MarkdownConstants.codeBlockScale);
    });
  });
}
