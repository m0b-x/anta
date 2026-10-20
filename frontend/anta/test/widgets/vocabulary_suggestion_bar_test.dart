import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/controllers/vocabulary_suggestion_controller.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';
import 'package:anta/models/utility_button_config.dart';
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

  // Two lists, so every pill draws its second line, and a scope label —
  // the tallest the bar ever gets.
  final session = VocabularySuggestionSession(
    lineIndex: 0,
    start: 0,
    end: 2,
    suggestions: [
      candidate('Bench press', 'Exercises'),
      candidate('Bent-over row', 'Back day'),
    ],
    scopeNames: const ['Exercises'],
  );

  Future<VocabularySuggestionController> pumpBar(
    WidgetTester tester, {
    required double textScale,
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
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VocabularySuggestionBar(
            session: session,
            onAccept: (candidate) => accepted.add(candidate.term),
            onDismiss: () => dismissed++,
          ),
        ),
      ),
    );

    final en = lookupAppLocalizations(const Locale('en'));
    expect(
      tester.getSemantics(find.byTooltip(en.vocabularySuggestionsDismiss)),
      isSemantics(isButton: true, hasTapAction: true),
    );
    final pill = find.ancestor(
      of: find.text('Bench press'),
      matching: find.byType(Semantics),
    );
    expect(
      tester.getSemantics(pill.first),
      isSemantics(isButton: true, hasTapAction: true),
    );

    await tester.tap(find.text('Bench press'));
    await tester.tap(find.byTooltip(en.vocabularySuggestionsDismiss));
    expect(accepted, ['Bench press']);
    expect(dismissed, 1);
    semantics.dispose();
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets('opening and closing a session never moves the editor at '
        '${textScale}x', (tester) async {
      final suggestions = await pumpBar(tester, textScale: textScale);
      final normal = barHeight(tester);

      suggestions.value = session;
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

  testWidgets('text scale 2.0 leaves both rows at their 1.0 height', (
    tester,
  ) async {
    await pumpBar(tester, textScale: 1.0);
    final atOne = barHeight(tester);

    final suggestions = await pumpBar(tester, textScale: 2.0);
    expect(barHeight(tester), atOne);

    suggestions.value = session;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(barHeight(tester), atOne);
    expect(find.text('Bench press'), findsOneWidget);
  });
}
