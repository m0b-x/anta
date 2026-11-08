import 'package:equatable/equatable.dart';

import 'editor_input_policy.dart';
import 'markdown_callout_syntax.dart';
import 'markdown_list_syntax.dart';

/// The caret line after a Space on an empty list item: its new [line]
/// text and the collapsed caret's new [caretOffset] on it. At the nesting
/// cap both are the ones the policy was given — the key is swallowed and
/// nothing changes.
class MarkerSpaceResult extends Equatable {
  const MarkerSpaceResult(this.line, this.caretOffset);

  final String line;
  final int caretOffset;

  @override
  List<Object?> get props => [line, caretOffset];
}

/// Space with the caret at an empty list item's content start (`- |`)
/// nests the item one level instead of typing a space, so a nested item
/// costs Enter, Space and the text on a phone keyboard that has no Tab.
///
/// Pure, as `MarkerBackspacePolicy` is: it reads the line, the caret and
/// the cap only, so the controller that applies it
/// (`ListAwarePasteController`) stays an adapter and every rule is pinned
/// by a table test.
class MarkerSpacePolicy {
  MarkerSpacePolicy._();

  /// What a Space at [caretOffset] does to [line], or `null` when the
  /// caret is not exactly at an empty list item's content start and the
  /// space is typed.
  ///
  /// The step is Tab's ([EditorInputPolicy.listIndent], the column grid),
  /// so Space and Tab land an item on the same column. [maxLevelOf] reads
  /// the nesting cap ([EditorInputPolicy.listIndentCap]): at it the line
  /// comes back unchanged and the caller swallows the key, so the item
  /// stays empty and the next Enter still ends the list. It is read only
  /// once the line is claimed, because the cap scans upward and a double
  /// space in prose must not pay for that scan. `null` leaves the indent
  /// unbounded.
  ///
  /// An ordered item restarts at `1` with its delimiter kept, since it
  /// opens a new sublist; a task keeps its box and a custom state its
  /// state. A quoted item (`> - |`) keeps its `>` run and nests after it,
  /// read as [MarkdownCalloutSyntax.quotedListItem] reads it.
  ///
  /// The content start must follow a blank: in `- [ ]` typed by hand it
  /// sits right after the `]`, and the space there is the one that
  /// separates the box from its text.
  static MarkerSpaceResult? apply(
    String line,
    int caretOffset, {
    int Function()? maxLevelOf,
  }) {
    final MarkdownListItem? item = MarkdownListSyntax.parse(line);
    if (item != null) {
      return _applyToItem(line, item, caretOffset, maxLevelOf);
    }

    final quoted = MarkdownCalloutSyntax.quotedListItem(line);
    if (quoted == null) return null;
    final int base = quoted.base;
    final MarkerSpaceResult? inner = _applyToItem(
      line.substring(base),
      quoted.item,
      caretOffset - base,
      maxLevelOf,
    );
    if (inner == null) return null;
    return MarkerSpaceResult(
      line.substring(0, base) + inner.line,
      base + inner.caretOffset,
    );
  }

  static MarkerSpaceResult? _applyToItem(
    String line,
    MarkdownListItem item,
    int caretOffset,
    int Function()? maxLevelOf,
  ) {
    if (caretOffset != item.contentStart || !item.isEmpty) return null;
    final int before = line.codeUnitAt(caretOffset - 1);
    if (before != 0x20 && before != 0x09) return null;
    final EditorListIndent? indent = EditorInputPolicy.listIndent(
      lineText: line,
      outdent: false,
      maxLevel: maxLevelOf?.call(),
    );
    if (indent == null) return null;
    if (indent.delta == 0) return MarkerSpaceResult(line, caretOffset);
    if (item.kind != MarkdownListKind.ordered) {
      return MarkerSpaceResult(indent.text, caretOffset + indent.delta);
    }
    final int numberStart = indent.delta + item.indent.length;
    return MarkerSpaceResult(
      '${indent.text.substring(0, numberStart)}1'
      '${indent.text.substring(numberStart + item.marker.length)}',
      caretOffset + indent.delta + 1 - item.marker.length,
    );
  }
}
