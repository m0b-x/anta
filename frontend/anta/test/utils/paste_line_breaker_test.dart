import 'dart:math';

import 'package:anta/constants/font_constants.dart';
import 'package:anta/utils/editor_width_calculator.dart';
import 'package:anta/utils/markdown_line_shape.dart';
import 'package:anta/utils/paste_line_breaker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Guards the paste reformatter's contracts:
///
/// * it finds the pasted range in **line** coordinates (a caret position and
///   a code-unit count), never by joining the document into a flat string;
/// * it rewrites only `[start, end]` — every line outside it comes back
///   byte-identical and every untouched segment keeps its backing-list
///   identity, which is what the editor's incremental line index reads as
///   "nothing to re-render here";
/// * the reformat overwrites the paste's undo node, so paste + line-breaking
///   is a single undo step;
/// * `EditorWidthCalculator`'s ASCII pre-filter answers exactly what the
///   painter would, while keeping the painter off the fitting lines.
void main() {
  // Nothing is mounted: `run` takes the measured width as a parameter. The
  // binding is still needed because every width comes from a `TextPainter`
  // laid out through dart:ui. The test font advances every glyph by the font
  // size, so the widths below are exact multiples of it.
  TestWidgetsFlutterBinding.ensureInitialized();

  const double fontSize = 16.0;

  /// Ten glyphs of the test font.
  const double width = fontSize * 10;

  /// 48 code units — five width-lines' worth, with spaces to break at.
  const String longLine = 'alpha bravo charlie delta echo foxtrot golf hotel';

  EditorWidthCalculator newCalculator() => EditorWidthCalculator(
    config: EditorWidthConfig(
      editorContainerKey: GlobalKey(),
      fontSize: fontSize,
      fontFamily: FontConstants.editorFontFamily,
    ),
    editorPadding: EdgeInsets.zero,
  );

  String shortLine(int i) => 'row $i';

  List<List<CodeLine>> backingLists(CodeLineEditingController controller) => [
    for (final segment in controller.codeLines.segments) segment.codeLines,
  ];

  PasteLineBreakerResult runOn(
    CodeLineEditingController controller, {
    required int endIndex,
    required int endOffset,
    required int pastedLength,
  }) {
    return PasteLineBreaker.run(
      controller: controller,
      calculator: newCalculator(),
      availableWidth: width,
      pasteEnd: CodeLinePosition(index: endIndex, offset: endOffset),
      pastedLength: pastedLength,
    );
  }

  setUp(() {
    EditorWidthCalculator.debugLayoutCount = 0;
  });

  group('range splice', () {
    // 700 lines is three 256-line segments, so the splice has untouched
    // segments on both sides of the range it rebuilds.
    const int documentLines = 700;
    const int rangeStart = 300;
    const int rangeEnd = 302;

    List<String> document() => List<String>.generate(
      documentLines,
      (i) => i >= rangeStart && i <= rangeEnd ? '$longLine $i' : shortLine(i),
    );

    test('rewrites only the pasted range', () {
      final lines = document();
      final controller = CodeLineEditingController.fromText(lines.join('\n'));
      expect(controller.codeLines.segments, hasLength(3));
      final before = backingLists(controller);

      final expected = newCalculator().breakLinesSmartly(
        lines.sublist(rangeStart, rangeEnd + 1),
        width,
      );
      expect(expected.linesModified, 3);
      expect(expected.lines.length, greaterThan(3));

      final result = runOn(
        controller,
        endIndex: rangeEnd,
        endOffset: lines[rangeEnd].length,
        pastedLength:
            lines[rangeStart].length +
            1 +
            lines[rangeStart + 1].length +
            1 +
            lines[rangeEnd].length,
      );

      expect(result.reformatted, isTrue);
      expect(result.linesModified, 3);

      final codeLines = controller.codeLines;
      expect(codeLines.length, documentLines - 3 + expected.lines.length);

      for (int i = 0; i < rangeStart; i++) {
        expect(codeLines[i].text, lines[i], reason: 'prefix line $i moved');
      }
      for (int i = 0; i < expected.lines.length; i++) {
        expect(codeLines[rangeStart + i].text, expected.lines[i]);
      }
      final suffixStart = rangeStart + expected.lines.length;
      for (int i = rangeEnd + 1; i < documentLines; i++) {
        expect(
          codeLines[suffixStart + i - rangeEnd - 1].text,
          lines[i],
          reason: 'suffix line $i moved',
        );
      }

      // The caret lands at the end of the reformatted block.
      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.baseIndex, suffixStart - 1);
      expect(controller.selection.baseOffset, expected.lines.last.length);

      // Only the segments the range sat in are rebuilt; the first and last
      // are carried over by reference.
      final after = backingLists(controller);
      expect(identical(after.first, before.first), isTrue);
      expect(identical(after.last, before.last), isTrue);
      expect(after.any((list) => identical(list, before[1])), isFalse);
    });

    test('nothing over-long leaves the value instance alone', () {
      final controller = CodeLineEditingController.fromText(
        List<String>.generate(20, shortLine).join('\n'),
      );
      final before = controller.value;

      final result = runOn(
        controller,
        endIndex: 19,
        endOffset: shortLine(19).length,
        pastedLength: 100,
      );

      expect(result.reformatted, isFalse);
      expect(result.linesModified, 0);
      expect(identical(controller.value, before), isTrue);
    });
  });

  group('lines the breaker must leave alone', () {
    test('a fence pair inside the range keeps its code line intact', () {
      final lines = <String>['```dart', longLine, '```', longLine];
      final text = lines.join('\n');
      final controller = CodeLineEditingController.fromText(text);

      final result = runOn(
        controller,
        endIndex: 3,
        endOffset: longLine.length,
        pastedLength: text.length,
      );

      expect(result.linesModified, 1);
      expect(controller.codeLines[0].text, '```dart');
      expect(controller.codeLines[1].text, longLine);
      expect(controller.codeLines[2].text, '```');
      expect(controller.codeLines[3].text, isNot(longLine));
    });

    test('a heading and a money row inside the range are never broken', () {
      const heading = '## a heading long enough to need several width lines';
      const moneyRow = r'$+ 25.50 groceries bought at the far side of town';
      // Both are line-led: a width split would strip the lead marker off
      // the tail and with it the construct's meaning.
      expect(MarkdownLineShape.isLineLedConstruct(heading), isTrue);
      expect(MarkdownLineShape.isLineLedConstruct(moneyRow), isTrue);

      final lines = <String>[heading, moneyRow, longLine];
      final text = lines.join('\n');
      final controller = CodeLineEditingController.fromText(text);

      final result = runOn(
        controller,
        endIndex: 2,
        endOffset: longLine.length,
        pastedLength: text.length,
      );

      expect(result.linesModified, 1);
      expect(controller.codeLines[0].text, heading);
      expect(controller.codeLines[1].text, moneyRow);
      expect(controller.codeLines[2].text, isNot(longLine));
    });
  });

  group('start line from a caret and a code-unit count', () {
    test('a multi-line paste ending mid-line starts where it began', () {
      final controller = CodeLineEditingController.fromText(
        '$longLine\n$longLine',
      );
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 12,
      );
      final beforeLength = controller.textLength;
      controller.replaceSelection('ab\ncd');
      final pastedLength = controller.textLength - beforeLength;
      expect(pastedLength, 5);
      expect(controller.codeLines.length, 3);
      expect(controller.codeLines[2].text, longLine);

      final result = PasteLineBreaker.run(
        controller: controller,
        calculator: newCalculator(),
        availableWidth: width,
        pasteEnd: controller.selection.extent,
        pastedLength: pastedLength,
      );

      // The range is [0, 1]: both halves of the split line are over-long,
      // and the line the paste never reached stays whole.
      expect(result.linesModified, 2);
      expect(controller.codeLines.last.text, longLine);
    });

    test('a single-line paste covers the caret line only', () {
      final controller = CodeLineEditingController.fromText('hello\n$longLine');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 5,
      );
      final beforeLength = controller.textLength;
      controller.replaceSelection(longLine);
      final pastedLength = controller.textLength - beforeLength;
      expect(pastedLength, longLine.length);
      expect(controller.selection.baseIndex, 0);

      final result = PasteLineBreaker.run(
        controller: controller,
        calculator: newCalculator(),
        availableWidth: width,
        pasteEnd: controller.selection.extent,
        pastedLength: pastedLength,
      );

      expect(result.linesModified, 1);
      expect(controller.codeLines.last.text, longLine);
    });
  });

  group('undo', () {
    test('paste + reformat is a single undo step', () {
      final controller = CodeLineEditingController.fromText('row 0');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 5,
      );
      final beforeLength = controller.textLength;
      controller.replaceSelection('\n$longLine');
      final pastedLength = controller.textLength - beforeLength;

      final result = PasteLineBreaker.run(
        controller: controller,
        calculator: newCalculator(),
        availableWidth: width,
        pasteEnd: controller.selection.extent,
        pastedLength: pastedLength,
      );
      expect(result.reformatted, isTrue);
      expect(controller.codeLines.length, greaterThan(2));

      controller.undo();

      expect(controller.text, 'row 0');
      expect(controller.codeLines.length, 1);
    });
  });

  group('the ASCII advance pre-filter', () {
    test('short ASCII lines never reach the painter', () {
      final calculator = newCalculator();
      for (int i = 0; i < 200; i++) {
        expect(calculator.lineExceedsWidth(shortLine(i), width), isFalse);
      }
      expect(EditorWidthCalculator.debugLayoutCount, 0);
    });

    test('a non-ASCII line falls through to the painter', () {
      final calculator = newCalculator();
      expect(calculator.lineExceedsWidth('héllo', width), isFalse);
      expect(EditorWidthCalculator.debugLayoutCount, 1);
    });

    test('an over-long ASCII line falls through to the painter', () {
      final calculator = newCalculator();
      expect(calculator.lineExceedsWidth(longLine, width), isTrue);
      expect(EditorWidthCalculator.debugLayoutCount, 1);
    });

    test('the fitting lines of a breaking pass cost no layouts', () {
      final calculator = newCalculator();
      calculator.breakLinesSmartly(
        List<String>.generate(20, (i) => '$longLine $i'),
        width,
      );
      final longOnly = EditorWidthCalculator.debugLayoutCount;
      expect(longOnly, greaterThan(0));

      EditorWidthCalculator.debugLayoutCount = 0;
      calculator.breakLinesSmartly(
        List<String>.generate(
          200,
          (i) => i % 10 == 0 ? '$longLine ${i ~/ 10}' : shortLine(i),
        ),
        width,
      );

      // The same 20 over-long lines, now with 180 fitting ones between
      // them — and those 180 reach the painter zero times.
      expect(EditorWidthCalculator.debugLayoutCount, longOnly);
    });

    test('a fitting remainder ends the break loop without a layout', () {
      final calculator = newCalculator();
      // One over-long ASCII line: every loop turn but the last has to
      // measure (the table only ever proves "fits"), and the last turn —
      // the fitting remainder — is settled by the table alone.
      calculator.breakLinesSmartly([longLine], width);
      final withPreFilter = EditorWidthCalculator.debugLayoutCount;

      EditorWidthCalculator.debugLayoutCount = 0;
      calculator.breakLinesSmartly(['é${longLine.substring(1)}'], width);
      final withoutPreFilter = EditorWidthCalculator.debugLayoutCount;

      expect(withPreFilter, lessThan(withoutPreFilter));
    });

    test('agrees with the painter on 200 random ASCII strings', () {
      final calculator = newCalculator();
      final random = Random(20260904);
      for (int i = 0; i < 200; i++) {
        final text = String.fromCharCodes(
          List<int>.generate(
            random.nextInt(24),
            (_) => 0x20 + random.nextInt(0x5F),
          ),
        );
        expect(
          calculator.lineExceedsWidth(text, width),
          calculator.measureTextWidth(text) > width,
          reason: 'disagreement on "$text"',
        );
      }
    });
  });

  group('the break-point search', () {
    /// The search as it read before the ASCII seed: `low` starts at 0 and
    /// every step asks the painter.
    int naiveBreakPoint(
      EditorWidthCalculator calculator,
      String text,
      double maxWidth,
    ) {
      int low = 0;
      int high = text.length;
      while (low < high) {
        final mid = (low + high + 1) ~/ 2;
        if (calculator.measureTextWidth(text.substring(0, mid)) <= maxWidth) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      return low;
    }

    test('the ASCII seed never moves the break point', () {
      final calculator = newCalculator();
      final random = Random(20260905);
      for (int i = 0; i < 300; i++) {
        final length = 1 + random.nextInt(200);
        final text = String.fromCharCodes(
          List<int>.generate(
            length,
            // Spaces at ~1 in 6 so word boundaries actually occur.
            (_) => random.nextInt(6) == 0 ? 0x20 : 0x21 + random.nextInt(0x5E),
          ),
        );
        for (final maxWidth in const <double>[80, 200, 360]) {
          expect(
            calculator.findBreakPoint(text, maxWidth),
            naiveBreakPoint(calculator, text, maxWidth),
            reason: 'seeded search diverged at $maxWidth on "$text"',
          );
        }
      }
    });

    test('the seed collapses the search for a text barely over the width', () {
      final calculator = newCalculator();
      final text = 'x' * 200;
      // Wide enough for all but the last glyph: the provably-fitting ASCII
      // prefix is then the answer itself and the search has one step left,
      // where the unseeded search still has to bisect the whole length.
      const maxWidth = 199 * fontSize;

      EditorWidthCalculator.debugLayoutCount = 0;
      final seeded = calculator.findBreakPoint(text, maxWidth);
      final seededLayouts = EditorWidthCalculator.debugLayoutCount;

      EditorWidthCalculator.debugLayoutCount = 0;
      final naive = naiveBreakPoint(calculator, text, maxWidth);
      final naiveLayouts = EditorWidthCalculator.debugLayoutCount;

      expect(seeded, 199);
      expect(seeded, naive);
      expect(seededLayouts, lessThanOrEqualTo(1));
      expect(naiveLayouts, greaterThan(seededLayouts));
    });

    test('breaking an ASCII line no longer re-measures the whole line', () {
      const ascii =
          'abcdefghi abcdefghi abcdefghi abcdefghi abcdefghi '
          'abcdefghi abcdefghi abcdefghi abcdefghi abcdefghi ';
      expect(ascii.length, 100);
      // The same line with its first code unit outside ASCII, which
      // disables the pre-filter and the seed for every prefix of it.
      final nonAscii = 'é${ascii.substring(1)}';
      expect(nonAscii.length, 100);

      final calculator = newCalculator();
      EditorWidthCalculator.debugLayoutCount = 0;
      calculator.breakLinesSmartly([ascii], width);
      final asciiLayouts = EditorWidthCalculator.debugLayoutCount;

      EditorWidthCalculator.debugLayoutCount = 0;
      calculator.breakLinesSmartly([nonAscii], width);
      final nonAsciiLayouts = EditorWidthCalculator.debugLayoutCount;

      // Pinned numbers, not just a comparison: a regression that
      // re-measures the whole line on entry, drops the loop's pre-filter,
      // or unseeds `findBreakPoint` shows up here as a bigger number. The
      // non-ASCII line runs the unaided path and is the "before" baseline.
      // Measured numbers, not just a comparison: a regression that
      // re-measures the whole line on entry, drops the loop's pre-filter,
      // or unseeds `findBreakPoint` shows up here as a bigger one. The
      // non-ASCII line runs the unaided path and is the baseline — the gap
      // is narrow because the binary search still asks the painter for
      // every "does this prefix fit", which only an exact prefix-width
      // source (not an upper bound) could remove.
      expect(asciiLayouts, lessThanOrEqualTo(56));
      expect(nonAsciiLayouts, greaterThan(asciiLayouts));
    });

    test('the reformatted corpus is byte-identical to the unseeded output', () {
      // Golden captured from the implementation before the entry-measure
      // removal and the `findBreakPoint` seed. Neither may move a single
      // code unit of the output.
      final calculator = newCalculator();
      final result = calculator.breakLinesSmartly(_corpus, width);

      expect(result.linesModified, 9);
      expect(result.lines, _corpusGolden);
    });
  });
}

