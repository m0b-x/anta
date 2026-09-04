import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../constants/markdown_constants.dart';
import 'editor_render_context.dart';
import 'ghost_text.dart';
import 'markdown_color_syntax.dart';
import 'markdown_editor_emitter.dart';
import 'markdown_editor_inline_emitter.dart';
import 'markdown_editor_paint_spans.dart';
import 'markdown_money_syntax.dart';
import 'money_display_config.dart';

/// The live editor's money-ledger row: the one line shape whose chrome
/// composes four layers (list marker, heading, emphasis wrapper, `$`
/// marker) and whose value is positional rather than textual.
///
/// Shape decisions come from [MoneyRowLayout], glyphs from
/// [MarkdownMoneySyntax.glyph] and accents from
/// [MarkdownConstants.moneyAccent] — the same three the preview reads —
/// so the surfaces can only differ in how they emit, never in what they
/// think the row is. This surface stays source-faithful: label text
/// renders from the raw match offsets and the typed currency word stays
/// visible.
class EditorMoneyRowBuilder {
  const EditorMoneyRowBuilder._();

  /// Money-ledger line. Op rows conceal the `$` and render the op char
  /// in its accent (`-`/`*`//` substituted 1:1 with `−`/`×`/`÷`), the
  /// amount tinted, and the label with full inline styling — purely
  /// textual, so they live in the text-keyed memo. `$$` / `$?` / `$^`
  /// rows conceal the first `$` and substitute the second char 1:1 with
  /// a painted chip showing the computed [balance] (positional — cached
  /// upstream with the value in the key). On reveal both show raw
  /// dimmed markers, and the display rows paint nothing so the user
  /// edits real text; only marker conceal/substitution differs between
  /// reveal states, never line height.
  ///
  /// A heading prefix conceals its hashes and scales the row via the
  /// root span's fontSize (the fork gives such a line its own height,
  /// same as the header branch — identical in both reveal states). A
  /// resolved accent token is concealed and overrides the semantic
  /// accent; an unresolved one stays visible as plain source text.
  static TextSpan build({
    required String text,
    required MoneyLineMatch m,
    required EditorRenderContext context,
    required MoneyDisplayConfig config,
    required MarkdownColorPalette palette,
    required bool reveal,
    required List<GhostMatch> ghosts,
    required int balance,
  }) {
    final baseColor = context.baseColor;
    final primary = context.primary;
    final isDark = context.isDark;
    var style = context.style;

    // Error rows keep the source text — the editor must never change a
    // line's code units, so the message itself lives in the preview and
    // the detail sheet. Off-caret the `$` substitutes 1:1 with the `!`
    // the warning promises and the row tints yellow over a subtle
    // band; on reveal the raw source shows warn-tinted, no substitution.
    // Deliberately unscaled by any heading prefix (matching the
    // preview): both reveal states share the base height.
    if (MarkdownMoneySyntax.hasError(m)) {
      final warn = MarkdownConstants.moneyWarning(dark: isDark);
      final children = <InlineSpan>[];
      // Pre-marker chrome: heading hashes and/or emphasis opener,
      // contiguous by grammar; the emphasis closer needs no handling
      // here — the raw warn emit below covers to the line end.
      final chromeFrom = m.headerStart >= 0
          ? m.headerStart
          : m.emphasisStart >= 0
          ? m.emphasisStart
          : m.markerStart;
      final lead = m.listMarkerStart >= 0 ? m.listMarkerStart : chromeFrom;
      if (lead > 0) {
        children.add(TextSpan(text: text.substring(0, lead), style: style));
      }
      if (reveal) {
        EditorSpanEmitter.emit(
          text: text,
          start: lead,
          end: text.length,
          style: style.copyWith(color: warn),
          baseColor: baseColor,
          ghosts: ghosts,
          out: children,
        );
        return _finish(m, style, children);
      }
      final warnStyle = style.copyWith(
        color: warn,
        backgroundColor: warn.withValues(alpha: 0.1),
      );
      if (m.listMarkerStart >= 0) {
        // A broken bulleted row keeps its list marker, so the list
        // reads intact around the yellow row.
        _emitListMarker(
          text: text,
          m: m,
          gapEnd: chromeFrom,
          style: style,
          baseColor: baseColor,
          primary: primary,
          reveal: false,
          out: children,
        );
      }
      if (chromeFrom < m.markerStart) {
        children.add(
          TextSpan(
            text: text.substring(chromeFrom, m.markerStart),
            style: EditorSpanEmitter.concealStyle(style),
          ),
        );
      }
      children.add(
        TextSpan(
          text: '!',
          style: warnStyle.copyWith(fontWeight: FontWeight.bold),
        ),
      );
      EditorSpanEmitter.emit(
        text: text,
        start: m.markerStart + 1,
        end: text.length,
        style: warnStyle,
        baseColor: baseColor,
        ghosts: ghosts,
        out: children,
      );
      return _finish(m, style, children);
    }

    // The list-marker prefix is chrome *outside* the row's own styling:
    // it must render exactly like a plain list item's, or a bulleted
    // money row stops aligning with its plain siblings. Captured before
    // the heading/emphasis mutations below — a heading-scaled bullet is
    // bigger and a bold one has a wider trailing space, either of which
    // pushes the row's marker (and everything after it) off the list's
    // left edge.
    final listStyle = style;
    if (m.headerLevel > 0) {
      style = style.copyWith(
        fontSize:
            (style.fontSize ?? 16.0) *
            MarkdownConstants.editorHeaderScale(m.headerLevel),
        fontWeight: FontWeight.bold,
      );
    }
    // An emphasis wrapper styles the whole row; its marker runs conceal
    // with the rest of the pre-marker chrome below, and the closer is
    // appended (concealed) at the end of every path, so all code units
    // keep their offsets.
    if (m.emphasisLen > 0) {
      style = style.copyWith(
        fontStyle: m.emphasisItalic ? FontStyle.italic : null,
        fontWeight: m.emphasisBold ? FontWeight.bold : null,
      );
    }
    // The pre-marker chrome run: heading hashes and/or emphasis opener,
    // contiguous by grammar, concealed as one — the header branch does
    // the same for its `level + 1` chars.
    final chromeFrom = m.headerStart >= 0
        ? m.headerStart
        : m.emphasisStart >= 0
        ? m.emphasisStart
        : m.markerStart;
    final children = <InlineSpan>[];
    if (m.listMarkerStart >= 0) {
      // List-marker prefix: the indent stays visible so nesting keeps
      // its width, then the marker renders exactly like a list item's —
      // in [listStyle], the row's *unstyled* base, so the bullet sits on
      // the same left edge as every sibling bullet. Heading hashes / an
      // emphasis opener may follow (`- ## $$`, `- *$~ 2 x*`) — they
      // conceal below just like the list-less shapes.
      if (m.listMarkerStart > 0) {
        children.add(
          TextSpan(
            text: text.substring(0, m.listMarkerStart),
            style: listStyle,
          ),
        );
      }
      _emitListMarker(
        text: text,
        m: m,
        gapEnd: chromeFrom,
        style: listStyle,
        baseColor: baseColor,
        primary: primary,
        reveal: reveal,
        out: children,
      );
    } else if (chromeFrom > 0) {
      children.add(TextSpan(text: text.substring(0, chromeFrom), style: style));
    }
    if (chromeFrom < m.markerStart) {
      children.add(
        TextSpan(
          text: text.substring(chromeFrom, m.markerStart),
          style: reveal
              ? EditorSpanEmitter.dimStyle(style, baseColor)
              : EditorSpanEmitter.concealStyle(style),
        ),
      );
    }

    MarkdownColorSpec? accentSpec;
    if (m.accentStart >= 0) {
      accentSpec = palette.lookup(text.substring(m.accentStart, m.accentEnd));
    }

    // Glyph and semantic accent come from the shared palette (same two
    // functions the preview reads). Display kinds carry no op glyph
    // here — their chip paints the glyph itself — and `$! N`
    // declarations render source-faithfully like op rows (`!` → `◎`
    // amount-first; written label-first the row is a statement and the
    // glyph is suppressed, the `:` staying visible as typed). The
    // remaining budget lives on the bare `$!` status chip. A `$!`
    // status row with no target above it warns instead of reading green
    // off the sentinel; a resolved accent token overrides the semantic
    // colour either way.
    final bool noTarget =
        m.kind == MoneyLineKind.remaining &&
        MarkdownMoneySyntax.isNoTarget(balance);
    Color accent = noTarget
        ? MarkdownConstants.moneyWarning(dark: isDark)
        : MarkdownConstants.moneyAccent(
            m.kind,
            balance,
            dark: isDark,
            primary: primary,
          );
    final String opGlyph = MarkdownMoneySyntax.isDisplayKind(m.kind)
        ? ''
        : MarkdownMoneySyntax.glyph(m.kind);
    if (accentSpec != null) {
      accent = accentSpec.text(dark: isDark);
    }
    final accentStyle = style.copyWith(
      color: accent,
      fontWeight: FontWeight.w600,
    );
    // The label takes the row's accent — resolved colour token when
    // there is one, otherwise the semantic sign colour — matching the
    // preview. Colour only, so the base weight stays and the value
    // still leads.
    final labelStyle = style.copyWith(color: accent);

    // The accent token region: concealed when resolved (it is chrome,
    // like `{name:`), left as plain source text when it does not
    // resolve — nothing is ever silently eaten.
    // [concealGaps] hides the spaces around the token as well, for rows
    // whose whole marker run is chrome (label-first, where the op glyph
    // renders at the `:` instead) — otherwise they indent the row.
    void emitAccentToken(int from, int to, {bool concealGaps = false}) {
      final gapStyle = concealGaps
          ? EditorSpanEmitter.concealStyle(style)
          : style;
      if (from < m.accentStart) {
        children.add(
          TextSpan(text: text.substring(from, m.accentStart), style: gapStyle),
        );
      }
      children.add(
        TextSpan(
          text: text.substring(m.accentStart, m.accentEnd + 1),
          style: reveal
              ? EditorSpanEmitter.dimStyle(style, baseColor)
              : EditorSpanEmitter.concealStyle(style),
        ),
      );
      if (m.accentEnd + 1 < to) {
        children.add(
          TextSpan(text: text.substring(m.accentEnd + 1, to), style: gapStyle),
        );
      }
    }

    // One shared derivation of the row's shape (same object the preview
    // builds), so the surfaces cannot disagree on flags or slot. Label
    // text still renders from the raw match offsets — this surface is
    // source-faithful and keeps the currency word visible.
    final layout = MoneyRowLayout.of(text, m, config.currencySymbol);
    final isDisplay = layout.isDisplay;
    final slot = layout.slot;
    final hasSlot = slot >= 0;
    // Label-first rows (`$= Net worth: 5000`) read as an equation: the
    // op glyph renders at the `:` instead of leading the row. Needed
    // this early because it changes how the marker itself is emitted.
    final bool amountTrails = layout.labelFirst;
    // A count-taking display row may carry its accent token *after* the
    // count (`$~ 2 teal:`); the token then sits between the count and the
    // label rather than in the marker gap, and is concealed there instead.
    final bool accentAfterCount = layout.accentAfterCount;
    if (isDisplay) {
      if (reveal) {
        children.add(
          TextSpan(
            text: text.substring(m.markerStart, m.markerEnd),
            style: EditorSpanEmitter.dimStyle(style, baseColor),
          ),
        );
      } else if (hasSlot) {
        // The chip moved to the label's slot, so the marker renders like
        // an op row: `$` concealed, second char substituted 1:1 with the
        // kind's glyph. The substitution must stay one code unit wide or
        // the caret drifts, so `Δ=` narrows to `Δ` here — the `$^` count
        // digits and the signed value carry the distinction from `$?`.
        // (`Σ` and `◎` are already single code units.)
        children.add(
          TextSpan(text: r'$', style: EditorSpanEmitter.concealStyle(style)),
        );
        children.add(
          TextSpan(
            text: switch (m.kind) {
              MoneyLineKind.total => 'Σ',
              MoneyLineKind.remaining => '◎',
              _ => 'Δ',
            },
            style: accentStyle,
          ),
        );
      } else {
        children.add(
          TextSpan(text: r'$', style: EditorSpanEmitter.concealStyle(style)),
        );
        children.add(
          _valueSpan(
            style: style,
            config: config,
            isDark: isDark,
            accent: accent,
            balance: balance,
            kind: m.kind,
          ),
        );
      }
    } else {
      children.add(
        TextSpan(
          text: r'$',
          style: reveal
              ? EditorSpanEmitter.dimStyle(style, baseColor)
              : EditorSpanEmitter.concealStyle(style),
        ),
      );
      // On a label-first row the glyph renders at the `:` further along,
      // so the op char is concealed here instead of substituted. It must
      // still be emitted as its own source char — concealed, not
      // dropped — or every offset after it shifts by one.
      children.add(
        TextSpan(
          text: (reveal || amountTrails)
              ? text.substring(m.markerStart + 1, m.markerEnd)
              : opGlyph,
          style: reveal
              ? EditorSpanEmitter.dimStyle(style, baseColor)
              : amountTrails
              ? EditorSpanEmitter.concealStyle(style)
              : accentStyle,
        ),
      );
    }

    // Emits a label region, substituting the value slot's lone `$` 1:1
    // with the painted value — exactly like the second `$` of a `$$`
    // marker. Featured as a tinted chip on display rows, dimmed and
    // unfilled on op rows and `$=`/`$!` declarations, mirroring the
    // preview's pill/annotation split. On reveal the slot stays literal
    // text so the user edits real source.
    void emitLabelRegion(int from, int to) {
      if (from >= to) return;
      if (hasSlot && !reveal && slot >= from && slot < to) {
        if (from < slot) {
          EditorInlineEmitter.append(
            text: text,
            start: from,
            end: slot,
            contextStyle: labelStyle,
            context: context,
            palette: palette,
            reveal: reveal,
            ghosts: ghosts,
            out: children,
            depth: 0,
          );
        }
        children.add(
          _valueSpan(
            style: style,
            config: config,
            isDark: isDark,
            // Display rows keep their row accent (sentinel and pinned
            // resolve to the warning inside); op rows and the `$=`/`$!`
            // declaration slot spellings take the dimmed bare-number
            // look their preview annotation has.
            accent: isDisplay ? accent : baseColor.withValues(alpha: 0.5),
            balance: balance,
            kind: m.kind,
            atSlot: true,
            filled: isDisplay,
          ),
        );
        if (slot + 1 < to) {
          EditorInlineEmitter.append(
            text: text,
            start: slot + 1,
            end: to,
            contextStyle: labelStyle,
            context: context,
            palette: palette,
            reveal: reveal,
            ghosts: ghosts,
            out: children,
            depth: 0,
          );
        }
      } else {
        EditorInlineEmitter.append(
          text: text,
          start: from,
          end: to,
          contextStyle: labelStyle,
          context: context,
          palette: palette,
          reveal: reveal,
          ghosts: ghosts,
          out: children,
          depth: 0,
        );
      }
    }

    // A count-taking display row's window count (`$^ 2`, `$~ ALL`) is
    // syntax, not content — it selects the window the row measures just
    // as the accent token selects its colour — so the whole chrome run
    // from the marker to the label (spaces, accent token, count, in
    // either order) is concealed as one, keeping only the single space
    // that separates the painted chip from the label. Concealed, never
    // dropped: every source char stays in the span tree at its true
    // offset, so caret arithmetic is untouched and reveal (caret on the
    // line) shows the count again for editing. An unresolved accent
    // token opts the row out — nothing the parser could not resolve is
    // ever silently eaten — matching the preview, which simply declines
    // to paint the same run.
    final bool concealCount =
        isDisplay &&
        !reveal &&
        m.amountEnd > m.amountStart &&
        (m.accentStart < 0 || accentSpec != null);
    if (concealCount) {
      // The parser skips spaces to reach the label, so whenever a label
      // follows there is a space right before it to leave visible.
      // Bounded by [MoneyRowLayout.contentEnd], never the line length:
      // on an emphasis-wrapped row (`*$^ 2*`) the label is empty and
      // starts at the closer, and testing against the line length would
      // read that as "a label follows" and leave the count visible.
      final int keep = m.labelStart < layout.contentEnd
          ? m.labelStart - 1
          : m.labelStart;
      if (m.markerEnd < keep) {
        children.add(
          TextSpan(
            text: text.substring(m.markerEnd, keep),
            style: EditorSpanEmitter.concealStyle(style),
          ),
        );
      }
      if (keep < m.labelStart) {
        children.add(
          TextSpan(text: text.substring(keep, m.labelStart), style: style),
        );
      }
      emitLabelRegion(m.labelStart, layout.contentEnd);
      _emitEmphasisCloser(
        text: text,
        m: m,
        style: style,
        baseColor: baseColor,
        reveal: reveal,
        out: children,
      );
      return _finish(m, style, children);
    }

    // Between the marker and whatever comes first sit only spaces and
    // the optional accent token (parse-guaranteed, so no ghost can start
    // here). On a label-first row (`$- Loss: 5000`) that run ends at the
    // label instead of the amount — every span below stays a contiguous
    // source range in document order, which is what keeps editor offsets
    // 1:1 regardless of which order the row was written in.
    final int gapEnd = amountTrails ? m.labelStart : m.amountStart;
    // On a label-first row the glyph has moved to the `:`, so this whole
    // run is chrome and must not take up width. The exception is an
    // unresolved accent token, which stays visible as literal source
    // (nothing is ever silently eaten) and brings its spacing with it.
    final bool chromeGap = amountTrails && !reveal;
    if (m.markerEnd < gapEnd) {
      if (accentSpec != null && !accentAfterCount) {
        emitAccentToken(m.markerEnd, gapEnd, concealGaps: chromeGap);
      } else {
        children.add(
          TextSpan(
            text: text.substring(m.markerEnd, gapEnd),
            style: chromeGap && m.accentStart < 0
                ? EditorSpanEmitter.concealStyle(style)
                : style,
          ),
        );
      }
    }
    if (amountTrails) {
      if (reveal || m.kind == MoneyLineKind.target) {
        // Raw source while editing: the `:` stays a plain character and
        // the marker above shows its dimmed `$=`. A `$!` declaration
        // keeps its `:` in *both* states — written label-first it is a
        // statement, not an equation, so no target glyph renders and
        // `### $! yellow: Groceries: 500` reads "Groceries: 500"
        // (matching the preview's icon suppression).
        emitLabelRegion(m.labelStart, m.labelEnd);
      } else {
        emitLabelRegion(m.labelStart, m.labelEnd - 1);
        // The `:` is chrome here, replaced by the op glyph so the row
        // reads `Net worth = 5000`. It goes through the placeholder
        // mechanism rather than a 1:1 text swap because the source has
        // no character before the `:` to render as a space — a plain
        // substitution would read `Net worth= 5000`.
        children.add(_glyphSpan(style: style, accent: accent, glyph: opGlyph));
      }
      if (m.labelEnd < m.amountStart) {
        children.add(
          TextSpan(
            text: text.substring(m.labelEnd, m.amountStart),
            style: style,
          ),
        );
      }
      EditorSpanEmitter.emit(
        text: text,
        start: m.amountStart,
        end: m.amountEnd,
        style: accentStyle,
        baseColor: baseColor,
        ghosts: ghosts,
        out: children,
      );
      // Free trailing text after the amount (`$= Worth: 500 lei so
      // far`): a label region like any other, slot included. The
      // currency word stays visible as typed — this surface renders
      // source faithfully, same as amounts.
      emitLabelRegion(m.amountEnd, layout.contentEnd);
    } else {
      // The amount run covers op amounts and `$^ N` count digits alike —
      // display rows without a count have an empty range.
      if (m.amountStart < m.amountEnd) {
        EditorSpanEmitter.emit(
          text: text,
          start: m.amountStart,
          end: m.amountEnd,
          style: accentStyle,
          baseColor: baseColor,
          ghosts: ghosts,
          out: children,
        );
      }
      if (accentAfterCount && accentSpec != null) {
        // A resolved accent written after the count is chrome, exactly
        // like an accent-first row: conceal the token between the count
        // and the label, then render the label proper. An unresolved
        // token falls through to the label run and stays visible as typed.
        emitAccentToken(m.amountEnd, m.labelStart);
        emitLabelRegion(m.labelStart, layout.contentEnd);
      } else {
        emitLabelRegion(m.amountEnd, layout.contentEnd);
      }
    }
    _emitEmphasisCloser(
      text: text,
      m: m,
      style: style,
      baseColor: baseColor,
      reveal: reveal,
      out: children,
    );
    return _finish(m, style, children);
  }

