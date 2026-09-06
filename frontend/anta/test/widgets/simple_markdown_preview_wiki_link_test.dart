import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/widgets/simple_markdown_preview.dart';

/// `[[note]]` in [SimpleMarkdownPreview], the read-only surface the event
/// sheet and the shortcut editor render descriptions through.
///
/// The preview caches its `LineBasedMarkdownBuilder` and rebuilds it only
/// when something the builder read at construction changed, and
/// `onWikiLinkTap` is one of those things: the builder allocates a
/// recognizer per `[[note]]` only when that callback was non-null when it
/// was made. Every host here wires the callback *after* its first frame —
/// the sheet reads it off `widget`, the editor page resolves it from a
/// setting — so a rebuild check that ignored it would leave the titles
/// rendered but inert against unchanged data, which looks exactly like a
/// link that does not work. The cases below pin the null-ness comparison
/// in both directions and the rendering that is there either way.
void main() {
  const source = 'see [[a]] now';

  /// Pumps the preview over [source], with the wiki-link callback wired or
  /// not. Deliberately the same `MaterialApp` shape every time — same data,
  /// same theme brightness, same (default) money config and palette — so a
  /// second pump differs from the first in exactly one thing, and a rebuild
  /// can only be attributed to the callback.
  Future<void> pumpPreview(
    WidgetTester tester,
    void Function(String title)? onTapWikiLink,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: Scaffold(
          body: SimpleMarkdownPreview(
            data: source,
            onTapWikiLink: onTapWikiLink,
          ),
        ),
      ),
    );
  }

  /// The preview's rendered rich text.
  RichText previewText(WidgetTester tester) => tester.widget<RichText>(
    find.descendant(
      of: find.byType(SimpleMarkdownPreview),
      matching: find.byType(RichText),
    ),
  );

  /// The single leaf span of the rendered text whose text is exactly [text].
  /// The recognizer is attached to every node of the wrapped subtree, so the
  /// leaf carries it.
  TextSpan leafReading(WidgetTester tester, String text) {
    final found = <TextSpan>[];
    previewText(tester).text.visitChildren((span) {
      if (span is TextSpan && span.text == text) found.add(span);
      return true;
    });
    return found.single;
  }

  testWidgets('a callback wired after the first frame makes the title '
      'tappable', (tester) async {
    await pumpPreview(tester, null);

    expect(
      leafReading(tester, 'a').recognizer,
      isNull,
      reason: 'the first build had nothing to wire a recognizer to',
    );

    final tapped = <String>[];
    await pumpPreview(tester, tapped.add);

    final recognizer = leafReading(tester, 'a').recognizer;
    expect(
      recognizer,
      isA<TapGestureRecognizer>(),
      reason: 'the cached builder has to be discarded, not reused',
    );
    (recognizer! as TapGestureRecognizer).onTap!();

    expect(tapped, ['a'], reason: 'the raw title between the brackets');
  });

  testWidgets('and unwiring it makes the title inert again', (tester) async {
    // The other direction of the same comparison: the flag tracks null-ness,
    // so a host that drops the callback (the setting turned off) gets a
    // builder that allocates no recognizers, not one that keeps the old ones.
    await pumpPreview(tester, (_) {});
    expect(leafReading(tester, 'a').recognizer, isNotNull);

    await pumpPreview(tester, null);

    expect(leafReading(tester, 'a').recognizer, isNull);
  });

  testWidgets('the brackets are dropped and the title renders as a link', (
    tester,
  ) async {
    // True whether or not the link is wired: an unwired `[[note]]` still
    // reads as a note name rather than as literal punctuation.
    await pumpPreview(tester, null);

    expect(
      previewText(tester).text.toPlainText(includePlaceholders: false),
      'see a now',
    );
    expect(find.textContaining('[[', findRichText: true), findsNothing);

    final style = leafReading(tester, 'a').style!;
    final theme = Theme.of(tester.element(find.byType(SimpleMarkdownPreview)));
    expect(style.decoration, TextDecoration.underline);
    expect(style.color, theme.colorScheme.primary);
  });
}