/// A fixed reformat corpus: prose, an empty line, line-led constructs the
/// breaker must skip, a fence pair, and every protected range kind.
const List<String> _corpus = <String>[
  'row 0',
  'alpha bravo charlie delta echo foxtrot golf hotel',
  '',
  '## a heading long enough to need several width lines',
  r'$+ 25.50 groceries bought at the far side of town',
  '```dart',
  'final answer = compute(alpha, bravo, charlie, delta);',
  '```',
  'see [the docs](https://example.com/a/very/long/path) for more',
  'visit https://example.com/a/very/long/path/that/never/ends now',
  'this **bold run must not be split** across a width boundary',
  'trailing spaces here                                   ',
  'a `long inline code run that should stay whole` and more text',
  'short',
  'mixed 12345 67890 abcde fghij klmno pqrst uvwxy zabcd efghi',
  '- [ ] squat 5x5 @100kg and then some more text to force a break',
  '> quoted line long enough to need several width lines of space',
  '| a | b | c | d | e | f | g | h | i | j | k | l | m | n | o |',
  'x',
  'ends with a link [docs](https://example.com/end)',
];

const List<String> _corpusGolden = <String>[
  'row 0',
  'alpha',
  'bravo',
  'charlie',
  'delta echo',
  'foxtrot',
  'golf hotel',
  '',
  '## a heading long enough to need several width lines',
  r'$+ 25.50 groceries bought at the far side of town',
  '```dart',
  'final answer = compute(alpha, bravo, charlie, delta);',
  '```',
  'see',
  '[the docs](https://example.com/a/very/long/path)',
  'for more',
  'visit',
  'https://example.com/a/very/long/path/that/never/ends',
  'now',
  'this',
  '**bold run must not be split**',
  'across a',
  'width',
  'boundary',
  'trailing',
  'spaces',
  'here',
  'a',
  '`long inline code run that should stay whole`',
  'and more',
  'text',
  'short',
  'mixed',
  '12345',
  '67890',
  'abcde',
  'fghij',
  'klmno',
  'pqrst',
  'uvwxy',
  'zabcd',
  'efghi',
  '- [ ]',
  'squat 5x5',
  '@100kg and',
  'then some',
  'more text',
  'to force a',
  'break',
  '> quoted line long enough to need several width lines of space',
  '| a | b | c | d | e | f | g | h | i | j | k | l | m | n | o |',
  'x',
  'ends with',
  'a link',
  '[docs](https://example.com/end)',
];
