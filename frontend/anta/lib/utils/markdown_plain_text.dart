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
/// [MarkdownLineShape], [MarkdownChunker.isFenceDelimiter],
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

  /// `|`, the table cell separator.
  static const int _pipe = 0x7C;

  /// The plain text of [content], collapsed onto one line and capped at
  /// [maxLength] with a trailing ellipsis.
  ///
  /// Blank lines, fence delimiters and fenced bodies, horizontal rules
  /// and table separators contribute nothing; every other line is
  /// unwrapped to its content and appended in source order, so the first
  /// meaningful line leads. A note whose every line strips to nothing
  /// (a lone `---`, a fenced-only note) falls back to the raw whitespace
  /// collapse, so a non-empty note never previews blank.
  static String strip(
    String content, {
    MarkdownColorPalette palette = MarkdownColorPalette.presets,
    int maxLength = 200,
  }) {
    if (content.isEmpty) return '';

    final out = StringBuffer();
    final lines = const LineSplitter().convert(content);
    var inFence = false;
    for (final line in lines) {
      if (MarkdownChunker.isFenceDelimiter(line)) {
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;
      final before = out.length;
      _line(line, out, palette, 0);
      if (out.length > before) out.write(' ');
    }

    final collapsed = _collapse(out.toString());
    final text = collapsed.isEmpty ? _collapse(content) : collapsed;
    return _cap(text, maxLength);
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
  ) {
    if (line.trim().isEmpty) return;
    if (MarkdownLineShape.isHorizontalRule(line)) return;
    if (MarkdownLineShape.isTableSeparator(line)) return;

    final ghosts = GhostText.mightContain(line)
        ? GhostText.findGhosts(line)
        : const <GhostMatch>[];

    final lead = MarkdownCalloutSyntax.parseLead(line);
    if (lead != null) {
      out.write(MarkdownCalloutSyntax.labelFor(lead.type));
      if (lead.title.isNotEmpty) {
        out.write(' ');
        _inline(line, lead.titleStart, line.length, out, palette, ghosts, 0);
      }
      return;
    }

    final quote = MarkdownCalloutSyntax.quoteMarkers(line);
    if (quote != null) {
      if (depth < _maxBlockDepth) {
        _line(line.substring(quote.contentStart), out, palette, depth + 1);
      } else {
        _inline(line, quote.contentStart, line.length, out, palette, ghosts, 0);
      }
      return;
    }

    if (MarkdownMoneySyntax.leadsWithMoney(line)) {
      final match = MarkdownMoneySyntax.parse(line);
      if (match != null) {
        _moneyRow(line, match, out, palette, ghosts);
        return;
      }
    }

    final heading = MarkdownLineShape.headingAt(line);
    if (heading != null) {
      _inline(line, heading.contentStart, line.length, out, palette, ghosts, 0);
      return;
    }

    final item = MarkdownListSyntax.parse(line);
    if (item != null) {
      if (item.kind == MarkdownListKind.task && item.checked) out.write('✓ ');
      _inline(line, item.contentStart, line.length, out, palette, ghosts, 0);
      return;
    }

    if (MarkdownLineShape.isTableRow(line)) {
      _tableRow(line, out, palette, ghosts);
      return;
    }

    _inline(line, 0, line.length, out, palette, ghosts, 0);
  }

  /// Cells of a `| a | b |` row joined with a middot. The row shape is
  /// [MarkdownLineShape.isTableRow]'s, so the outer pipes always exist
  /// and only the inner ones split.
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
    for (var i = from; i <= last; i++) {
      if (i != last && line.codeUnitAt(i) != _pipe) continue;
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

    if (match.labelStart < match.amountStart) {
      _spaced(out, () {
        _inline(line, match.labelStart, labelEnd, out, palette, ghosts, 0);
      });
      if (amount.isNotEmpty) _spaced(out, () => out.write(amount));
      _spaced(out, () {
        _inline(line, match.amountEnd, contentEnd, out, palette, ghosts, 0);
      });
      return;
    }

    if (amount.isNotEmpty) _spaced(out, () => out.write(amount));
    _spaced(out, () {
      _inline(line, match.labelStart, labelEnd, out, palette, ghosts, 0);
    });
  }

  static void _spaced(StringBuffer out, void Function() write) {
    final before = out.length;
    write();
    if (out.length > before) out.write(' ');
  }

  /// Emits `[start, end)` with every inline marker dropped, walking the
  /// tokens [MarkdownInlineGrammar.tokenize] reports and recursing into
  /// the ranges it declares nested.
  static void _inline(
    String text,
    int start,
    int end,
    StringBuffer out,
    MarkdownColorPalette palette,
    List<GhostMatch> ghosts,
    int depth,
  ) {
    if (start >= end) return;
    final tokens = MarkdownInlineGrammar.tokenize(
      text,
      start: start,
      end: end,
      ghosts: ghosts,
      palette: palette,
      depth: depth,
    );
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
          break;
        case InlineEscape():
          out.write(text.substring(token.charStart, token.end));
        case InlineCode():
          out.write(text.substring(token.innerStart, token.innerEnd));
        case InlineLink():
          if (!token.isImage) {
            _inline(
              text,
              token.textStart,
              token.textEnd,
              out,
              palette,
              ghosts,
              depth + 1,
            );
          }
        case InlineWikiLink():
          out.write(token.titleOf(text));
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
