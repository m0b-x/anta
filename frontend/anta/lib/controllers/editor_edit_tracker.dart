import 'package:re_editor/re_editor.dart';

import '../utils/editor_width_calculator.dart';
import '../utils/markdown_list_utils.dart';
import '../utils/paste_line_breaker.dart';

/// What the tracker needs to reformat a paste: the calculator configured
/// for the editor's current font, and the text width it measured off the
/// live widget tree. The host returns null when the editor is not laid out
/// yet — nothing can be measured, so nothing is broken.
///
/// The fence predicate is deliberately *not* here: it is a property of the
/// document's line index rather than of the widget tree's geometry, so it
/// is passed once to [EditorEditTracker.new] instead of rebuilt per paste.
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
    bool Function(int lineIndex)? isFenceLine,
    bool Function(int lineIndex)? lineInFenceBody,
  }) : _controller = controller,
       _autoBreakLongLines = autoBreakLongLines,
       _pasteContext = pasteContext,
       _onLinesReformatted = onLinesReformatted,
       _isFenceLine = isFenceLine,
       _lineInFenceBody = lineInFenceBody;

  /// Growth beyond this many code units in one notification is a paste, not
  /// typing. Deliberately low: a fast typist never lands 20 characters in
  /// one controller notification, and a short paste that is misread as
  /// typing simply skips a reflow nobody asked for.
  static const int pasteThreshold = 20;

  final CodeLineEditingController _controller;
  final bool Function() _autoBreakLongLines;
  final PasteReformatContext? Function() _pasteContext;
  final void Function(int linesModified) _onLinesReformatted;

  /// Whether the line at the given index is inside a ``` fence, or
  /// `null` when the host cannot tell. A fenced line is inert markdown,
  /// so Enter on `- foo` in a code block must not grow a marker.
  final bool Function(int lineIndex)? _isFenceLine;

  /// Whether the line at the given index sits **inside** a fence body
  /// (delimiters excluded), or `null` when the host cannot tell. Seeds
  /// the width breaker so a paste landing in the middle of a code block
  /// is not hard-wrapped — a different question from [_isFenceLine],
  /// which counts the delimiters as fenced too.
  final bool Function(int lineIndex)? _lineInFenceBody;

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
  ///
  /// The Enter shape is tested **before** the paste threshold, because the
  /// two overlap: an item indented by [pasteThreshold] spaces or more
  /// grows the document past the threshold on a plain Enter, and reflowing
  /// it instead would swallow the continuation.
  ///
  /// The growth it diffs is a **net** length change, which bounds what it
  /// can know. A paste that replaced a selection reports fewer code units
  /// than it inserted, so [_reformat]'s range starts no earlier than the
  /// true one (the safe direction: the reflow can under-cover a paste, but
  /// never rewrite lines the paste did not touch); a paste that shrank the
  /// document reports no growth at all and is never reflowed; and a paste
  /// of exactly a line break plus the previous line's indentation is
  /// indistinguishable from an Enter and is deliberately read as one.
  void onTextChanged() {
    if (_isProcessing) return;

    final selection = _controller.selection;
    final currentTextLength = _controller.textLength;
    final textLengthDiff = currentTextLength - _previousTextLength;
    _previousTextLength = currentTextLength;

    if (textLengthDiff <= 0) return;

    // Undo and redo restore text the user already had; growth from a
    // restore is neither a paste to reflow (that would rewrite the restored
    // lines and, writing the value directly, drop the redo chain) nor an
    // Enter to continue.
    if (_controller.isRestoringHistory) return;

    if (_handleNewLine(selection, textLengthDiff)) return;

    if (textLengthDiff > pasteThreshold) {
      _reformat(pasteEnd: selection.extent, pastedLength: textLengthDiff);
    }
  }

  /// Whether [textLengthDiff] is the growth of an Enter the tracker owns —
  /// in which case the list continuation (or termination) has already been
  /// applied and the paste branch must not run.
  bool _handleNewLine(CodeLineSelection selection, int textLengthDiff) {
    // After Enter, the caret sits on the freshly split line just past the
    // whitespace re_editor copied down from the line above — column 0 for
    // a top-level line, column N for one indented by N. That line above is
    // the one whose list marker, if any, should carry over.
    final currentLineIndex = selection.baseIndex;
    if (currentLineIndex <= 0) return false;

    final prevLineIndex = currentLineIndex - 1;
    // A fenced line is inert markdown on both rendering surfaces, so a
    // `- foo` inside a code block must not grow a marker either.
    if (_isFenceLine?.call(prevLineIndex) ?? false) return false;
    final prevLine = _controller.codeLines[prevLineIndex].text;
    final currentLine = _controller.codeLines[currentLineIndex];
    final autoIndent = _autoIndentLength(prevLine);

    // An Enter grows the document by exactly the line break plus the
    // indentation `applyNewLine` copied down — nothing else does. The
    // caret checks below cannot tell an Enter from a Tab indent or a typed
    // space that happens to park the caret at the indent column, so the
    // growth is the discriminator.
    if (textLengthDiff != 1 + autoIndent) return false;

    // The caret has to sit exactly where the split parked it, and the line
    // has to actually start with the whitespace that was copied. Without
    // the second half, a caret that merely happens to rest at column N of
    // an unrelated line below a list item would grow a marker.
    if (selection.baseOffset != autoIndent) return false;
    if (currentLine.text.length < autoIndent) return false;
    if (currentLine.text.substring(0, autoIndent) !=
        prevLine.substring(0, autoIndent)) {
      return false;
    }

    _isProcessing = true;
    try {
      // The empty-item test reads the split **prefix**, which is only the
      // whole item when the split left nothing behind: a caret parked just
      // right of the marker (`- item` at offset 2) makes that prefix `- `
      // too, and dropping the line there would delete the marker and merge
      // the remainder into the line above. Requiring an empty remainder as
      // well sends that split down the continuation branch instead.
      if (currentLine.text.length == autoIndent &&
          MarkdownListUtils.isEmptyListItem(prevLine)) {
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
        return true;
      }

      final listPrefix = MarkdownListUtils.getListPrefix(prevLine);
      // Still an Enter, just not on a list line: there is nothing to
      // continue, and nothing for the paste branch to reflow either.
      if (listPrefix == null) return true;

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
      return true;
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
        lineInFenceBody: _lineInFenceBody,
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
