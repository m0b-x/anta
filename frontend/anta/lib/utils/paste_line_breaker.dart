import 'package:re_editor/re_editor.dart';

import 'editor_width_calculator.dart';
import 'text_position_utils.dart';

/// Utilities for translating between line/column positions and
/// flat character offsets in a [CodeLineEditingController].
class CodeLineOffsetUtils {
  CodeLineOffsetUtils._();

  /// Character offset of the first character of [lineIndex].
  static int lineStartOffset(
    CodeLineEditingController controller,
    int lineIndex,
  ) {
    int offset = 0;
    final codeLines = controller.codeLines;
    for (int i = 0; i < lineIndex && i < codeLines.length; i++) {
      offset += codeLines[i].text.length + 1;
    }
    return offset;
  }

  /// Convert a [CodeLinePosition] to a character offset in the full text.
  static int offsetFromPosition(
    CodeLineEditingController controller,
    CodeLinePosition position,
  ) {
    int offset = 0;
    final codeLines = controller.codeLines;
    final lineIndex = position.index.clamp(0, codeLines.length - 1);

    for (int i = 0; i < lineIndex; i++) {
      offset += codeLines[i].text.length + 1;
    }

    if (lineIndex < codeLines.length) {
      final lineLength = codeLines[lineIndex].text.length;
      offset += position.offset.clamp(0, lineLength);
    }

    return offset;
  }
}

/// Result of a paste reformat pass.
class PasteLineBreakerResult {
  final bool reformatted;
  final int linesModified;

  const PasteLineBreakerResult({
    required this.reformatted,
    required this.linesModified,
  });

  static const empty = PasteLineBreakerResult(
    reformatted: false,
    linesModified: 0,
  );
}

/// Reformats the lines covered by a paste range so they fit the
/// editor's available text width.
///
/// When the reformat changes the text, the new value is written
/// **directly** to [controller.value] (bypassing `runRevocableOp`)
/// so the reformat overwrites the paste's undo node — making
/// paste + line-breaking a single undo entry.
class PasteLineBreaker {
  PasteLineBreaker._();

  static PasteLineBreakerResult run({
    required CodeLineEditingController controller,
    required EditorWidthCalculator calculator,
    required int pasteStartOffset,
    required int pasteEndOffset,
  }) {
    final availableWidth = calculator.getAvailableTextWidth();
    if (availableWidth == null || availableWidth <= 0) {
      return PasteLineBreakerResult.empty;
    }

    final text = controller.text;
    final codeLines = controller.codeLines;
    final lineCount = codeLines.length;

    final startLine = TextPositionUtils.getLineFromOffset(
      text,
      pasteStartOffset,
    );
    final endLine = TextPositionUtils.getLineFromOffset(text, pasteEndOffset);

    final linesToProcess = <String>[];
    for (int i = startLine; i <= endLine && i < lineCount; i++) {
      linesToProcess.add(codeLines[i].text);
    }

    final result = calculator.breakLinesSmartly(linesToProcess, availableWidth);
    if (result.linesModified == 0) return PasteLineBreakerResult.empty;

    final beforePaste = <String>[];
    for (int i = 0; i < startLine; i++) {
      beforePaste.add(codeLines[i].text);
    }
    final afterPaste = <String>[];
    for (int i = endLine + 1; i < lineCount; i++) {
      afterPaste.add(codeLines[i].text);
    }

    final newText = [...beforePaste, ...result.lines, ...afterPaste].join('\n');

    if (newText == controller.text) return PasteLineBreakerResult.empty;

    final beforePasteLength =
        beforePaste.join('\n').length + (beforePaste.isNotEmpty ? 1 : 0);
    final formattedPasteLength = result.lines.join('\n').length;
    final newCursorOffset = beforePasteLength + formattedPasteLength;
    final newCursorLine = TextPositionUtils.getLineFromOffset(
      newText,
      newCursorOffset,
    );
    final newCursorCol = TextPositionUtils.getColumnFromOffset(
      newText,
      newCursorOffset,
    );

    controller.value = CodeLineEditingValue(
      codeLines: newText.codeLines,
      selection: CodeLineSelection.collapsed(
        index: newCursorLine,
        offset: newCursorCol,
      ),
    );

    return PasteLineBreakerResult(
      reformatted: true,
      linesModified: result.linesModified,
    );
  }
}
