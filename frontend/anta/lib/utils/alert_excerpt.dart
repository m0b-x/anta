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
/// at [kAlertExcerptMaxLength] with an ellipsis — the body a reminder and a
/// Missed notice expand to.
///
/// Pure, and a projection over the grammar modules rather than a scanner of
/// its own: the line shape says what a heading or a rule is, the list
/// grammar where an item's text starts, the money grammar what a ledger
/// line means, and the inline grammar which code units are chrome. Anything
/// the grammar does not name passes through as written.
String alertExcerptFor(String? description) {
  if (description == null || description.isEmpty) return '';
  for (final raw in description.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final plain = _plainLine(line);
    if (plain.isEmpty) continue;
    if (plain.length <= kAlertExcerptMaxLength) return plain;
    return '${plain.substring(0, kAlertExcerptMaxLength - 1).trimRight()}…';
  }
  return '';
}

String _plainLine(String line) {
  if (MarkdownLineShape.isHorizontalRule(line) ||
      MarkdownLineShape.isTableSeparator(line) ||
      MarkdownLineShape.isTableRow(line) ||
      MarkdownChunker.isFenceDelimiter(line)) {
    return '';
  }
  final money = MarkdownMoneySyntax.parse(line);
  if (money != null) return _plainMoney(line, money);
  var text = line;
  final callout = MarkdownCalloutSyntax.parseLead(text);
  if (callout != null) return _collapseSpaces(_plainInline(callout.title.trim()));
  final quote = MarkdownCalloutSyntax.quoteMarkers(text);
  if (quote != null) text = text.substring(quote.contentStart);
  final heading = MarkdownLineShape.headingAt(text);
  if (heading != null) text = text.substring(heading.contentStart);
  final item = MarkdownListSyntax.parse(text);
  if (item != null) text = item.content;
  return _collapseSpaces(_plainInline(text.trim()));
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

String _plainInline(String text) {
  final tokens = MarkdownInlineGrammar.tokenize(
    text,
    palette: MarkdownColorPalette.presets,
  );
  if (tokens.isEmpty) return text;
  final buffer = StringBuffer();
  var cursor = 0;
  for (final token in tokens) {
    if (token.start < cursor) continue;
    buffer.write(text.substring(cursor, token.start));
    buffer.write(_plainToken(text, token));
    cursor = token.end;
  }
  buffer.write(text.substring(cursor));
  return buffer.toString();
}

String _plainToken(String text, InlineToken token) => switch (token) {
  InlineEscape() => text.substring(token.start + 1, token.end),
  InlineGhost() => '',
  InlineCode() => text.substring(token.innerStart, token.innerEnd),
  InlineLink() => token.isImage
      ? ''
      : _plainInline(text.substring(token.textStart, token.textEnd)),
  InlineWikiLink() => text.substring(token.titleStart, token.titleEnd),
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
