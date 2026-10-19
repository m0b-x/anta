import 'package:equatable/equatable.dart';

import 'editor_input_policy.dart';
import 'markdown_callout_syntax.dart';
import 'markdown_list_syntax.dart';

/// The caret line after a marker Backspace: its new [line] text and the
/// collapsed caret's new [caretOffset] on it.
class MarkerBackspaceResult extends Equatable {
  const MarkerBackspaceResult(this.line, this.caretOffset);

  final String line;
  final int caretOffset;

  @override
  List<Object?> get props => [line, caretOffset];
}

/// Backspace with the caret parked right after a line's leading marker
/// takes the marker away in one keystroke, the way every markdown editor
/// does, instead of eating `- [ ] ` one character at a time and passing
/// through shapes that mean something else (`- [ ` is a bullet whose text
/// is `[ `).
///
/// Pure: it reads the line and the caret only, so the controller that
/// applies it (`ListAwarePasteController`) stays an adapter and every rule
/// is pinned by a table test.
class MarkerBackspacePolicy {
  MarkerBackspacePolicy._();

  /// What a Backspace at [caretOffset] does to [line], or `null` when the
  /// caret is not exactly at a list item's or a quote's content start and
  /// the editor's own Backspace applies.
  ///
  /// A nested list item outdents one level first (the same step as
  /// Shift-Tab, [EditorInputPolicy.listIndent]), so deleting a marker
  /// never jumps more than one level; a top-level item becomes its bare
  /// content with the caret at its start. A quote loses its innermost `>`
  /// only, so `> > a` becomes `> a` and a nested quote unwinds one level
  /// per keystroke.
  ///
  /// Content may follow the caret: Backspace at the start of `- item`
  /// leaves `item`, which is what merging the item into plain text means.
  ///
  /// A list item inside a quote (`> - a`) follows the list rule with the
  /// quote run kept, as Enter continues it
  /// (`MarkdownListUtils.continuationPrefix`): `> - |a` becomes `> |a`.
  static MarkerBackspaceResult? apply(String line, int caretOffset) {
    final MarkdownListItem? item = MarkdownListSyntax.parse(line);
    if (item != null) return _applyToItem(line, item, caretOffset);

    final MarkdownQuoteShape? quote = MarkdownCalloutSyntax.quoteMarkers(line);
    if (quote == null) return null;
    if (caretOffset == quote.contentStart) {
      final int innermost = quote.markerOffsets.last;
      return MarkerBackspaceResult(
        line.substring(0, innermost) + line.substring(quote.contentStart),
        innermost,
      );
    }
    final String rest = line.substring(quote.contentStart);
    final MarkdownListItem? quoted = MarkdownListSyntax.parse(rest);
    if (quoted == null) return null;
    final MarkerBackspaceResult? inner = _applyToItem(
      rest,
      quoted,
      caretOffset - quote.contentStart,
    );
    if (inner == null) return null;
    return MarkerBackspaceResult(
      line.substring(0, quote.contentStart) + inner.line,
      quote.contentStart + inner.caretOffset,
    );
  }

  static MarkerBackspaceResult? _applyToItem(
    String line,
    MarkdownListItem item,
    int caretOffset,
  ) {
    if (caretOffset != item.contentStart) return null;
    if (item.indent.isNotEmpty) {
      final EditorListIndent? outdent = EditorInputPolicy.listIndent(
        lineText: line,
        outdent: true,
      );
      if (outdent != null && outdent.delta != 0) {
        return MarkerBackspaceResult(outdent.text, caretOffset + outdent.delta);
      }
    }
    // Whatever indent the outdent could not take (none at top level)
    // stays, so only the marker itself goes.
    return MarkerBackspaceResult(
      item.indent + item.content,
      item.indent.length,
    );
  }
}
