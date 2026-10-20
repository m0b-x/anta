import 'dart:convert';

import 'ghost_text.dart';
import 'markdown_callout_syntax.dart';
import 'markdown_chunker.dart';
import 'markdown_color_syntax.dart';
import 'markdown_inline_grammar.dart';
import 'markdown_line_shape.dart';
import 'markdown_list_syntax.dart';
import 'markdown_money_syntax.dart';

/// Renders markdown source as the plain text a reader sees — the third
/// emitter over the shared grammars, beside the preview's `_parseInline`
/// and the editor's `EditorInlineEmitter`.
///
/// Nothing here scans for a construct of its own: line shapes come from
/// [MarkdownLineShape], [MarkdownChunker.blockStateAfter],
/// [MarkdownCalloutSyntax], [MarkdownListSyntax] and
/// [MarkdownMoneySyntax], and everything inline comes from
/// [MarkdownInlineGrammar.tokenize]. The only decision this file makes
/// is how a token is *emitted*: markers are dropped rather than
/// concealed, because plain text has no styling to carry them.
///
/// The output is one whitespace-collapsed line — the note-row preview
/// and, through the stored `preview` column, quick-search and FTS input,
/// which is why every line contributes rather than only the first.
class MarkdownPlainText {
  MarkdownPlainText._();

  /// How deep a quoted block may nest another block shape before the
  /// walk stops unwrapping and emits the rest inline.
  static const int _maxBlockDepth = 6;