  /// A money row's list-marker prefix, `[listMarkerStart, markerStart)`:
  /// the bullet substitutes 1:1 with `•` exactly like a plain list item
  /// (ordered numbers stay as typed, tinted), and the gap spaces keep
  /// their width — every code unit at its offset, reading as a list
  /// item. Callers emit `[0, listMarkerStart)` (the indent) themselves.
  static void _emitListMarker({
    required String text,
    required MoneyLineMatch m,
    required int gapEnd,
    required TextStyle style,
    required Color baseColor,
    required Color primary,
    required bool reveal,
    required List<InlineSpan> out,
  }) {
    final mc = text.codeUnitAt(m.listMarkerStart);
    if (mc >= 0x30 && mc <= 0x39) {
      out.add(
        TextSpan(
          text: text.substring(m.listMarkerStart, m.listMarkerEnd),
          style: style.copyWith(color: primary, fontWeight: FontWeight.w600),
        ),
      );
    } else {
      out.add(
        TextSpan(
          text: reveal
              ? text.substring(m.listMarkerStart, m.listMarkerEnd)
              : '•',
          style: reveal
              ? EditorSpanEmitter.dimStyle(style, baseColor)
              : style.copyWith(color: primary, fontWeight: FontWeight.bold),
        ),
      );
    }
    // [gapEnd] is where the next chrome piece begins: heading hashes,
    // an emphasis opener, or the `$` itself — the caller knows.
    if (m.listMarkerEnd < gapEnd) {
      out.add(
        TextSpan(text: text.substring(m.listMarkerEnd, gapEnd), style: style),
      );
    }
  }

