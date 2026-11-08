import 'package:re_editor/re_editor.dart';

import '../utils/editor_input_policy.dart';

/// Tab / Shift-Tab on the live editor, callable without a hardware key: the
/// markdown bar's indent and outdent buttons run the same edit a keyboard
/// Tab does, because a soft keyboard has no Tab key.
class ListIndentAction {
  ListIndentAction._();

  /// Indents (or, with [outdent], outdents) the caret's list line by one
  /// grid step of [EditorInputPolicy.listIndent], keeping the caret on the
  /// same content character, as one undo node.
  ///
  /// A quoted item (`> - a`) nests after its `>` run, which stays put.
  ///
  /// Anything that is not a single list line — a multi-line selection, a
  /// plain line, a line [isFenceLine] reports inside a code fence — falls
  /// back to the fork's own `applyIndent` / `applyOutdent`, so the button
  /// and Tab never disagree on a line. An outdent already at column 0
  /// changes nothing, and so does an indent past the nesting cap
  /// ([EditorInputPolicy.listIndentCap]).
  static void apply(
    CodeLineEditingController controller, {
    required bool outdent,
    bool Function(int lineIndex)? isFenceLine,
  }) {
    if (_listIndent(controller, outdent: outdent, isFenceLine: isFenceLine) !=
        null) {
      return;
    }
    if (outdent) {
      controller.applyOutdent();
    } else {
      controller.applyIndent();
    }
  }

  /// [apply]'s single-list-line path alone: never the fork's indent, so a
  /// caller that is not a keyboard (the line swipe) cannot pad spaces at
  /// the caret. Returns whether the line's text changed — false on
  /// anything [apply] would hand to the fork, and on a list line the cap
  /// or column 0 leaves as it is — which is what decides a haptic.
  static bool tryApply(
    CodeLineEditingController controller, {
    required bool outdent,
    bool Function(int lineIndex)? isFenceLine,
  }) =>
      _listIndent(controller, outdent: outdent, isFenceLine: isFenceLine) ??
      false;

  /// Null when the selection is not on a single unfenced list line; else
  /// whether the step changed the line.
  static bool? _listIndent(
    CodeLineEditingController controller, {
    required bool outdent,
    required bool Function(int lineIndex)? isFenceLine,
  }) {
    final selection = controller.selection;
    if (!selection.isSameLine) return null;
    final lineIndex = selection.extentIndex;
    final lines = controller.codeLines;
    if (lineIndex < 0 || lineIndex >= lines.length) return null;
    // A fenced line is inert markdown — the tap path passes it through
    // for the same reason, so Tab there is the fork's plain indent.
    if (isFenceLine?.call(lineIndex) ?? false) return null;
    final lineText = lines[lineIndex].text;
    final uncapped = EditorInputPolicy.listIndent(
      lineText: lineText,
      outdent: outdent,
    );
    if (uncapped == null) return null;
    // The cap scans upward through the document, so it is paid only once
    // the line is known to be a list item, and only for an indent.
    final indent = outdent
        ? uncapped
        : EditorInputPolicy.listIndent(
            lineText: lineText,
            outdent: false,
            maxLevel: EditorInputPolicy.listIndentCap(
              lineAt: (index) => lines[index].text,
              index: lineIndex,
              isFenceLine: isFenceLine,
            ),
          )!;
    if (indent.delta == 0) return false;

    final newText = indent.text;
    // An offset in a quote's `>` run stays; one in the item moves with it,
    // clamped to the item's start when an outdent takes the indent it sat in.
    int shifted(int offset) => offset < indent.start
        ? offset
        : (offset + indent.delta).clamp(indent.start, newText.length);
    final baseOffset = shifted(selection.baseOffset);
    final extentOffset = shifted(selection.extentOffset);

    controller.runRevocableOp(() {
      controller.value = CodeLineEditingValue(
        codeLines: lines.replaceLine(
          lineIndex,
          lines[lineIndex].copyWith(text: newText),
        ),
        selection: CodeLineSelection(
          baseIndex: lineIndex,
          baseOffset: baseOffset,
          extentIndex: lineIndex,
          extentOffset: extentOffset,
        ),
      );
    });
    return true;
  }
}
