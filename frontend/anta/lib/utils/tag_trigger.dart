/// Where a `#tag` suggestion session sits on a line — the typing half of the
/// tag autocomplete, beside `VocabularyTrigger`.
///
/// It holds no tag pattern of its own: a tag is whatever the inline grammar
/// renders as one ([MarkdownInlineGrammar.linksAndTags]), so a heading's `# `,
/// `#123`, a `#` glued to a word, a code span, a bare URL's fragment and a
/// ghost run are ruled out by the rule both surfaces already paint with, and
/// the bar can never offer to complete something the editor does not show as
/// a tag.
library;

import 'markdown_color_syntax.dart';
import 'markdown_inline_grammar.dart';

/// The tag the caret is in or at the end of: its `#` at [hashOffset], its
/// end at [tagEnd], and what has been typed of it, `#` included, in [query]
/// (`line.substring(hashOffset, caret)`).
///
/// Accepting a suggestion replaces `[hashOffset, tagEnd)` — the whole tag, not
/// only the part before the caret, so completing `#leg|dy` leaves no `dy`
/// behind.
class TagTriggerMatch {
  final int hashOffset;
  final int tagEnd;
  final String query;

  const TagTriggerMatch({
    required this.hashOffset,
    required this.tagEnd,
    required this.query,
  });
}

class TagTrigger {
  TagTrigger._();

  /// The tag [caret] sits in or right after on [line], or `null`.
  ///
  /// A bare `#` is never one — the grammar needs a body — so nothing opens
  /// before the first character after it, when a `#` at a line's start may
  /// still become a heading. A caret on the `#` itself is before the tag.
  ///
  /// [palette] only decides whether a `{name:…}` run is a colour, and a tag
  /// inside one is still a tag, so the presets serve every caller.
  ///
  /// Callers apply the editor-state guards this cannot see, as for
  /// `VocabularyTrigger.matchAt`: collapsed selection only, not while the IME
  /// is composing, not on a fence line, and not on lines past
  /// `MarkdownEditorSpanBuilder.maxStyledLineLength`.
  static TagTriggerMatch? matchAt(
    String line,
    int caret, {
    MarkdownColorPalette palette = MarkdownColorPalette.presets,
  }) {
    if (caret < 2 || caret > line.length) return null;
    if (!line.contains('#')) return null;
    for (final token in MarkdownInlineGrammar.linksAndTags(
      line,
      palette: palette,
    )) {
      if (token is! InlineTag) continue;
      if (token.start < caret && caret <= token.end) {
        return TagTriggerMatch(
          hashOffset: token.start,
          tagEnd: token.end,
          query: line.substring(token.start, caret),
        );
      }
    }
    return null;
  }
}
