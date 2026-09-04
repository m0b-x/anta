import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../constants/markdown_constants.dart';
import 'editor_render_context.dart';
import 'ghost_text.dart';
import 'markdown_color_syntax.dart';
import 'markdown_editor_emitter.dart';
import 'markdown_inline_grammar.dart';

/// The live editor's inline layer: an emitter over
/// [MarkdownInlineGrammar] tokens, and the styles those tokens apply.
///
/// It is the editor half of the one-grammar rule — the preview's
/// `_parseInline` is the other — so nothing here scans for a construct;
/// it only decides how a token is *emitted*, which is where the two
/// surfaces legitimately differ (the editor conceals markers, the
/// preview drops them).
///
/// Static, like [EditorSpanEmitter]: the build path allocates no
/// emitter and captures no closure per line.
class EditorInlineEmitter {
  const EditorInlineEmitter._();

  /// Alpha of the rounded chip painted behind inline `` `code` ``
  /// content.
  static const double _codeBackgroundAlpha = 0.08;

  /// Appends spans covering [start]..[end], styling every inline
  /// construct [MarkdownInlineGrammar] finds there — emphasis, strike,
  /// highlight, inline code, `[text](url)` links and images, bare URLs,
  /// `#tag` tokens, `{name:text}` colours, ghost runs and backslash
  /// escapes — against [contextStyle]. The grammar is shared with the
  /// preview: this method never scans for a construct of its own, it
  /// only decides how each token is emitted (conceal vs drop is the one
  /// difference between the two surfaces), and it recurses into a
  /// container's inner range for the nested tokens. Gaps between tokens
  /// are plain text.
  ///
  /// Ghost runs come back as tokens and are emitted through the
  /// ghost-aware [EditorSpanEmitter.emit] like everything else, so their
  /// markers stay concealed inside whatever style surrounds them. They
  /// are not "styling" on their own — the caller falls back to the
  /// ghost-only builder when nothing else matched.
  ///
  /// Nesting is bounded by [MarkdownInlineGrammar.maxNestingDepth]: past
  /// it the tokenizer returns nothing, so the inner range emits plain
  /// through the gap path on both surfaces alike. Returns whether any
  /// non-ghost token was found.
  static bool append({
    required String text,
    required int start,
    required int end,
    required TextStyle contextStyle,
    required EditorRenderContext context,
    required MarkdownColorPalette palette,
    required bool reveal,
    required List<GhostMatch> ghosts,
    required List<InlineSpan> out,
    required int depth,
  }) {
    final baseColor = context.baseColor;
    final primary = context.primary;
    final tokens = MarkdownInlineGrammar.tokenize(
      text,
      start: start,
      end: end,
      ghosts: ghosts,
      palette: palette,
      depth: depth,
    );
    if (tokens.isEmpty) {
      EditorSpanEmitter.emit(
        text: text,
        start: start,
        end: end,
        style: contextStyle,
        baseColor: baseColor,
        ghosts: ghosts,
        out: out,
      );
      return false;
    }

    final markerStyle = reveal
        ? EditorSpanEmitter.dimStyle(contextStyle, baseColor)
        : EditorSpanEmitter.concealStyle(contextStyle);
    var styled = false;
    var plainFrom = start;
    for (final token in tokens) {
      if (plainFrom < token.start) {
        EditorSpanEmitter.emit(
          text: text,
          start: plainFrom,
          end: token.start,
          style: contextStyle,
          baseColor: baseColor,
          ghosts: ghosts,
          out: out,
        );
      }
      plainFrom = token.end;
      switch (token) {
        case InlineGhost():
          // [EditorSpanEmitter.emit] already splits ghosts out of any
          // range; a ghost token just marks where one is, and styles
          // nothing.
          EditorSpanEmitter.emit(
            text: text,
            start: token.start,
            end: token.end,
            style: contextStyle,
            baseColor: baseColor,
            ghosts: ghosts,
            out: out,
          );
        case InlineEscape():
          // The escaped punctuation renders literally with the `\`
          // concealed off-caret, dimmed on reveal. Never inside a ghost
          // by the grammar, so no ghost split is needed here.
          out.add(TextSpan(text: r'\', style: markerStyle));
          out.add(
            TextSpan(
              text: text.substring(token.charStart, token.end),
              style: contextStyle,
            ),
          );
          styled = true;
        case InlineCode():
          // Code spans are literal all the way down: no recursion, and
          // the chip is painted at the emit site (CodeDecoratedTextSpan)
          // rather than as a per-glyph background.
          EditorSpanEmitter.emitChrome(
            text,
            token.start,
            token.innerStart,
            markerStyle,
            out,
          );
          EditorSpanEmitter.emit(
            text: text,
            start: token.innerStart,
            end: token.innerEnd,
            style: contextStyle,
            baseColor: baseColor,
            ghosts: ghosts,
            out: out,
            decoration: _codeDecoration(contextStyle, baseColor),
          );
          EditorSpanEmitter.emitChrome(
            text,
            token.innerEnd,
            token.end,
            markerStyle,
            out,
          );
          styled = true;
        case InlineLink():
          // `![image](url)` stays raw in the editor — the preview owns
          // image rendering — so its chrome is emitted plain and the alt
          // text keeps the surrounding style. A real link tints and
          // underlines its text with `[` and `](url)` concealed.
          final isImage = token.isImage;
          EditorSpanEmitter.emit(
            text: text,
            start: token.start,
            end: token.textStart,
            style: isImage ? contextStyle : markerStyle,
            baseColor: baseColor,
            ghosts: ghosts,
            out: out,
          );
          append(
            text: text,
            start: token.textStart,
            end: token.textEnd,
            contextStyle: isImage
                ? contextStyle
                : _linkStyle(contextStyle, primary),
            context: context,
            palette: palette,
            reveal: reveal,
            ghosts: ghosts,
            out: out,
            depth: depth + 1,
          );
          EditorSpanEmitter.emit(
            text: text,
            start: token.textEnd,
            end: token.end,
            style: isImage ? contextStyle : markerStyle,
            baseColor: baseColor,
            ghosts: ghosts,
            out: out,
          );
          styled = true;
        case InlineColor():
          // `{name:` and `}` are concealed (transparent + ~0 size) so
          // the line keeps every source code unit.
          EditorSpanEmitter.emitChrome(
            text,
            token.start,
            token.innerStart,
            markerStyle,
            out,
          );
          append(
            text: text,
            start: token.innerStart,
            end: token.innerEnd,
            contextStyle: contextStyle.copyWith(
              color: token.spec.text(dark: context.isDark),
            ),
            context: context,
            palette: palette,
            reveal: reveal,
            ghosts: ghosts,
            out: out,
            depth: depth + 1,
          );
          EditorSpanEmitter.emitChrome(
            text,
            token.innerEnd,
            token.end,
            markerStyle,
            out,
          );
          styled = true;
        case InlineTag():
          EditorSpanEmitter.emit(
            text: text,
            start: token.start,
            end: token.end,
            style: contextStyle.copyWith(
              color: primary,
              fontWeight: FontWeight.w600,
            ),
            baseColor: baseColor,
            ghosts: ghosts,
            out: out,
            decoration: _tagDecoration(contextStyle, primary),
          );
          styled = true;
        case InlineUrl():
          EditorSpanEmitter.emit(
            text: text,
            start: token.start,
            end: token.end,
            style: _linkStyle(contextStyle, primary),
            baseColor: baseColor,
            ghosts: ghosts,
            out: out,
          );
          styled = true;
        case InlineEmphasis():
          EditorSpanEmitter.emitChrome(
            text,
            token.start,
            token.innerStart,
            markerStyle,
            out,
          );
          // `==name:text==` tints the highlight and conceals the
          // `name:` prefix as chrome alongside the `==` markers; an
          // unresolved name never reaches here (the tokenizer leaves it
          // as content) so nothing is ever silently eaten.
          final TextStyle runStyle;
          if (token.contentStart > token.innerStart) {
            EditorSpanEmitter.emitChrome(
              text,
              token.innerStart,
              token.contentStart,
              markerStyle,
              out,
            );
            runStyle = contextStyle.copyWith(
              backgroundColor: token.tintSpec!.highlight(dark: context.isDark),
            );
          } else {
            runStyle = _runStyle(contextStyle, token.kind, context.isDark);
          }
          append(
            text: text,
            start: token.contentStart,
            end: token.innerEnd,
            contextStyle: runStyle,
            context: context,
            palette: palette,
            reveal: reveal,
            ghosts: ghosts,
            out: out,
            depth: depth + 1,
          );
          EditorSpanEmitter.emitChrome(
            text,
            token.innerEnd,
            token.end,
            markerStyle,
            out,
          );
          styled = true;
      }
    }
    if (plainFrom < end) {
      EditorSpanEmitter.emit(
        text: text,
        start: plainFrom,
        end: end,
        style: contextStyle,
        baseColor: baseColor,
        ghosts: ghosts,
        out: out,
      );
    }
    return styled;
  }

  static TextStyle _linkStyle(TextStyle context, Color primary) =>
      context.copyWith(
        color: primary,
        decoration: TextDecoration.underline,
        decorationColor: primary,
      );

  /// The style a matched delimiter pair applies to its content. An
  /// untinted `==highlight==` keeps the legacy amber, which is what the
  /// palette's `yellow` preset resolves to; a tinted one never reaches
  /// here (the caller applies the resolved highlight instead).
  static TextStyle _runStyle(
    TextStyle context,
    InlineEmphasisKind kind,
    bool isDark,
  ) => switch (kind) {
    InlineEmphasisKind.boldItalic => context.copyWith(
      fontWeight: FontWeight.bold,
      fontStyle: FontStyle.italic,
    ),
    InlineEmphasisKind.bold => context.copyWith(fontWeight: FontWeight.bold),
    InlineEmphasisKind.italic => context.copyWith(fontStyle: FontStyle.italic),
    InlineEmphasisKind.strikethrough => context.copyWith(
      decoration: TextDecoration.lineThrough,
      decorationColor: context.color,
    ),
    InlineEmphasisKind.highlight => context.copyWith(
      backgroundColor: isDark
          ? MarkdownConstants.markBackgroundDark
          : MarkdownConstants.markBackgroundLight,
    ),
  };

  /// Stadium pill behind a `#tag` run. Radius past half the chip height
  /// clamps to a stadium; the vertical inset trims the strut-height box
  /// to ~1.06em so pills read uniform at every editor font size.
  static CodeTextDecoration _tagDecoration(TextStyle context, Color primary) {
    final size = context.fontSize ?? 16.0;
    return CodeTextDecoration(
      color: primary.withValues(
        alpha: MarkdownConstants.editorChipBackgroundAlpha,
      ),
      radius: size,
      horizontalPadding: size * 0.15,
      verticalInset: size * 0.22,
    );
  }

  /// Rounded chip behind inline `` `code` `` content (markers stay
  /// outside the chip).
  static CodeTextDecoration _codeDecoration(
    TextStyle context,
    Color baseColor,
  ) {
    final size = context.fontSize ?? 16.0;
    return CodeTextDecoration(
      color: baseColor.withValues(alpha: _codeBackgroundAlpha),
      radius: size * 0.25,
      horizontalPadding: size * 0.1,
      verticalInset: size * 0.16,
    );
  }
}
