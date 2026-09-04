import 'package:re_editor/re_editor.dart';

import '../utils/editor_width_calculator.dart';
import '../utils/markdown_list_utils.dart';
import '../utils/paste_line_breaker.dart';

/// What the tracker needs to reformat a paste: the calculator configured
/// for the editor's current font, and the text width it measured off the
/// live widget tree. The host returns null when the editor is not laid out
/// yet — nothing can be measured, so nothing is broken.
typedef PasteReformatContext = ({
  EditorWidthCalculator calculator,
  double availableWidth,
});

/// Watches the editor's text length and turns each growth into the one
/// edit it implies: a paste wide enough to need reflowing, or an Enter on
/// a list line that should continue (or end) the list.
///
/// Both of those write [CodeLineEditingController.value] **directly**
/// rather than through `runRevocableOp`, which overwrites the undo node
/// the user's own keystroke just pushed — so paste + reflow, and Enter +
/// continuation, are each a single undo step. That is only safe while the
/// tracker cannot re-enter itself: every path that edits the document from
/// code raises [isProcessing] first, and a controller notification arriving
/// under that guard is ignored.
///
/// Programmatic inserts from elsewhere in the page (toolbar shortcuts,
/// vocabulary completions, counter values) go through [runGuarded] for the
/// same reason, and must resync the length afterwards or the next keystroke
/// diffs against a stale count and looks like a paste.
class EditorEditTracker {
  EditorEditTracker({
    required CodeLineEditingController controller,
    required bool Function() autoBreakLongLines,
    required PasteReformatContext? Function() pasteContext,
    required void Function(int linesModified) onLinesReformatted,
  }) : _controller = controller,
       _autoBreakLongLines = autoBreakLongLines,
       _pasteContext = pasteContext,
       _onLinesReformatted = onLinesReformatted;

  /// Growth beyond this many code units in one notification is a paste, not
  /// typing. Deliberately low: a fast typist never lands 20 characters in
  /// one controller notification, and a short paste that is misread as
  /// typing simply skips a reflow nobody asked for.
  static const int pasteThreshold = 20;

  final CodeLineEditingController _controller;
  final bool Function() _autoBreakLongLines;
  final PasteReformatContext? Function() _pasteContext;
  final void Function(int linesModified) _onLinesReformatted;

  int _previousTextLength = 0;
  bool _isProcessing = false;

  /// The length the last observed edit left behind — the baseline the next
  /// notification diffs against.
  int get previousTextLength => _previousTextLength;

  /// True while the tracker (or a [runGuarded] caller) is editing the
  /// document itself.
  bool get isProcessing => _isProcessing;

  /// Adopts the controller's current length as the baseline. Called after
  /// the note's content lands, and after every programmatic edit.
  void syncLength() {
    _previousTextLength = _controller.textLength;
  }

  /// Runs [op] with the re-entrancy guard raised, then resyncs the length.
  ///
  /// Every programmatic edit needs both halves: without the guard, the
  /// notification `op` fires synchronously would be diffed as a paste and
  /// reformatted mid-operation with stale offsets; without the resync, the
  /// next keystroke would be.
  void runGuarded(void Function() op) {
    _isProcessing = true;
    try {
      op();
    } finally {
      _isProcessing = false;
      syncLength();
    }
  }

