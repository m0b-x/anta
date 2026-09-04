@Tags(['benchmark'])
library;

import 'package:anta/constants/font_constants.dart';
import 'package:anta/utils/editor_width_calculator.dart';
import 'package:anta/utils/paste_line_breaker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Timings for the paste reformat pass on the shape the editor actually
/// meets: a large note, a 500-line paste in the middle of it, and a width
/// most pasted lines already fit.
///
/// **Tagged `benchmark` and excluded from the default run** (see
/// `dart_test.yaml`) because wall-clock numbers are not a pass/fail signal.
/// Run it deliberately when you want the numbers:
///
/// ```powershell
/// flutter test test/utils/paste_line_breaker_benchmark_test.dart --tags benchmark --run-skipped
/// ```
///
/// The assertions are catastrophe-only — they catch a re-introduced
/// whole-document rebuild, not a 30% regression. Read the printed table, and
/// especially the layout counts: they are what the ASCII pre-filter moves.
void main() {
  // The test font advances every glyph by the font size, so a "fits" line
  // here is one under `availableWidth / fontSize` characters.
  TestWidgetsFlutterBinding.ensureInitialized();

  const int documentLines = 10000;
  const int pasteStart = 5000;
  const int pasteLines = 500;
  const double fontSize = 16.0;
  const double availableWidth = 360.0;
  const int iterations = 20;

  EditorWidthCalculator newCalculator() => EditorWidthCalculator(
    config: EditorWidthConfig(
      editorContainerKey: GlobalKey(),
      fontSize: fontSize,
      fontFamily: FontConstants.editorFontFamily,
    ),
    editorPadding: EdgeInsets.zero,
  );

  String short(int i) => '- [ ] squat 5x5 @${100 + i % 40}kg';
  String long(int i) =>
      'alpha bravo charlie delta echo foxtrot golf hotel india $i';

  /// A [documentLines]-line note whose pasted range is [pasteStart] ..
  /// [pasteStart] + [pasteLines] - 1. `overLongEvery == 0` means the paste
  /// brought nothing that needs breaking.
  String buildText({required int overLongEvery}) {
    final lines = List<String>.generate(documentLines, (i) {
      if (i < pasteStart || i >= pasteStart + pasteLines) return short(i);
      final withinPaste = i - pasteStart;
      final overLong = overLongEvery > 0 && withinPaste % overLongEvery == 0;
      return overLong ? long(withinPaste) : short(i);
    });
    return lines.join('\n');
  }

  ({int best, int median, int layouts}) measure({
    required int overLongEvery,
    required bool expectReformat,
  }) {
    final text = buildText(overLongEvery: overLongEvery);
    final samples = <int>[];
    int layouts = 0;
    for (int i = 0; i < iterations; i++) {
      final controller = CodeLineEditingController.fromText(text);
      final calculator = newCalculator();
      final codeLines = controller.codeLines;
      final endIndex = pasteStart + pasteLines - 1;
      int pastedLength = codeLines[endIndex].text.length;
      for (int line = pasteStart; line < endIndex; line++) {
        pastedLength += codeLines[line].text.length + 1;
      }

      EditorWidthCalculator.debugLayoutCount = 0;
      final stopwatch = Stopwatch()..start();
      final result = PasteLineBreaker.run(
        controller: controller,
        calculator: calculator,
        availableWidth: availableWidth,
        pasteEnd: CodeLinePosition(
          index: endIndex,
          offset: codeLines[endIndex].text.length,
        ),
        pastedLength: pastedLength,
      );
      stopwatch.stop();
      layouts = EditorWidthCalculator.debugLayoutCount;

      expect(result.reformatted, expectReformat);
      samples.add(stopwatch.elapsedMicroseconds);
    }
    samples.sort();
    return (
      best: samples.first,
      median: samples[samples.length ~/ 2],
      layouts: layouts,
    );
  }

  test('paste of $pasteLines lines into a $documentLines-line note', () {
    final fits = measure(overLongEvery: 0, expectReformat: false);
    final breaks = measure(overLongEvery: 5, expectReformat: true);

    // ignore: avoid_print
    print(
      '\n=== PasteLineBreaker '
      '($documentLines lines, $pasteLines-line paste at $pasteStart, '
      '${availableWidth.toStringAsFixed(0)}px @ ${fontSize.toStringAsFixed(0)}pt) ===',
    );
    // ignore: avoid_print
    print(
      '  nothing to break  best ${fits.best.toString().padLeft(7)}us  '
      'median ${fits.median.toString().padLeft(7)}us  '
      'layouts ${fits.layouts.toString().padLeft(5)}',
    );
    // ignore: avoid_print
    print(
      '  20% over-long     best ${breaks.best.toString().padLeft(7)}us  '
      'median ${breaks.median.toString().padLeft(7)}us  '
      'layouts ${breaks.layouts.toString().padLeft(5)}',
    );

    expect(fits.best, lessThan(5000000));
    expect(breaks.best, lessThan(5000000));
  });
}