  /// The emphasis closing run (plus any trailing spaces): chrome,
  /// concealed off-caret and dimmed raw on reveal, appended after all
  /// content so the code-unit inventory stays complete. Error rows skip
  /// this — their raw warn emit already covers to the line end.
  static void _emitEmphasisCloser({
    required String text,
    required MoneyLineMatch m,
    required TextStyle style,
    required Color baseColor,
    required bool reveal,
    required List<InlineSpan> out,
  }) {
    if (m.emphasisCloseStart < 0) return;
    out.add(
      TextSpan(
        text: text.substring(m.emphasisCloseStart),
        style: reveal
            ? EditorSpanEmitter.dimStyle(style, baseColor)
            : EditorSpanEmitter.concealStyle(style),
      ),
    );
  }

  /// Money-row root span: plain normally, the fork's hanging span when
  /// the row carries a list-marker prefix so soft-wrapped continuation
  /// aligns under the `$` like any list item's content. Identical in
  /// both reveal states, exactly like a plain list item's root.
  static TextSpan _finish(
    MoneyLineMatch m,
    TextStyle style,
    List<InlineSpan> children,
  ) {
    if (m.listMarkerStart < 0) {
      return TextSpan(style: style, children: children);
    }
    return CodeHangingTextSpan(
      hangingChars: m.markerStart,
      style: style,
      children: children,
    );
  }