  /// The controller reported a change. Reflows a paste, continues a list,
  /// or does nothing.
  void onTextChanged() {
    if (_isProcessing) return;

    final selection = _controller.selection;
    final currentTextLength = _controller.textLength;
    final textLengthDiff = currentTextLength - _previousTextLength;
    _previousTextLength = currentTextLength;

    if (textLengthDiff <= 0) return;

    if (textLengthDiff > pasteThreshold) {
      _reformat(pasteEnd: selection.extent, pastedLength: textLengthDiff);
      return;
    }

    // After Enter, the caret sits on the freshly split line just past the
    // whitespace re_editor copied down from the line above — column 0 for
    // a top-level line, column N for one indented by N. That line above is
    // the one whose list marker, if any, should carry over.
    final currentLineIndex = selection.baseIndex;
    if (currentLineIndex <= 0) return;

    final prevLineIndex = currentLineIndex - 1;
    final prevLine = _controller.codeLines[prevLineIndex].text;
    final currentLine = _controller.codeLines[currentLineIndex];
    final autoIndent = _autoIndentLength(prevLine);

    // The caret has to sit exactly where the split parked it, and the line
    // has to actually start with the whitespace that was copied. Without
    // the second half, a caret that merely happens to rest at column N of
    // an unrelated line below a list item would grow a marker.
    if (selection.baseOffset != autoIndent) return;
    if (currentLine.text.length < autoIndent) return;
    if (currentLine.text.substring(0, autoIndent) !=
        prevLine.substring(0, autoIndent)) {
      return;
    }

    _isProcessing = true;
    try {
      if (MarkdownListUtils.isEmptyListItem(prevLine)) {
        // Enter on an item with no content ends the list: the marker line
        // goes, and the copied indentation goes with it, so a nested item
        // ends the same way a top-level one does — on a bare line with the
        // caret at column 0.
        final CodeLines dedented = autoIndent == 0
            ? _controller.codeLines
            : _controller.codeLines.replaceLine(
                currentLineIndex,
                currentLine.copyWith(
                  text: currentLine.text.substring(autoIndent),
                ),
              );
        _controller.value = CodeLineEditingValue(
          codeLines: dedented.removeLine(prevLineIndex),
          selection: CodeLineSelection.collapsed(
            index: prevLineIndex,
            offset: 0,
          ),
        );
        _previousTextLength = _controller.textLength;
        return;
      }

      final listPrefix = MarkdownListUtils.getListPrefix(prevLine);
      if (listPrefix == null) return;

      // The prefix carries the item's own indentation, so the copy the
      // split already made has to come off or a nested item indents twice.
      _controller.value = CodeLineEditingValue(
        codeLines: _controller.codeLines.replaceLine(
          currentLineIndex,
          currentLine.copyWith(
            text: '$listPrefix${currentLine.text.substring(autoIndent)}',
          ),
        ),
        selection: CodeLineSelection.collapsed(
          index: currentLineIndex,
          offset: listPrefix.length,
        ),
      );
      _previousTextLength = _controller.textLength;
    } finally {
      _isProcessing = false;
    }
  }

  /// How many leading code units re_editor's `applyNewLine` copies from
  /// [line] onto the line it creates.
  ///
  /// Deliberately **not** `MarkdownListUtils.leadingWhitespace`: the
  /// question here is not what markdown reads as this line's indent (which
  /// includes tabs) but what the fork actually copied, and its auto-indent
  /// counts spaces alone. A tab-indented list line therefore answers 0 —
  /// nothing was copied — and the continuation still lands at the right
  /// depth, because the prefix from `getListPrefix` carries the tab itself.
  static int _autoIndentLength(String line) {
    int index = 0;
    while (index < line.length && line.codeUnitAt(index) == _spaceCodeUnit) {
      index++;
    }
    return index;
  }

  static const int _spaceCodeUnit = 0x20;

  /// Reflows the text a programmatic insert just added, given the length
  /// the document had before it. Used by the toolbar shortcuts, whose edits
  /// run under [runGuarded] and so never reach [onTextChanged].
  void reformatInserted({required int beforeLength}) {
    final diff = _controller.textLength - beforeLength;
    if (diff <= 0) return;
    _reformat(pasteEnd: _controller.selection.extent, pastedLength: diff);
  }

  void _reformat({
    required CodeLinePosition pasteEnd,
    required int pastedLength,
  }) {
    if (!_autoBreakLongLines()) return;
    final context = _pasteContext();
    if (context == null) return;

    _isProcessing = true;
    try {
      final result = PasteLineBreaker.run(
        controller: _controller,
        calculator: context.calculator,
        availableWidth: context.availableWidth,
        pasteEnd: pasteEnd,
        pastedLength: pastedLength,
      );
      if (result.reformatted) {
        _previousTextLength = _controller.textLength;
        _onLinesReformatted(result.linesModified);
      }
    } finally {
      _isProcessing = false;
    }
  }
}
