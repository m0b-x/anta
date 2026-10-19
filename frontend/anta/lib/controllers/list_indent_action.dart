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
  /// Anything that is not a single list line — a multi-line selection, a
  /// plain line, a line [isFenceLine] reports inside a code fence — falls
  /// back to the fork's own `applyIndent` / `applyOutdent`, so the button
  /// and Tab never disagree on a line. An outdent already at column 0
  /// changes nothing.
  static void apply(
    CodeLineEditingController controller, {
    required bool outdent,
    bool Function(int lineIndex)? isFenceLine,
  }) {
    if (_tryListIndent(
      controller,
      outdent: outdent,
      isFenceLine: isFenceLine,
    )) {
      return;
    }
    if (outdent) {
      controller.applyOutdent();
    } else {
      controller.applyIndent();
    }
  }

  static bool _tryListIndent(
    CodeLineEditingController controller, {
    required bool outdent,
    required bool Function(int lineIndex)? isFenceLine,
  }) {
    final selection = controller.selection;
    if (!selection.isSameLine) return false;
    final lineIndex = selection.extentIndex;
    final lines = controller.codeLines;
    if (lineIndex < 0 || lineIndex >= lines.length) return false;
    // A fenced line is inert markdown — the tap path passes it through
    // for the same reason, so Tab there is the fork's plain indent.
    if (isFenceLine?.call(lineIndex) ?? false) return false;
    final indent = EditorInputPolicy.listIndent(
      lineText: lines[lineIndex].text,
      outdent: outdent,
    );
    if (indent == null) return false;
    if (indent.delta == 0) return true;

    final newText = indent.text;
    final baseOffset = (selection.baseOffset + indent.delta).clamp(
      0,
      newText.length,
    );
    final extentOffset = (selection.extentOffset + indent.delta).clamp(
      0,
      newText.length,
    );

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
