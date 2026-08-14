import 'markdown_list_syntax.dart';

/// List-aware editing helpers for the markdown editor: continuing a list
/// on Enter (preserving indentation), terminating it on an empty item,
/// and indenting. Detection delegates to [MarkdownListSyntax] so the
/// editor and the preview renderer share one definition of list syntax.
class MarkdownListUtils {
  MarkdownListUtils._();

  /// Spaces inserted per indent level when continuing or indenting a
  /// list. Matches re_editor's default indent width.
  static const int indentUnit = MarkdownListSyntax.indentUnit;

  /// Whether [line] begins a list item (bullet, ordered, or task).
  static bool isListLine(String line) => MarkdownListSyntax.isListLine(line);

  /// Whether [line] is a list item with no content after the marker —
  /// the signal to terminate the list when Enter is pressed.
  static bool isEmptyListItem(String line) {
    final item = MarkdownListSyntax.parse(line);
    return item != null && item.isEmpty;
  }

  /// The leading whitespace of [line] (spaces and/or tabs).
  static String leadingWhitespace(String line) {
    final trimmed = line.trimLeft();
    return line.substring(0, line.length - trimmed.length);
  }

  /// The marker to prepend to the next line when Enter is pressed on
  /// [line], preserving the original indentation so nested lists
  /// continue at the same depth. Task items continue unchecked; ordered
  /// items increment their number and keep their delimiter (`.` or `)`).
  /// Returns `null` when [line] is not a list item.
  static String? getListPrefix(String line) {
    final item = MarkdownListSyntax.parse(line);
    if (item == null) return null;
    switch (item.kind) {
      case MarkdownListKind.task:
        return '${item.indent}${item.marker} [ ] ';
      case MarkdownListKind.bullet:
        return '${item.indent}${item.marker} ';
      case MarkdownListKind.ordered:
        final next = (int.tryParse(item.marker) ?? 1) + 1;
        return '${item.indent}$next${item.delimiter} ';
    }
  }
}
