import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import 'markdown_line_shape.dart';
import 'markdown_list_syntax.dart';

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
///     (a blank line ends a markdown list).
///
/// Only the copy/paste toolbar and Ctrl+V reach [paste]; text inserted
/// by the IME's own paste key arrives as a plain insertion and is left
/// alone by design.
class ListAwarePasteController extends CodeLineEditingControllerDelegate {
  ListAwarePasteController({required super.delegate});

  @override
  void paste() {
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      final text = data?.text;
      if (text == null || text.isEmpty) return;
      final sel = selection;
      final caretLine =
          sel.extentIndex >= 0 && sel.extentIndex < codeLines.length
          ? codeLines[sel.extentIndex].text
          : '';
      replaceSelection(
        ListAwarePaste.transform(
          caretLine: caretLine,
          caretOffset: sel.extentOffset,
          collapsed: sel.isCollapsed,
          pasted: text,
        ),
      );
    });
  }
}

/// The pure transform behind [ListAwarePasteController], separated so
/// the paste policy has no controller dependencies.
class ListAwarePaste {
  ListAwarePaste._();

  static String transform({
    required String caretLine,
    required int caretOffset,
    required bool collapsed,
    required String pasted,
  }) {
    final normalized = pasted.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (!collapsed || !normalized.contains('\n')) return normalized;
    final item = MarkdownListSyntax.parse(caretLine);
    if (item == null || caretOffset < item.contentStart) return normalized;

    final lines = normalized.split('\n');
    var hasContinuation = false;
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) break;
      if (MarkdownListSyntax.isListLine(line) ||
          MarkdownLineShape.isLineLedConstruct(line)) {
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
    return out.toString();
  }
}