  /// The plain text of [content], collapsed onto one line and capped at
  /// [maxLength] with a trailing ellipsis.
  ///
  /// Blank lines, fence delimiters and fenced bodies, `%%` block comments,
  /// horizontal rules and table separators contribute nothing, and a
  /// trailing `\` is dropped only where a non-blank line follows (a hard
  /// break); every other line is
  /// unwrapped to its content and appended in source order, so the first
  /// meaningful line leads. A note whose every line strips to nothing
  /// (a lone `---`, a fenced-only note) falls back to the raw whitespace
  /// collapse, so a non-empty note never previews blank — less its `%%`
  /// comments, so a note that holds only a comment previews blank rather
  /// than the text its author hid.
  ///
  /// [money] is whether the text has a ledger. A note does, so a `$`-led
  /// line is one of its rows and loses its marker. An event's or a
  /// template's description has none — money is off there on every surface
  /// that renders it — and with [money] false such a line stays the text it
  /// was typed as, `$= 500` and not `500`.
  static String strip(
    String content, {
    MarkdownColorPalette palette = MarkdownColorPalette.presets,
    int maxLength = 200,
    bool money = true,
  }) {
    if (content.isEmpty) return '';

    final out = StringBuffer();
    final lines = const LineSplitter().convert(content);
    var state = MarkdownChunker.outsideBlock;
    // The open callout, stepped as the chunker steps it: only the line
    // that opens a block is its lead, so a `[!x]` on a body line stays
    // the body text both surfaces show.
    MarkdownCalloutType? callout;
    // The previous line when it sat outside every fence and comment, the
    // only kind a setext underline can belong to.
    String? previous;
    // A front matter is metadata, not text: the block is dropped whole.
    final body = MarkdownChunker.frontMatterEnd(lines.length, (i) => lines[i]);
    for (var i = body; i < lines.length; i++) {
      final line = lines[i];
      final entry = state;
      state = MarkdownChunker.blockStateAfter(line, state);
      final above = previous;
      previous = null;
      if (entry != MarkdownChunker.outsideBlock ||
          state != MarkdownChunker.outsideBlock) {
        callout = null;
        continue;
      }
      previous = line;
      // A setext underline is chrome: its text line above already printed.
      if (above != null && MarkdownLineShape.setextLevelOf(above, line) > 0) {
        callout = null;
        continue;
      }
      final openBefore = callout;
      callout = MarkdownCalloutSyntax.blockStep(line, callout);
      final isLead = openBefore == null && callout != null;
      final next = i + 1 < lines.length ? lines[i + 1] : null;
      // A trailing `\` breaks the line only where the paragraph continues,
      // and never on a setext heading's text line. Only a line that ends
      // in one pays the paragraph test.
      final hardBreaks =
          next != null &&
          line.endsWith(r'\') &&
          MarkdownChunker.continuesParagraph(
            line,
            next,
            i + 2 < lines.length ? lines[i + 2] : null,
          ) &&
          MarkdownLineShape.setextLevelOf(line, next) == 0;
      final before = out.length;
      _line(line, out, palette, 0, money, hardBreaks, isLead: isLead);
      if (out.length > before) out.write(' ');
    }

    final collapsed = _collapse(out.toString());
    final text = collapsed.isEmpty
        ? _collapse(_uncommented(lines.sublist(body), palette))
        : collapsed;
    return _cap(text, maxLength);
  }

  /// The fallback's source: [lines] as written, without `%%` block
  /// comments and with every top-level `%%…%%` run outside a fence cut.
  static String _uncommented(List<String> lines, MarkdownColorPalette palette) {
    final out = StringBuffer();
    var state = MarkdownChunker.outsideBlock;
    for (final line in lines) {
      final entry = state;
      state = MarkdownChunker.blockStateAfter(line, state);
      if (entry == MarkdownChunker.insideComment ||
          state == MarkdownChunker.insideComment) {
        continue;
      }
      var from = 0;
      if (entry == MarkdownChunker.outsideBlock &&
          state == MarkdownChunker.outsideBlock) {
        for (final token in MarkdownInlineGrammar.tokenize(
          line,
          palette: palette,
        )) {
          if (token is! InlineComment) continue;
          out.write(line.substring(from, token.start));
          from = token.end;
        }
      }
      out
        ..write(line.substring(from))
        ..write(' ');
    }
    return out.toString();
  }

  static String _collapse(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _cap(String text, int maxLength) {
    if (maxLength <= 0 || text.length <= maxLength) return text;
    var cut = maxLength;
    final unit = text.codeUnitAt(cut - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) cut--;
    return '${text.substring(0, cut)}...';
  }

  static void _line(
    String line,
    StringBuffer out,
    MarkdownColorPalette palette,
    int depth,
    bool money,
    bool hardBreaks, {
    bool isLead = false,
  }) {
    if (line.trim().isEmpty) return;
    if (MarkdownLineShape.isHorizontalRule(line)) return;
    if (MarkdownLineShape.isTableSeparator(line)) return;

    final ghosts = GhostText.mightContain(line)
        ? GhostText.findGhosts(line)
        : const <GhostMatch>[];

    // Only a block's opening line is read as a lead ([isLead]); nested
    // content never is.
    final lead = isLead ? MarkdownCalloutSyntax.parseLead(line) : null;
    if (lead != null) {
      // The token's own word, as both surfaces title it (`[!hint]` reads
      // `Hint`, an unknown `[!drill]` reads `Drill`); a fold marker is
      // chrome and never reaches the title.
      out.write(lead.label.trim());
      if (lead.title.isNotEmpty) {
        out.write(' ');
        _inline(
          line,
          lead.titleStart,
          line.length,
          out,
          palette,
          ghosts,
          0,
          false,
        );
      }
      return;
    }

    final quote = MarkdownCalloutSyntax.quoteMarkers(line);
    if (quote != null) {
      if (depth < _maxBlockDepth) {
        _line(
          line.substring(quote.contentStart),
          out,
          palette,
          depth + 1,
          money,
          hardBreaks,
        );
      } else {
        _inline(
          line,
          quote.contentStart,
          line.length,
          out,
          palette,
          ghosts,
          0,
          hardBreaks,
        );
      }
      return;
    }

    // Without a ledger the line falls through to the shapes below, so its
    // heading or list marker is still dropped and the `$` stays text.
    if (money && MarkdownMoneySyntax.leadsWithMoney(line)) {
      final match = MarkdownMoneySyntax.parse(line);
      if (match != null) {
        _moneyRow(line, match, out, palette, ghosts);
        return;
      }
    }

    final heading = MarkdownLineShape.headingAt(line);
    if (heading != null) {
      _inline(
        line,
        heading.contentStart,
        heading.contentEnd,
        out,
        palette,
        ghosts,
        0,
        false,
      );
      return;
    }

    final item = MarkdownListSyntax.parse(line);
    if (item != null) {
      if (item.kind == MarkdownListKind.task && item.checked) out.write('✓ ');
      // A custom state keeps its box as typed (`[-] skipped`): no glyph
      // carries `-` or `/` into a share or a note preview. The box is
      // written verbatim, since a `*`, a backtick or a `\` state would
      // otherwise open emphasis, code or an escape against the content.
      final custom =
          item.kind == MarkdownListKind.task &&
          !item.checked &&
          item.state != ' ';
      if (custom) {
        out.write(line.substring(item.bracketStart, item.bracketStart + 3));
      }
      _inline(
        line,
        custom ? item.bracketStart + 3 : item.contentStart,
        line.length,
        out,
        palette,
        ghosts,
        0,
        hardBreaks,
      );
      return;
    }

    if (MarkdownLineShape.isTableRow(line)) {
      _tableRow(line, out, palette, ghosts);
      return;
    }

    _inline(line, 0, line.length, out, palette, ghosts, 0, hardBreaks);
  }

  /// Cells of a `| a | b |` row joined with a middot. The row shape is
  /// [MarkdownLineShape.isTableRow]'s, so the outer pipes always exist
  /// and only the inner ones split — at the boundaries of
  /// [MarkdownLineShape.nextTableCellPipe], the editor's and the
  /// preview's splitter, so `\|`, a wiki alias and a ghost stay whole.
  static void _tableRow(
    String line,
    StringBuffer out,
    MarkdownColorPalette palette,
    List<GhostMatch> ghosts,
  ) {
    final trimmed = line.trim();
    final start = line.indexOf(trimmed);
    final last = start + trimmed.length - 1;
    var from = start + 1;
    var first = true;
    while (from <= last) {
      // An escaped closing pipe (`| a \|`) leaves no boundary at the end:
      // the last cell then runs to the line end and keeps its `|`.
      var i = MarkdownLineShape.nextTableCellPipe(line, from, ghosts);
      if (i < 0) i = last + 1;
      final cell = StringBuffer();
      _inline(line, from, i, cell, palette, ghosts, 0);
      final text = cell.toString().trim();
      if (text.isNotEmpty) {
        if (!first) out.write(' · ');
        out.write(text);
        first = false;
      }
      from = i + 1;
    }
  }

  /// A money row as typed: its label, its literal amount and any free
  /// trailing text, in source order. Never the folded balance — a
  /// preview is generated without the note's ledger, so a number here
  /// would be a guess that reads as a real one.
  static void _moneyRow(
    String line,
    MoneyLineMatch match,
    StringBuffer out,
    MarkdownColorPalette palette,
    List<GhostMatch> ghosts,
  ) {
    final contentEnd = match.emphasisCloseStart >= 0
        ? match.emphasisCloseStart
        : line.length;
    final hasAmount =
        match.amountEnd > match.amountStart &&
        !MarkdownMoneySyntax.isDisplayKind(match.kind);
    final amount = hasAmount
        ? line.substring(match.amountStart, match.amountEnd)
        : '';
    final labelEnd = match.labelEnd < contentEnd ? match.labelEnd : contentEnd;

    // A row is one line, so a trailing `\` is label text.
    if (match.labelStart < match.amountStart) {
      _spaced(out, () {
        _inline(
          line,
          match.labelStart,
          labelEnd,
          out,
          palette,
          ghosts,
          0,
          false,
        );
      });
      if (amount.isNotEmpty) _spaced(out, () => out.write(amount));
      _spaced(out, () {
        _inline(
          line,
          match.amountEnd,
          contentEnd,
          out,
          palette,
          ghosts,
          0,
          false,
        );
      });
      return;
    }

    if (amount.isNotEmpty) _spaced(out, () => out.write(amount));
    _spaced(out, () {
      _inline(line, match.labelStart, labelEnd, out, palette, ghosts, 0, false);
    });
  }

  static void _spaced(StringBuffer out, void Function() write) {
    final before = out.length;
    write();
    if (out.length > before) out.write(' ');
  }

  /// Emits `[start, end)` with every inline marker dropped, walking the
  /// tokens [MarkdownInlineGrammar.tokenize] reports and recursing into
  /// the ranges it declares nested. [hardBreaks] is false on a heading, a
  /// callout title and a money row, which keep a trailing `\` as text.
  static void _inline(
    String text,
    int start,
    int end,
    StringBuffer out,
    MarkdownColorPalette palette,
    List<GhostMatch> ghosts,
    int depth, [
    bool hardBreaks = true,
  ]) {
    if (start >= end) return;
    final tokens = MarkdownInlineGrammar.tokenize(
      text,
      start: start,
      end: end,
      ghosts: ghosts,
      palette: palette,
      depth: depth,
    );
    // A hard break's `\` is chrome at the end of the source line only,
    // as on both render surfaces.
    if (hardBreaks &&
        depth == 0 &&
        end == text.length &&
        MarkdownInlineGrammar.endsWithHardBreak(text, start, end, tokens)) {
      end--;
    }
    if (tokens.isEmpty) {
      out.write(text.substring(start, end));
      return;
    }

    var plainFrom = start;
    for (final token in tokens) {
      if (plainFrom < token.start) {
        out.write(text.substring(plainFrom, token.start));
      }
      plainFrom = token.end;
      switch (token) {
        case InlineGhost():
        case InlineComment():
          break;
        case InlineEscape():
          out.write(text.substring(token.charStart, token.end));
        case InlineEntity():
          out.write(token.decoded);
        case InlineCode():
          out.write(text.substring(token.innerStart, token.innerEnd));
        // An image reads as its alt text, the caption both render
        // surfaces show beside the picture glyph.
        case InlineLink():
          _inline(
            text,
            token.textStart,
            token.textEnd,
            out,
            palette,
            ghosts,
            depth + 1,
          );
        case InlineWikiLink():
          out.write(token.displayOf(text));
        case InlineAutolink():
          out.write(text.substring(token.innerStart, token.innerEnd));
        case InlineColor():
          _inline(
            text,
            token.innerStart,
            token.innerEnd,
            out,
            palette,
            ghosts,
            depth + 1,
          );
        case InlineEmphasis():
          _inline(
            text,
            token.contentStart,
            token.innerEnd,
            out,
            palette,
            ghosts,
            depth + 1,
          );
        case InlineTag():
        case InlineUrl():
          out.write(text.substring(token.start, token.end));
      }
    }
    if (plainFrom < end) out.write(text.substring(plainFrom, end));
  }
}
