import 'package:anta/constants/markdown_constants.dart';
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

    test('the markers must be adjacent — spaced runs are prose', () {
      expect(MarkdownLineShape.isHorizontalRule('- - -'), isFalse);
      expect(MarkdownLineShape.isHorizontalRule('* * *'), isFalse);
      expect(MarkdownLineShape.isHorizontalRule('_ _ _'), isFalse);
    });

    test('tabs count as indent and as trailing blanks', () {
      expect(MarkdownLineShape.isHorizontalRule('---\t'), isTrue);
      expect(MarkdownLineShape.isHorizontalRule('\t---'), isTrue);
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
      expect(MarkdownLineShape.isLineLedConstruct('a | b'), isFalse);
      expect(MarkdownLineShape.isLineLedConstruct('```'), isTrue);
      expect(MarkdownLineShape.isLineLedConstruct('```dart'), isTrue);
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
