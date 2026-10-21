import 'package:flutter/material.dart';

import '../constants/markdown_constants.dart';
import 'editor_render_context.dart';
import 'ghost_text.dart';
import 'markdown_color_syntax.dart';
import 'markdown_editor_emitter.dart';
import 'markdown_editor_inline_emitter.dart';
import 'markdown_editor_span_builder.dart';
import 'markdown_line_shape.dart';

/// A short markdown term rendered as a one-line chip: the vocabulary
/// suggestion pill previews how a term will read in the note once
/// accepted, the way an IDE's completion popup colours its items.
///
/// It is the editor's own rendering, not a third grammar: the term goes
/// through [EditorInlineEmitter.append] with markers concealed, so a
/// construct the editor learns reaches the chip for free and the two can
/// never disagree.
class MarkdownChipSpan {
  /// The term's rendering, or the raw term in the incoming style wherever
  /// a rendering would mislead or show nothing.
  final InlineSpan span;

  /// The heading level the term was flattened from, or null when it is
  /// not a heading. The chip's row has a fixed height, so a heading keeps
  /// the chip's font size and the caller shows this level beside it.
  final int? headingLevel;

  const MarkdownChipSpan._(this.span, this.headingLevel);

  /// Renders [term] as the live editor renders a line with the caret
  /// elsewhere, at [style]'s size: plain runs in [style]'s colour, tags,
  /// links and colours from [theme] and [palette]. It stops short of what
  /// only the editor's paragraph paints on its own (the tag and
  /// inline-code chips) and of the editor's heading size and H5/H6 tint.
  ///
  /// [headings] says whether an ATX heading may be flattened; false
  /// renders the term as the inline prose it will be. A flattened heading
  /// drops its hashes and takes the editor's heading weight but never its
  /// size, since a taller chip would grow the row it sits in.
  ///
  /// A trailing `\` is never a hard break here: an accepted term is
  /// followed by a space, so the note always shows the backslash.
  ///
  /// Concealed markers keep their style's letter spacing (Material's
  /// `bodyMedium` carries 0.25 px per code unit), so a long link's hidden
  /// URL would leave a wide invisible tail inside the chip; the rendering
  /// is built at zero letter spacing for that reason.
  ///
  /// Falls back to the raw term past the editor's styling cap, as that
  /// line would stay raw in the editor, and whenever the rendering shows
  /// nothing at all (an empty heading, `%%note%%`, `# %%x%%`): a chip that
  /// shows nothing is worse than one that shows the source.
  static MarkdownChipSpan build({
    required String term,
    required TextStyle style,
    required ThemeData theme,
    required MarkdownColorPalette palette,
    bool headings = true,
  }) {
    final raw = MarkdownChipSpan._(TextSpan(text: term, style: style), null);
    if (term.length > MarkdownEditorSpanBuilder.maxStyledLineLength) {
      return raw;
    }
    final heading = headings ? MarkdownLineShape.headingAt(term) : null;
    if (heading != null && heading.contentStart >= heading.contentEnd) {
      return raw;
    }
    final flat = style.copyWith(letterSpacing: 0);
    final contextStyle = heading == null
        ? flat
        : flat.copyWith(fontWeight: MarkdownConstants.headingWeight);
    final out = <InlineSpan>[];
    EditorInlineEmitter.append(
      text: term,
      start: heading?.contentStart ?? 0,
      end: heading?.contentEnd ?? term.length,
      contextStyle: contextStyle,
      context: EditorRenderContext.fromTheme(theme, contextStyle),
      palette: palette,
      reveal: false,
      ghosts: GhostText.mightContain(term)
          ? GhostText.findGhosts(term)
          : const <GhostMatch>[],
      out: out,
      depth: 0,
      hardBreaks: false,
    );
    if (!_showsAnything(out)) return raw;
    return MarkdownChipSpan._(
      TextSpan(style: contextStyle, children: out),
      heading?.level,
    );
  }

  static bool _showsAnything(List<InlineSpan> spans) {
    var visible = false;
    for (final span in spans) {
      span.visitChildren((child) {
        if (child is TextSpan && (child.text?.isNotEmpty ?? false)) {
          final style = child.style;
          visible =
              style == null ||
              style.color != EditorSpanEmitter.transparent ||
              style.fontSize != EditorSpanEmitter.concealedFontSize;
        }
        return !visible;
      });
      if (visible) return true;
    }
    return false;
  }
}
