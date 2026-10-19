import 'markdown_callout_syntax.dart';
import 'markdown_list_syntax.dart';

/// What Enter does to a line that carries a marker and nothing after it:
/// the answer of [MarkdownListUtils.emptyLineEnd].
sealed class MarkdownEmptyLineEnd {
  const MarkdownEmptyLineEnd();
}

/// The innermost marker ends: the line becomes [text] — a bare line for a
/// top-level item or an empty quote line, the quote's `>` run alone for a
/// top-level item inside a quote, so a quoted list ends into its quote
/// before the quote itself ends.
final class MarkdownEndMarker extends MarkdownEmptyLineEnd {
  const MarkdownEndMarker(this.text);

  final String text;
}

/// The item is nested: it goes up one level instead of ending. [quote] is
/// the `>` run in front of it (empty outside a quote) and [item] the item
/// itself; the caller outdents [item] by the editor's own Shift-Tab step,
/// so Enter and Shift-Tab always land an item on the same column.
final class MarkdownOutdentItem extends MarkdownEmptyLineEnd {
  const MarkdownOutdentItem({required this.quote, required this.item});

  final String quote;
  final String item;
}

/// List-aware editing helpers for the markdown editor: continuing a list
/// on Enter (preserving indentation), terminating it on an empty item,
/// and indenting. Detection delegates to [MarkdownListSyntax] so the
/// editor and the preview renderer share one definition of list syntax;
/// quote lines are read through [MarkdownCalloutSyntax.quoteMarkers] for
/// the same reason.
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

  /// The text the line after [line] starts with when Enter is pressed at
  /// its end: [getListPrefix] on a list line; on a quote line, its `>` run
  /// as written followed by the list prefix of what it quotes — `> a`
  /// continues as `> `, `> > a` as `> > `, `> - a` as `> - `. A callout
  /// lead (`> [!TIP] title`) continues into its body, `> `. `null` when
  /// [line] is neither, and the new line stays bare.
  static String? continuationPrefix(String line) {
    final listPrefix = getListPrefix(line);
    if (listPrefix != null) return listPrefix;
    final quote = MarkdownCalloutSyntax.quoteMarkers(line);
    if (quote == null) return null;
    final rest = line.substring(quote.contentStart);
    return '${line.substring(0, quote.contentStart)}'
        '${getListPrefix(rest) ?? ''}';
  }

  /// What Enter on [line] does when [line] holds a marker and nothing
  /// else, or `null` when it holds content (and Enter continues it).
  ///
  /// Each Enter undoes one marker, innermost first: a nested item goes up
  /// a level, a top-level item ends (into its quote, if it has one), an
  /// empty quote line drops its innermost `>` and a one-level one ends
  /// the quote. A callout lead is never empty — its
  /// `[!TYPE]` token is content — so Enter on one always opens the body.
  static MarkdownEmptyLineEnd? emptyLineEnd(String line) {
    final item = MarkdownListSyntax.parse(line);
    if (item != null) return _emptyItemEnd('', line, item);
    final quote = MarkdownCalloutSyntax.quoteMarkers(line);
    if (quote == null) return null;
    final run = line.substring(0, quote.contentStart);
    final rest = line.substring(quote.contentStart);
    final quoted = MarkdownListSyntax.parse(rest);
    if (quoted != null) return _emptyItemEnd(run, rest, quoted);
    if (rest.trim().isNotEmpty) return null;
    // The innermost `>` goes, as Backspace takes it
    // (`MarkerBackspacePolicy`): `> > ` leaves `> `, and `> ` a bare line.
    if (quote.depth == 1) return const MarkdownEndMarker('');
    return MarkdownEndMarker(line.substring(0, quote.markerOffsets.last));
  }

  static MarkdownEmptyLineEnd? _emptyItemEnd(
    String quote,
    String line,
    MarkdownListItem item,
  ) {
    if (!item.isEmpty) return null;
    if (item.level > 0) return MarkdownOutdentItem(quote: quote, item: line);
    return MarkdownEndMarker(quote);
  }
}
