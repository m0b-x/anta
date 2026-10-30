import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/markdown_bar_metrics.dart';
import 'package:anta/controllers/vocabulary_suggestion_controller.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';
import 'package:anta/models/utility_button_config.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/vocabulary_matcher.dart';
import 'package:anta/widgets/markdown_bar.dart';
import 'package:anta/widgets/vocabulary_suggestion_bar.dart';

/// E28 — the suggestion bar takes the markdown bar's place while a
/// vocabulary session is open. The two must be one height at every text
/// scale, or the editor jumps each time a session opens or closes.
void main() {
  VocabularyCandidate candidate(String term, String list) =>
      VocabularyCandidate(
        term: term,
        foldedTerm: term.toLowerCase(),
        vocabularyId: list,
        vocabularyName: list,
        vocabularySortOrder: 0,
        itemSortOrder: 0,
      );

  // A two-list scope, so every pill draws its second line — the tallest a
  // pill gets — and no scope label leads the strip.
  final session = VocabularySuggestionSession(
    lineIndex: 0,
    start: 0,
    end: 2,
    suggestions: [
      candidate('Bench press', 'Exercises'),
      candidate('Bent-over row', 'Back day'),
    ],
    scopeNames: const ['Exercises', 'Back day'],
  );

  // A one-list scope, so the pills keep one line and the scope leads the
  // strip.
  final scopedSession = VocabularySuggestionSession(
    lineIndex: 0,
    start: 0,
    end: 2,
    suggestions: [
      candidate('Bench press', 'Exercises'),
      candidate('Bent-over row', 'Exercises'),
    ],
    scopeNames: const ['Exercises'],
  );

  // A two-list scope whose matches have narrowed to one list: the label
  // follows the typed scope, so it stays away here too.
  final narrowedSession = VocabularySuggestionSession(
    lineIndex: 0,
    start: 0,
    end: 2,
    suggestions: scopedSession.suggestions,
    scopeNames: const ['Exercises', 'Back day'],
  );

  final unscopedSession = VocabularySuggestionSession(
    lineIndex: 0,
    start: 0,
    end: 2,
    suggestions: scopedSession.suggestions,
  );

  Finder pillBody(String term) =>
      find.ancestor(of: find.text(term), matching: find.byType(Material)).first;

  // The pill's own button node: the one container between its term and
  // the bar.
  Finder pillNode(String term) => find.ancestor(
    of: find.text(term),
    matching: find.descendant(
      of: find.byType(VocabularySuggestionBar),
      matching: find.byWidgetPredicate((w) => w is Semantics && w.container),
    ),
  );

  Future<void> pumpBare(
    WidgetTester tester,
    VocabularySuggestionSession session, {
    ValueChanged<VocabularyCandidate>? onAccept,
    VoidCallback? onDismiss,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: VocabularySuggestionBar(
          session: session,
          onAccept: onAccept ?? (_) {},
          onDismiss: onDismiss ?? () {},
        ),
      ),
    ),
  );

  Future<VocabularySuggestionController> pumpBar(
    WidgetTester tester, {
    required double textScale,
    MarkdownColorPalette? palette,
  }) async {
    final editor = CodeLineEditingController.fromText('be');
    addTearDown(editor.dispose);
    final suggestions = VocabularySuggestionController(
      controller: editor,
      onInsert: (_) {},
      candidateSource: () => const [],
    );
    addTearDown(suggestions.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              MarkdownBar(
                shortcuts: const [
                  CustomMarkdownShortcut(
                    id: 'default_bold',
                    label: 'Bold',
                    iconCodePoint: 0xe238,
                    iconFontFamily: 'MaterialIcons',
                    beforeText: '**',
                    afterText: '**',
                    isDefault: true,
                  ),
                  CustomMarkdownShortcut(
                    id: 'default_header',
                    label: 'Headers',
                    iconCodePoint: 0xe167,
                    iconFontFamily: 'MaterialIcons',
                    beforeText: '# ',
                    afterText: '',
                    isDefault: true,
                    insertType: 'header',
                  ),
                ],
                isPreviewMode: false,
                canUndo: false,
                canRedo: false,
                previewFontSize: 14,
                onUndo: () {},
                onRedo: () {},
                onDecreaseFontSize: () {},
                onIncreaseFontSize: () {},
                onSettings: () {},
                onShortcutPressed: (_) {},
                utilityConfigs: const [
                  UtilityButtonConfig(id: UtilityButtonId.undo),
                  UtilityButtonConfig(id: UtilityButtonId.settings),
                ],
                suggestions: suggestions,
                suggestionPalette: palette,
              ),
            ],
          ),
        ),
      ),
    );
    return suggestions;
  }

  double barHeight(WidgetTester tester) =>
      tester.getSize(find.byType(MarkdownBar)).height;

  testWidgets('the pills and the dismiss button are buttons to a screen '
      'reader, as the bar buttons they stand in for are (U1.8)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final accepted = <String>[];
    var dismissed = 0;
    await pumpBare(
      tester,
      session,
      onAccept: (candidate) => accepted.add(candidate.term),
      onDismiss: () => dismissed++,
    );

    final en = lookupAppLocalizations(const Locale('en'));
    expect(
      tester.getSemantics(find.byTooltip(en.vocabularySuggestionsDismiss)),
      isSemantics(isButton: true, hasTapAction: true),
    );
    // One node per pill: the bar adds no container between the term and
    // the pill's own button node, which reads the term and its list.
    final pill = pillNode('Bench press');
    expect(pill, findsOneWidget);
    final node = tester.getSemantics(pill);
    expect(node, isSemantics(isButton: true, hasTapAction: true));
    expect(node.label, contains('Bench press'));
    expect(node.label, contains('Exercises'));

    await tester.tap(find.text('Bench press'));
    await tester.tap(find.byTooltip(en.vocabularySuggestionsDismiss));
    expect(accepted, ['Bench press']);
    expect(dismissed, 1);
    semantics.dispose();
  });

  for (final textScale in [1.0, 1.3, 2.0]) {
    for (final (name, fixture) in [
      ('two lists', session),
      ('one scoped list', scopedSession),
    ]) {
      testWidgets('opening and closing a session ($name) never moves the '
          'editor at ${textScale}x', (tester) async {
        final suggestions = await pumpBar(tester, textScale: textScale);
        final normal = barHeight(tester);

        suggestions.value = fixture;
        await tester.pump();
        expect(find.byType(VocabularySuggestionBar), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(barHeight(tester), normal);

        suggestions.value = null;
        await tester.pump();
        expect(find.byType(VocabularySuggestionBar), findsNothing);
        expect(barHeight(tester), normal);
      });
    }
  }

  testWidgets('only a single-list scope leads the strip, so the label never '
      'comes and goes while typing', (tester) async {
    final suggestions = await pumpBar(tester, textScale: 1.0);
    final glyph = find.byIcon(Icons.format_list_bulleted_rounded);

    suggestions.value = scopedSession;
    await tester.pump();
    expect(glyph, findsOneWidget);
    expect(find.text('Exercises'), findsOneWidget);
    // The label's glyph is a prefix to 14 sp text, so it kept 20 dp when the
    // bar's buttons went to 24; the dismiss ✕ is a bar button and follows.
    expect(
      tester.widget<Icon>(glyph).size,
      MarkdownBarMetrics.suggestionScopeGlyphSize,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.close)).size,
      MarkdownBarMetrics.glyphSize,
    );

    // Each pill's second line names its list; no label repeats it.
    suggestions.value = session;
    await tester.pump();
    expect(glyph, findsNothing);
    expect(find.text('Exercises'), findsOneWidget);
    expect(find.text('Back day'), findsOneWidget);

    // The same two-list scope, its matches narrowed to one list.
    suggestions.value = narrowedSession;
    await tester.pump();
    expect(glyph, findsNothing);
    expect(find.text('Exercises'), findsNothing);

    suggestions.value = unscopedSession;
    await tester.pump();
    expect(glyph, findsNothing);
  });

  testWidgets('a long scope name ellipsizes inside its share of the strip', (
    tester,
  ) async {
    const longName = 'Upper body accessory exercises';
    await pumpBare(
      tester,
      VocabularySuggestionSession(
        lineIndex: 0,
        start: 0,
        end: 2,
        suggestions: [candidate('Bench press', longName)],
        scopeNames: const [longName],
      ),
    );

    final strip = find.descendant(
      of: find.byType(VocabularySuggestionBar),
      matching: find.byType(MarkdownBarEdgeFade),
    );
    expect(strip, findsOneWidget);
    final label = find.text(longName);
    expect(
      tester.getSize(label).width,
      lessThanOrEqualTo(
        tester.getSize(strip).width *
            MarkdownBarMetrics.suggestionScopeMaxShare,
      ),
    );
    final text = tester.widget<Text>(label);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(
      tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
      isTrue,
    );
  });

  testWidgets('a pill body is a chip inside the row\'s tap target', (
    tester,
  ) async {
    final suggestions = await pumpBar(tester, textScale: 1.0);
    suggestions.value = scopedSession;
    await tester.pump();
    expect(
      tester.getSize(pillBody('Bench press')).height,
      MarkdownBarMetrics.suggestionPillMinHeight,
    );

    final scaled = await pumpBar(tester, textScale: 2.0);
    scaled.value = session;
    await tester.pump();
    expect(tester.takeException(), isNull);
    final twoLines = tester.getSize(pillBody('Bench press')).height;
    expect(twoLines, greaterThan(MarkdownBarMetrics.suggestionPillMinHeight));
    expect(twoLines, lessThanOrEqualTo(MarkdownBar.rowHeight));
  });

  testWidgets('the band around a pill body still accepts the pill', (
    tester,
  ) async {
    final accepted = <String>[];
    await pumpBare(
      tester,
      scopedSession,
      onAccept: (candidate) => accepted.add(candidate.term),
    );

    expect(
      tester.getSize(pillNode('Bench press')).height,
      MarkdownBar.rowHeight,
    );
    await tester.tapAt(
      tester.getTopLeft(pillBody('Bench press')) + const Offset(8, -2),
    );
    expect(accepted, ['Bench press']);
  });

  testWidgets('the strip ends on its side padding, as it starts', (
    tester,
  ) async {
    await pumpBare(tester, unscopedSession);

    final content = find
        .descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Padding),
        )
        .first;
    final first = tester.getRect(pillBody('Bench press'));
    final last = tester.getRect(pillBody('Bent-over row'));
    expect(
      first.left - tester.getTopLeft(content).dx,
      MarkdownBarMetrics.sidePadding,
    );
    expect(last.left - first.right, MarkdownBarMetrics.suggestionPillGap);
    expect(
      tester.getTopRight(content).dx - last.right,
      MarkdownBarMetrics.sidePadding,
    );
  });

  // Y5: a session notifies on every keystroke; the hidden normal bar is
  // built once per bar build, so only the pills follow the typing.
  testWidgets('session keystrokes rebuild the pills, not the normal bar', (
    tester,
  ) async {
    final suggestions = await pumpBar(tester, textScale: 1.0);
    suggestions.value = session;
    await tester.pump();

    MarkdownBar.debugNormalModeBuildCount = 0;
    for (var end = 3; end <= 5; end++) {
      suggestions.value = VocabularySuggestionSession(
        lineIndex: 0,
        start: 0,
        end: end,
        suggestions: session.suggestions,
        scopeNames: session.scopeNames,
      );
      await tester.pump();
    }

    expect(find.byType(VocabularySuggestionBar), findsOneWidget);
    expect(MarkdownBar.debugNormalModeBuildCount, 0);
  });

  for (final textScale in [1.3, 2.0]) {
    testWidgets('text scale $textScale leaves both rows at their 1.0 height', (
      tester,
    ) async {
      await pumpBar(tester, textScale: 1.0);
      final atOne = barHeight(tester);

      final suggestions = await pumpBar(tester, textScale: textScale);
      expect(barHeight(tester), atOne);

      suggestions.value = session;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(barHeight(tester), atOne);
      expect(find.text('Bench press'), findsOneWidget);
    });
  }

  // A pill previews its term as the live editor will render it; a heading
  // keeps the pill's size and shows its level instead.
  final markdownSession = VocabularySuggestionSession(
    lineIndex: 0,
    start: 0,
    end: 2,
    suggestions: [
      candidate('# Bench', 'Exercises'),
      candidate('**Row**', 'Back day'),
    ],
    scopeNames: const ['Exercises'],
    atLineStart: true,
  );

  testWidgets('with a palette the pills render their markdown', (tester) async {
    final semantics = tester.ensureSemantics();
    final suggestions = await pumpBar(
      tester,
      textScale: 1.0,
      palette: MarkdownColorPalette.presets,
    );
    suggestions.value = markdownSession;
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('H1'), findsOneWidget);
    expect(find.text('# Bench'), findsNothing);
    expect(find.text('**Row**'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Heading 1')), findsOneWidget);
    expect(
      tester.getSemantics(
        find
            .ancestor(of: find.text('Bench'), matching: find.byType(Semantics))
            .first,
      ),
      isSemantics(isButton: true, hasTapAction: true),
    );

    var bold = false;
    tester.widget<Text>(find.text('**Row**')).textSpan!.visitChildren((span) {
      if (span is TextSpan &&
          span.text == 'Row' &&
          span.style?.fontWeight == FontWeight.bold) {
        bold = true;
      }
      return !bold;
    });
    expect(bold, isTrue);
    semantics.dispose();
  });

  testWidgets('a heading term mid-line keeps its hashes', (tester) async {
    final suggestions = await pumpBar(
      tester,
      textScale: 1.0,
      palette: MarkdownColorPalette.presets,
    );
    suggestions.value = VocabularySuggestionSession(
      lineIndex: 0,
      start: 4,
      end: 7,
      suggestions: markdownSession.suggestions,
      scopeNames: markdownSession.scopeNames,
    );
    await tester.pump();

    expect(find.text('# Bench'), findsOneWidget);
    expect(find.text('H1'), findsNothing);
  });

  testWidgets('without a palette the pills stay raw', (tester) async {
    final suggestions = await pumpBar(tester, textScale: 1.0);
    suggestions.value = markdownSession;
    await tester.pump();

    expect(find.text('# Bench'), findsOneWidget);
    expect(find.text('**Row**'), findsOneWidget);
    expect(find.text('H1'), findsNothing);
  });

  for (final textScale in [1.0, 1.3, 2.0]) {
    testWidgets('heading pills never move the editor at ${textScale}x', (
      tester,
    ) async {
      final suggestions = await pumpBar(
        tester,
        textScale: textScale,
        palette: MarkdownColorPalette.presets,
      );
      final normal = barHeight(tester);

      suggestions.value = markdownSession;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('H1'), findsOneWidget);
      expect(barHeight(tester), normal);
      expect(
        tester.getSize(pillBody('Bench')).height,
        lessThanOrEqualTo(MarkdownBar.rowHeight),
      );
    });
  }
}
