import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/utils/settings_search.dart';
import 'package:anta/widgets/settings_section_list.dart';

/// Folding a settings section hides rows, so the two ways it could go wrong
/// both cost the user something they were looking for: a fold that survives a
/// search swallows the hit, and a fold that is not really a fold keeps
/// building the previews and sliders it claims to have put away.
void main() {
  SettingsEntry entry(String title) => SettingsEntry(
    title: title,
    builder: (context, titleWidget, description) =>
        ListTile(title: titleWidget),
  );

  final sections = [
    SettingsSectionData(
      id: 'appearance',
      icon: Icons.palette_rounded,
      title: 'Appearance',
      intro: const Text('preview strip'),
      entries: [entry('Today style'), entry('Accent color')],
    ),
    SettingsSectionData(
      id: 'events',
      icon: Icons.event_note_rounded,
      title: 'Events',
      entries: [entry('Description limit')],
    ),
  ];

  Future<Set<String>> pump(
    WidgetTester tester, {
    Set<String> collapsed = const {},
    String query = '',
    bool foldable = true,
  }) async {
    final state = {...collapsed};
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SettingsSectionList(
              sections: sections,
              query: SettingsQuery.parse(query),
              collapsedSections: state,
              onToggleSection: foldable
                  ? (id) => setState(
                      () => state.contains(id)
                          ? state.remove(id)
                          : state.add(id),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
    return state;
  }

  group('folding', () {
    testWidgets('an open section shows its rows and its intro', (tester) async {
      await pump(tester);

      expect(find.text('Today style'), findsOneWidget);
      expect(find.text('Accent color'), findsOneWidget);
      expect(find.text('preview strip'), findsOneWidget);
      expect(find.text('2 options'), findsNothing);
    });

    testWidgets('a folded section builds neither rows nor intro', (
      tester,
    ) async {
      await pump(tester, collapsed: {'appearance'});

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Today style'), findsNothing);
      expect(find.text('preview strip'), findsNothing);
      // The other section is untouched — folds are per-section.
      expect(find.text('Description limit'), findsOneWidget);
    });

    testWidgets('a folded header says how much it is hiding', (tester) async {
      await pump(tester, collapsed: {'appearance', 'events'});

      expect(find.text('2 options'), findsOneWidget);
      expect(find.text('1 option'), findsOneWidget);
    });

    testWidgets('tapping the header reports the section id and folds it', (
      tester,
    ) async {
      final state = await pump(tester);

      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();

      expect(state, {'appearance'});
      expect(find.text('Today style'), findsNothing);

      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();

      expect(state, isEmpty);
      expect(find.text('Today style'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('a fold never swallows a search hit', (tester) async {
      await pump(tester, collapsed: {'appearance'}, query: 'accent');

      expect(find.text('Accent color'), findsOneWidget);
      // Non-matching rows are filtered as usual, not revealed by the unfold.
      expect(find.text('Today style'), findsNothing);
    });

    testWidgets('the chevron is gone while filtering', (tester) async {
      await pump(tester, query: 'accent');

      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
    });

    testWidgets('clearing the query restores the fold', (tester) async {
      await pump(tester, collapsed: {'appearance'}, query: 'accent');
      expect(find.text('Accent color'), findsOneWidget);

      await pump(tester, collapsed: {'appearance'});
      expect(find.text('Accent color'), findsNothing);
    });
  });

  group('pages that never asked for folding', () {
    testWidgets('render every row and no chevron', (tester) async {
      await pump(tester, collapsed: {'appearance'}, foldable: false);

      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
      expect(find.text('Today style'), findsOneWidget);
      expect(find.text('preview strip'), findsOneWidget);
    });

    testWidgets('a section without an id cannot fold', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SettingsSectionList(
              sections: [
                SettingsSectionData(
                  icon: Icons.event_note_rounded,
                  title: 'Events',
                  entries: [entry('Description limit')],
                ),
              ],
              query: SettingsQuery.empty,
              onToggleSection: (_) => fail('a section with no id cannot fold'),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
      expect(find.text('Description limit'), findsOneWidget);
    });
  });
}
