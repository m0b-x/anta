import 'markdown_callout_syntax.dart';
import 'markdown_chunker.dart';
import 'markdown_color_syntax.dart';
import 'markdown_inline_grammar.dart';
import 'markdown_line_shape.dart';
import 'markdown_list_syntax.dart';
import 'markdown_money_syntax.dart';

/// How much of a description a notification body carries (OS-4).
const int kAlertExcerptMaxLength = 120;

/// The first non-empty line of an event description as plain text, capped
/// at [kAlertExcerptMaxLength] with an ellipsis — the line a notification
/// adds under its text when it is expanded, and the alarm page's second row.
///
/// Pure, and a projection over the grammar modules rather than a scanner of
/// its own: the line shape says what a heading or a rule is, the list
/// grammar where an item's text starts, the money grammar what a ledger
/// line means, and the inline grammar which code units are chrome. Anything
/// the grammar does not name passes through as written.
String alertExcerptFor(String? description) {
  if (description == null || description.isEmpty) return '';
  final lines = description.split('\n');
  var state = MarkdownChunker.outsideBlock;
  String? above;
  // A front matter is metadata: the excerpt starts under it.
  final body = MarkdownChunker.frontMatterEnd(lines.length, (i) => lines[i]);
  for (var i = body; i < lines.length; i++) {
    final raw = lines[i];
    final entry = state;
    state = MarkdownChunker.blockStateAfter(raw, state);
    // A fence's delimiters and a `%%` block comment never surface; a
    // fence's body reads as written.
    if (entry != state ||
        state == MarkdownChunker.insideComment ||
        entry == MarkdownChunker.insideComment) {
      above = null;
      continue;
    }
    // A setext underline is chrome, even under a text line that came out
    // empty (`%%note%%` above `===`).
    final prose = entry == MarkdownChunker.outsideBlock;
    final underline =
        prose &&
        above != null &&
        MarkdownLineShape.setextLevelOf(above, raw) > 0;
    above = prose ? raw : null;
    if (underline) continue;
    final line = raw.trim();
    if (line.isEmpty) continue;
    // A trailing `\` is a hard break only where the paragraph continues,
    // and never on a setext heading's text line. Only a line that ends in
    // one pays the paragraph test.
    final hardBreak =
        i + 1 < lines.length &&
        raw.endsWith(r'\') &&
        MarkdownChunker.continuesParagraph(
          raw,
          lines[i + 1],
          i + 2 < lines.length ? lines[i + 2] : null,
        ) &&
        MarkdownLineShape.setextLevelOf(raw, lines[i + 1]) == 0;
    final plain = _plainLine(line, hardBreak: hardBreak);
    if (plain.isEmpty) continue;
    if (plain.length <= kAlertExcerptMaxLength) return plain;
    // The cap counts code units, so the last one kept can be the lead half
    // of a pair — and a string that ends in half an emoji is not text: the
    // engine refuses it whole, and the alarm page would draw one replacement
    // character where the line should be.
    var cut = kAlertExcerptMaxLength - 1;
    final last = plain.codeUnitAt(cut - 1);
    if (last >= 0xD800 && last <= 0xDBFF) cut--;
    return '${plain.substring(0, cut).trimRight()}…';
  }
  return '';
}

String _plainLine(String line, {required bool hardBreak}) {
  if (MarkdownLineShape.isHorizontalRule(line) ||
      MarkdownLineShape.isTableSeparator(line) ||
      MarkdownLineShape.isTableRow(line)) {
    return '';
  }
  final money = MarkdownMoneySyntax.parse(line);
  if (money != null) return _plainMoney(line, money);
  var text = line;
  final callout = MarkdownCalloutSyntax.parseLead(text);
  if (callout != null) {
    return _collapseSpaces(_plainInline(callout.title.trim()));
  }
  final quote = MarkdownCalloutSyntax.quoteMarkers(text);
  if (quote != null) text = text.substring(quote.contentStart);
  final heading = MarkdownLineShape.headingAt(text);
  if (heading != null) {
    text = text.substring(heading.contentStart, heading.contentEnd);
  }
  final item = MarkdownListSyntax.parse(text);
  if (item != null) {
    // A custom state keeps its box as typed, as MarkdownPlainText does, so
    // a cancelled `[-]` task does not read as a live one; the box skips the
    // inline grammar, which would read a `*` or a `\` state as markup.
    if (item.kind == MarkdownListKind.task &&
        !item.checked &&
        item.state != ' ') {
      final box = text.substring(item.bracketStart, item.bracketStart + 3);
      final rest = _plainInline(
        item.content.trim(),
        hardBreak: hardBreak && heading == null,
      );
      return _collapseSpaces(rest.isEmpty ? box : '$box $rest');
    }
    text = item.content;
  }
  // A heading keeps a trailing `\` as text, as every surface does.
  return _collapseSpaces(
    _plainInline(text.trim(), hardBreak: hardBreak && heading == null),
  );
}

/// A ledger line reads as its amount, signed for an add or a subtract, and
/// its label, in the order the row itself renders them.
String _plainMoney(String line, MoneyLineMatch money) {
  final amount = line.substring(money.amountStart, money.amountEnd);
  final label = money.labelStart < line.length
      ? line.substring(money.labelStart, money.labelEnd).trim()
      : '';
  final sign = switch (money.kind) {
    MoneyLineKind.add => '+',
    MoneyLineKind.subtract => '−',
    _ => '',
  };
  final value = amount.isEmpty ? '' : '$sign$amount';
  final labelFirst = money.labelStart < money.amountStart;
  final parts = labelFirst ? [label, value] : [value, label];
  return parts.where((part) => part.isNotEmpty).join(' ');
}

/// [hardBreak] drops a line-ending hard-break `\`, as MarkdownPlainText
/// does at the end of a source line; nested ranges, a heading and a
/// callout title keep it.
String _plainInline(String text, {bool hardBreak = false}) {
  final tokens = MarkdownInlineGrammar.tokenize(
    text,
    palette: MarkdownColorPalette.presets,
  );
  final end =
      hardBreak &&
          MarkdownInlineGrammar.endsWithHardBreak(text, 0, text.length, tokens)
      ? text.length - 1
      : text.length;
  if (tokens.isEmpty) return text.substring(0, end);
  final buffer = StringBuffer();
  var cursor = 0;
  for (final token in tokens) {
    if (token.start < cursor) continue;
    buffer.write(text.substring(cursor, token.start));
    buffer.write(_plainToken(text, token));
    cursor = token.end;
  }
  if (cursor < end) buffer.write(text.substring(cursor, end));
  return buffer.toString();
}

String _plainToken(String text, InlineToken token) => switch (token) {
  InlineEscape() => text.substring(token.start + 1, token.end),
  InlineEntity() => token.decoded,
  InlineGhost() => '',
  InlineComment() => '',
  InlineCode() => text.substring(token.innerStart, token.innerEnd),
  // An image reads as its alt text, as MarkdownPlainText prints it.
  InlineLink() => _plainInline(text.substring(token.textStart, token.textEnd)),
  InlineWikiLink() => token.displayOf(text),
  InlineAutolink() => text.substring(token.innerStart, token.innerEnd),
  InlineColor() => _plainInline(
    text.substring(token.innerStart, token.innerEnd),
  ),
  InlineTag() => text.substring(token.start, token.end),
  InlineUrl() => text.substring(token.start, token.end),
  InlineEmphasis() => _plainInline(
    text.substring(token.contentStart, token.innerEnd),
  ),
};

String _collapseSpaces(String text) {
  final buffer = StringBuffer();
  var pendingSpace = false;
  for (final rune in text.runes) {
    final isSpace = rune == 0x20 || rune == 0x09;
    if (isSpace) {
      pendingSpace = buffer.isNotEmpty;
      continue;
    }
    if (pendingSpace) buffer.write(' ');
    pendingSpace = false;
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}
