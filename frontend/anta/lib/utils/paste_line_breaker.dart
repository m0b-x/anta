import 'package:re_editor/re_editor.dart';

import 'editor_width_calculator.dart';

/// Translates a line index into a flat character offset in a
/// [CodeLineEditingController]'s text. O(lines), so it belongs to the
/// developer overlay only — nothing on the typing or paste path joins the
/// document into a flat string any more.
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
/// The pasted range is found in **line coordinates** — never by joining
/// the document into a flat string — and only that range is rebuilt: the
/// splice is `sublines` + `add` + `addFrom`, the same shape the fork's own
/// `_replaceRange` uses, so every segment outside the range keeps its
/// backing-list identity and the editor's incremental line index reads it
/// as "nothing to re-render here".
///
/// When the reformat changes the text, the new value is written
/// **directly** to [CodeLineEditingController.value] (bypassing
/// `runRevocableOp`) so the reformat overwrites the paste's undo node —
/// making paste + line-breaking a single undo entry.
class PasteLineBreaker {
  PasteLineBreaker._();

  /// Break the lines the paste landed on down to [availableWidth].
  ///
  /// [availableWidth] is measured by the caller (the page owns the editor's
  /// render objects); the guard below only re-states the caller's contract.
  /// [pasteEnd] is `controller.selection.extent` immediately after the
  /// paste and [pastedLength] the number of code units it added, so the
  /// pasted range is recovered by walking back over line lengths from the
  /// caret — the only two facts the caller can supply without measuring the
  /// document.
  ///
  /// Returns [PasteLineBreakerResult.empty] with the controller untouched
  /// when nothing in the range needs breaking; otherwise the caret lands at
  /// the end of the reformatted block.
  static PasteLineBreakerResult run({
    required CodeLineEditingController controller,
    required EditorWidthCalculator calculator,
    required double availableWidth,
    required CodeLinePosition pasteEnd,
    required int pastedLength,
  }) {
    if (availableWidth <= 0) return PasteLineBreakerResult.empty;

    final codeLines = controller.codeLines;
    final lineCount = codeLines.length;
    if (lineCount == 0) return PasteLineBreakerResult.empty;

    final int end = pasteEnd.index.clamp(0, lineCount - 1);
    final int start = _startLine(
      codeLines: codeLines,
      end: end,
      caretOffset: pasteEnd.offset,
      pastedLength: pastedLength,
    );

    assert(
      _noChunkParents(codeLines, start, end),
      'PasteLineBreaker would rebuild a collapsed chunk parent as a plain '
      'line and drop its children; a paste must never land on one',
    );

    final lines = <String>[];
    for (int i = start; i <= end; i++) {
      lines.add(codeLines[i].text);
    }

    final result = calculator.breakLinesSmartly(lines, availableWidth);
    if (result.linesModified == 0) return PasteLineBreakerResult.empty;

    final next = codeLines.sublines(0, start);
    for (final line in result.lines) {
      next.add(CodeLine(line));
    }
    if (end + 1 < lineCount) {
      next.addFrom(codeLines, end + 1);
    }

    controller.value = CodeLineEditingValue(
      codeLines: next,
      selection: CodeLineSelection.collapsed(
        index: start + result.lines.length - 1,
        offset: result.lines.last.length,
      ),
    );

    return PasteLineBreakerResult(
      reformatted: true,
      linesModified: result.linesModified,
    );
  }

  /// First line the paste touched, walking back from the caret line over
  /// `text.length + 1` (the line and the newline that follows it) until the
  /// pasted code units are accounted for.
  ///
  /// A single-line paste consumes fewer units than the caret column, so the
  /// loop never runs and the range is the caret line alone.
  static int _startLine({
    required CodeLines codeLines,
    required int end,
    required int caretOffset,
    required int pastedLength,
  }) {
    int start = end;
    int remaining = pastedLength - caretOffset;
    while (remaining > 0 && start > 0) {
      start--;
      remaining -= 1 + codeLines[start].text.length;
    }
    return start;
  }

  /// Whether `[start, end]` is free of collapsed-chunk parents.
  ///
  /// Debug-only: today the editor collapses nothing, but once folding lands
  /// (roadmap Session 11) a parent line carries its hidden children in
  /// [CodeLine.chunks], and the splice below re-creates every line in the
  /// range as a plain [CodeLine] — silently deleting them.
  static bool _noChunkParents(CodeLines codeLines, int start, int end) {
    for (int i = start; i <= end; i++) {
      if (codeLines[i].chunkParent) return false;
    }
    return true;
  }
}
