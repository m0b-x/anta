import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import 'markdown_line_shape.dart';
import 'markdown_list_syntax.dart';
import 'marker_backspace_policy.dart';

/// Multi-line paste that continues the caret line's list.
///
/// Pasting a plain multi-line text (an exercise plan, a shopping list)
/// while the caret sits in a list item's content turns every pasted
/// line into a sibling item: tasks continue unchecked, bullets keep
/// their marker, ordered items keep numbering from the caret line.
/// Deliberately conservative — the transform leaves the paste untouched
/// when any of these hold, so it can never mangle a paste:
///   * the selection isn't collapsed, or the caret is inside the
///     marker (left of the item's content);
///   * the paste is single-line;
///   * any pasted line is already a list item, or any other line-led
///     construct — a money row, heading, quote/callout, fence, or
///     table row ([MarkdownLineShape]) — since the text brought its
///     own structure and a list marker in front would break it;
///   * from the first blank pasted line on, the remainder pastes raw
///     (a blank line ends a markdown list);
///   * the caret line is inside a ``` fence, where list syntax is inert.
///
/// The copy/paste toolbar and Ctrl+V reach [paste]; the keyboard's own
/// paste key arrives as a multi-line [edit] and is given the same
/// transform there.
///
/// Being the delegate every edit passes through, it is also where a
/// Backspace right after a list or quote marker takes the whole marker
/// ([MarkerBackspacePolicy]), from a hardware key and a soft keyboard
/// alike.
class ListAwarePasteController extends CodeLineEditingControllerDelegate {
  ListAwarePasteController({
    required super.delegate,
    bool Function(int lineIndex)? isFenceLine,
  }) : _isFenceLine = isFenceLine;

  /// Whether the line at the given index is inside a ``` fence, or `null`
  /// when the host keeps no fence index. A `- foo` in a code block is
  /// inert markdown on both rendering surfaces, so a paste under it must
  /// not grow list markers either.
  final bool Function(int lineIndex)? _isFenceLine;

  @override
  void deleteBackward() {
    if (!_applyMarkerBackspace()) super.deleteBackward();
  }

  /// A soft keyboard's Backspace arrives here as a rewrite of the caret
  /// line, never as [deleteBackward], so the marker rule is applied to
  /// that shape too; any other single-unit Backspace goes on to the fork,
  /// which runs its own Backspace rules for it.
  ///
  /// A multi-line commit is the keyboard's own paste key (Gboard's
  /// clipboard strip): it gets the same list continuation as [paste], cut
  /// out of the commit exactly as the editor cuts it ([imeReplacement]),
  /// as one undo step. Anything the transform leaves alone goes to the
  /// fork unchanged.
  @override
  void edit(TextEditingValue newValue) {
    if (isSingleBackspace(newValue) && _applyMarkerBackspace()) return;
    if (newValue.text.contains('\n') && _applyImePaste(newValue.text)) return;
    super.edit(newValue);
  }

  bool _applyImePaste(String committed) {
    final pasted = imeReplacement(committed);
    final transformed = _transformAtCaret(pasted);
    if (transformed == pasted) return false;
    replaceSelection(transformed);
    return true;
  }

  /// [pasted] through [ListAwarePaste.transform] against the caret line.
  String _transformAtCaret(String pasted) {
    final sel = selection;
    final inRange = sel.extentIndex >= 0 && sel.extentIndex < codeLines.length;
    final caretLine = inRange ? codeLines[sel.extentIndex].text : '';
    final fenced = inRange && (_isFenceLine?.call(sel.extentIndex) ?? false);
    return ListAwarePaste.transform(
      caretLine: caretLine,
      caretOffset: sel.extentOffset,
      collapsed: sel.isCollapsed,
      pasted: pasted,
      inFence: fenced,
    );
  }

  /// Applies [MarkerBackspacePolicy] to the collapsed caret's line as one
  /// undo step, or returns false to leave the Backspace to the editor. A
  /// fenced line is inert markdown, so its `- ` is plain text there.
  bool _applyMarkerBackspace() {
    final sel = selection;
    if (!sel.isCollapsed) return false;
    final index = sel.extentIndex;
    final lines = codeLines;
    if (index < 0 || index >= lines.length) return false;
    if (_isFenceLine?.call(index) ?? false) return false;
    final line = lines[index];
    final result = MarkerBackspacePolicy.apply(line.text, sel.extentOffset);
    if (result == null) return false;
    runRevocableOp(() {
      value = CodeLineEditingValue(
        codeLines: lines.replaceLine(index, line.copyWith(text: result.line)),
        selection: CodeLineSelection.collapsed(
          index: index,
          offset: result.caretOffset,
        ),
      );
    });
    makeCursorCenterIfInvisible();
    return true;
  }

  @override
  void paste() {
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      final text = data?.text;
      if (text == null || text.isEmpty) return;
      replaceSelection(_transformAtCaret(text));
    });
  }
}

/// The pure transform behind [ListAwarePasteController], separated so
/// the paste policy has no controller dependencies.
class ListAwarePaste {
  ListAwarePaste._();

  /// [pasted] with its line breaks normalised to `\n` and, when the caret
  /// sits in a list item's content, every pasted line turned into a
  /// sibling item. [inFence] is the one bail-out the line text cannot
  /// show: inside a ``` fence a `- foo` line is inert, so nothing is
  /// prefixed and only the normalisation applies.
  static String transform({
    required String caretLine,
    required int caretOffset,
    required bool collapsed,
    required String pasted,
    bool inFence = false,
  }) {
    final normalized = pasted.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (inFence) return normalized;
    if (!collapsed || !normalized.contains('\n')) return normalized;
    final item = MarkdownListSyntax.parse(caretLine);
    if (item == null || caretOffset < item.contentStart) return normalized;

    // One trailing line break is the copy's own end of line (a list copied
    // whole ends with one), not a blank line: kept after the last item, it
    // would leave the caret on a bare unmarked line under the new items.
    // After a tail pasted as written (past a blank line) it is put back.
    final trailingBreak = normalized.endsWith('\n');
    final body = trailingBreak
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final lines = body.split('\n');
    var hasContinuation = false;
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) break;
      // A rule past a lead only `trim` strips (a no-break space) is prose
      // on screen, but prefixed with its lead stripped it would become
      // `- ---`, a rule.
      if (MarkdownListSyntax.isListLine(line) ||
          MarkdownLineShape.isLineLedConstruct(line) ||
          MarkdownLineShape.isHorizontalRule(line.trimLeft())) {
        return normalized;
      }
      hasContinuation = true;
    }
    if (!hasContinuation) return normalized;

    final out = StringBuffer(lines.first);
    var ordinal = item.kind == MarkdownListKind.ordered
        ? (int.tryParse(item.marker) ?? 1)
        : 0;
    var stopped = false;
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      out.write('\n');
      if (stopped || line.trim().isEmpty) {
        stopped = true;
        out.write(line);
        continue;
      }
      switch (item.kind) {
        case MarkdownListKind.task:
          out.write('${item.indent}${item.marker} [ ] ');
        case MarkdownListKind.bullet:
          out.write('${item.indent}${item.marker} ');
        case MarkdownListKind.ordered:
          ordinal++;
          out.write('${item.indent}$ordinal${item.delimiter} ');
      }
      out.write(line.trimLeft());
    }
    if (stopped && trailingBreak) out.write('\n');
    return out.toString();
  }
}
