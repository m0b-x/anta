import 'package:re_editor/re_editor.dart';

import 'markdown_callout_syntax.dart';
import 'markdown_list_utils.dart';

/// Which line a horizontal swipe on the live editor may nest (D2 of the
/// list-nesting record): one input per level on a phone, the idiom of
/// Apple Notes and Craft.
class LineSwipePolicy {
  LineSwipePolicy._();

  /// Whether a swipe that went down on [lineIndex] indents or outdents it.
  ///
  /// Only the focused editor's caret line reacts — a collapsed caret or a
  /// selection within that one line — so a diagonal flick while scrolling
  /// never nests a line the user was not editing. The line must be a list
  /// item, plain or inside a quote, and outside a code fence, where list
  /// syntax is inert and the tap path passes through for the same reason.
  static bool accepts({
    required bool hasFocus,
    required CodeLineSelection selection,
    required int lineIndex,
    required String? lineText,
    bool Function(int lineIndex)? isFenceLine,
  }) {
    if (!hasFocus || !selection.isSameLine) return false;
    if (lineIndex != selection.extentIndex || lineText == null) return false;
    if (!MarkdownListUtils.isListLine(lineText) &&
        MarkdownCalloutSyntax.quotedListItem(lineText) == null) {
      return false;
    }
    return !(isFenceLine?.call(lineIndex) ?? false);
  }
}
