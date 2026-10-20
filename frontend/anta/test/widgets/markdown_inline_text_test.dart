import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/widgets/markdown_inline_text.dart';

/// The row renderer spends its three-line budget before the builder sees
/// the text, so a `%%` block comment has to be dropped there: the builder
/// draws every comment line as a spacer, and a description that opens with
/// one would otherwise show a blank row with its real text clamped away.
void main() {
  Future<String?> rowText(WidgetTester tester, String data) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MarkdownInlineText(data: data)),
      ),
    );
    final finder = find.byType(RichText);
    if (finder.evaluate().isEmpty) return null;
    return tester.widget<RichText>(finder.first).text.toPlainText();
  }

  testWidgets('a leading block comment leaves the budget to the text', (
    tester,
  ) async {
    final text = await rowText(tester, '%%\nprivate\n%%\nLeg day');
    expect(text, 'Leg day');
  });

  testWidgets('a description that is only a comment renders nothing', (
    tester,
  ) async {
    expect(await rowText(tester, '%%\nprivate\n%%'), isNull);
    expect(await rowText(tester, '%%\nunclosed to the end'), isNull);
  });

  testWidgets('a %% line inside a fence is code, never a comment', (
    tester,
  ) async {
    final text = await rowText(tester, 'Set\n```\n%%');
    expect(text, contains('Set'));
    expect(text, contains('%%'));
  });

  testWidgets('a dropped blank line never makes a setext heading', (
    tester,
  ) async {
    final pair = await rowText(tester, 'Notes\n---\nmore');
    final apart = await rowText(tester, 'Notes\n\n---\nmore');
    final commented = await rowText(tester, 'Notes\n%%\nx\n%%\n===');
    final shown = await rowText(tester, 'Notes\n===');

    expect(apart, contains('Notes'));
    expect(apart, isNot(pair), reason: 'a paragraph and a rule, as written');
    expect(commented, isNot(shown));
  });

  // C1 fix pass P4 — a front matter is metadata, dropped before the budget
  // as the alert excerpt drops it, so the row shows the text under it.
  testWidgets('a front matter leaves the budget to the text below it', (
    tester,
  ) async {
    expect(await rowText(tester, '---\ntitle: x\n---\nReal text'), 'Real text');
  });
}