  /// A single op glyph painted into a label-first row's `:` placeholder,
  /// carrying the horizontal padding a 1:1 text substitution cannot: the
  /// source has no character before the `:` to render as a space, so a
  /// plain swap would read `Net worth= 5000`. Same fork
  /// [EditorMoneyTotalSpan] mechanism as the money chip, unfilled — and
  /// like op rows generally it depends only on the line text, so it
  /// rides the text-keyed span memo and lays out once per unique line.
  static EditorMoneyTotalSpan _glyphSpan({
    required TextStyle style,
    required Color accent,
    required String glyph,
  }) {
    final fontSize = style.fontSize ?? 16.0;
    final painter = TextPainter(
      text: TextSpan(
        text: glyph,
        style: style.copyWith(
          color: accent,
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final lineBox = fontSize * (style.height ?? MarkdownConstants.lineHeight);
    final maxHeight = lineBox * 0.9;
    final height = painter.height > maxHeight ? maxHeight : painter.height;
    return EditorMoneyTotalSpan(
      width: painter.width + fontSize * 0.6,
      height: height,
      painter: painter,
      label: glyph,
      accent: accent,
      chip: const Color(0x00000000),
      radius: 0,
    );
  }

  /// Builds the painted chip for a `$$` total (`Σ` + balance), a `$?`
  /// net change (`Δ` + signed change), a bare `$!` target status (`◎` +
  /// remaining budget, or "no target"), a `$^` entry diff (`Δ=` +
  /// signed move), or a `$~` checkpoint span (`Δ~` + signed move), laid
  /// out once here (memoized upstream via the positional span cache)
  /// and painted into the placeholder box.
  /// The box height stays under the line's strut height so the line
  /// never grows.
  ///
  /// [atSlot] drops the leading glyph — a row whose value sits in a
  /// label slot already renders that glyph at its marker, and the label
  /// itself says what the number is. [filled] draws the rounded chip
  /// behind it; op rows pass `false` for the dimmed bare-number look
  /// their trailing `=` annotation has in the preview.
  static EditorMoneyTotalSpan _valueSpan({
    required TextStyle style,
    required MoneyDisplayConfig config,
    required bool isDark,
    required Color accent,
    required int balance,
    required MoneyLineKind kind,
    bool atSlot = false,
    bool filled = true,
  }) {
    // A value pinned at the clamp limit paints in the warning accent —
    // the number shown is the cap, not real arithmetic. Checked here so
    // the marker chip and the slot chip can never disagree. A bare `$!`
    // with no target above it is the same shape of exception: the
    // sentinel is not money, so the chip says "no target" in the same
    // warning accent instead of formatting it.
    final noTarget =
        kind == MoneyLineKind.remaining &&
        MarkdownMoneySyntax.isNoTarget(balance);
    if (noTarget || MarkdownMoneySyntax.valuePinned(balance)) {
      accent = MarkdownConstants.moneyWarning(dark: isDark);
    }
    final signed = MarkdownMoneySyntax.isSignedKind(kind);
    final value = noTarget
        ? 'no target'
        : signed
        ? MarkdownMoneySyntax.formatCentsSignedWithSymbol(
            balance,
            symbol: config.currencySymbol,
            suffix: config.currencySuffix,
          )
        : MarkdownMoneySyntax.formatCentsWithSymbol(
            balance,
            symbol: config.currencySymbol,
            suffix: config.currencySuffix,
          );
    // Chip glyph from the shared palette; only display kinds reach the
    // non-slot label (op-row chips always sit at a slot).
    final label = atSlot ? value : '${MarkdownMoneySyntax.glyph(kind)} $value';
    final fontSize = style.fontSize ?? 16.0;
    final lineBox = fontSize * (style.height ?? MarkdownConstants.lineHeight);
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: style.copyWith(
          color: accent,
          fontWeight: FontWeight.bold,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final hPad = fontSize * 0.3;
    var chipHeight = painter.height + fontSize * 0.12;
    final maxHeight = lineBox * 0.9;
    if (chipHeight > maxHeight) chipHeight = maxHeight;
    return EditorMoneyTotalSpan(
      width: painter.width + hPad * 2,
      height: chipHeight,
      painter: painter,
      label: label,
      accent: accent,
      chip: filled
          ? accent.withValues(
              alpha: MarkdownConstants.editorChipBackgroundAlpha,
            )
          : const Color(0x00000000),
      radius: fontSize * 0.35,
    );
  }
}
