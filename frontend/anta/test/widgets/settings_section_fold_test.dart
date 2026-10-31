import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
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
                      () =>
                          state.contains(id) ? state.remove(id) : state.add(id),
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

      expect(find.text('APPEARANCE'), findsOneWidget);
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

      await tester.tap(find.text('APPEARANCE'));
      await tester.pumpAndSettle();

      expect(state, {'appearance'});
      expect(find.text('Today style'), findsNothing);

      await tester.tap(find.text('APPEARANCE'));
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

  group('the browser\'s look', () {
    testWidgets('a header is a level-2 heading named as written, never the '
        'shouted label', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      // Both marks: Android reads the level alone, VoiceOver the flag alone.
      final folding = tester
          .getSemantics(find.text('APPEARANCE'))
          .getSemanticsData();
      expect(folding.headingLevel, 2);
      expect(folding.flagsCollection.isHeader, isTrue);
      expect(folding.label, 'Appearance');
      expect(folding.flagsCollection.isButton, isTrue);

      await pump(tester, foldable: false);
      final plain = tester.getSemantics(find.text('EVENTS')).getSemanticsData();
      expect(plain.headingLevel, 2);
      expect(plain.flagsCollection.isHeader, isTrue);
      expect(plain.label, 'Events');
      expect(plain.flagsCollection.isButton, isFalse);
      handle.dispose();
    });

    testWidgets('a header that cannot fold is the box a folding one is, its '
        'label on the same line, so the air after a group is one number', (
      tester,
    ) async {
      Finder box(String label) => find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .first;
      Future<({Rect box, double labelOffset, double gap})> measure({
        required bool foldable,
      }) async {
        await pump(tester, foldable: foldable);
        final header = tester.getRect(box('EVENTS'));
        final group = tester.getRect(
          find
              .ancestor(
                of: find.text('Accent color'),
                matching: find.byWidgetPredicate(
                  (w) => w is Material && w.type == MaterialType.card,
                ),
              )
              .first,
        );
        return (
          box: header,
          labelOffset: tester.getRect(find.text('EVENTS')).top - header.top,
          gap: tester.getRect(find.text('EVENTS')).top - group.bottom,
        );
      }

      final folding = await measure(foldable: true);
      final plain = await measure(foldable: false);
      expect(folding.box.height, RowMetrics.singleLineMinHeight);
      expect(plain.box.height, folding.box.height);
      expect(plain.labelOffset, folding.labelOffset);
      expect(plain.gap, folding.gap);
    });

    testWidgets('a folding header is a 48 dp target as wide as its group', (
      tester,
    ) async {
      await pump(tester);

      final target = find.ancestor(
        of: find.text('APPEARANCE'),
        matching: find.byType(InkWell),
      );
      expect(target, findsOneWidget);
      final rect = tester.getRect(target);
      expect(rect.height, greaterThanOrEqualTo(RowMetrics.singleLineMinHeight));
      final group = find.ancestor(
        of: find.text('Today style'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Material && widget.type == MaterialType.card,
        ),
      );
      expect(rect.width, tester.getSize(group).width);
    });

    testWidgets('rows sit in a rowGroup group on the page ground, no Card, '
        'and the section icon is not drawn', (tester) async {
      await pump(tester);
      final colorScheme = Theme.of(
        tester.element(find.byType(SettingsSectionList)),
      ).colorScheme;

      expect(find.byType(Card), findsNothing);
      expect(find.byIcon(Icons.palette_rounded), findsNothing);
      final group = tester.widget<Material>(
        find
            .ancestor(
              of: find.text('Today style'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(group.color, colorScheme.rowGroup);
      expect(group.elevation, 0);
      expect(group.borderRadius, BorderRadius.circular(RowMetrics.groupRadius));
      final ground = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(SettingsSectionList),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(ground.color, colorScheme.pageGround);
    });

    testWidgets('a one-line row is 48 dp and a two-line row 62 dp', (
      tester,
    ) async {
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
                  entries: [
                    entry('One line'),
                    SettingsEntry(
                      title: 'Two lines',
                      description: 'A caption',
                      builder: (context, title, description) =>
                          ListTile(title: title, subtitle: description),
                    ),
                  ],
                ),
              ],
              query: SettingsQuery.empty,
            ),
          ),
        ),
      );

      Finder tile(String title) =>
          find.ancestor(of: find.text(title), matching: find.byType(ListTile));
      expect(
        tester.getSize(tile('One line')).height,
        RowMetrics.singleLineMinHeight,
      );
      expect(
        tester.getSize(tile('Two lines')).height,
        RowMetrics.twoLineMinHeight,
      );
    });

    TextStyle? styleOf(WidgetTester tester, String text) => tester
        .widget<RichText>(
          find.descendant(of: find.text(text), matching: find.byType(RichText)),
        )
        .text
        .style;

    testWidgets('an intro is inset from its group\'s top edge, in the caption '
        'role', (tester) async {
      await pump(tester);
      final colorScheme = Theme.of(
        tester.element(find.byType(SettingsSectionList)),
      ).colorScheme;

      final group = tester.getRect(
        find
            .ancestor(
              of: find.text('preview strip'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(
        tester.getRect(find.text('preview strip')).top - group.top,
        FormMetrics.settingsRowVerticalPadding,
      );
      final style = styleOf(tester, 'preview strip')!;
      expect(style.fontSize, RowMetrics.secondLineFontSize);
      expect(style.height, settingsCaptionStyle.height);
      expect(style.color, colorScheme.onSurfaceVariant);
    });

    testWidgets('a disabled tile dims its caption; an enabled one and a row '
        'drawn without a tile keep onSurfaceVariant', (tester) async {
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
                  entries: [
                    for (final enabled in [true, false])
                      SettingsEntry(
                        title: 'Row $enabled',
                        description: 'Caption $enabled',
                        builder: (context, title, description) => ListTile(
                          enabled: enabled,
                          title: title,
                          subtitle: description,
                        ),
                      ),
                    SettingsEntry(
                      title: 'Bare',
                      description: 'Caption bare',
                      builder: (context, title, description) =>
                          Column(children: [title, description!]),
                    ),
                  ],
                ),
              ],
              query: SettingsQuery.empty,
            ),
          ),
        ),
      );
      final theme = Theme.of(tester.element(find.byType(SettingsSectionList)));

      expect(
        styleOf(tester, 'Caption true')!.color,
        theme.colorScheme.onSurfaceVariant,
      );
      expect(styleOf(tester, 'Caption false')!.color, theme.disabledColor);
      expect(
        styleOf(tester, 'Caption bare')!.color,
        theme.colorScheme.onSurfaceVariant,
      );
    });

    testWidgets('a yielding tile starts its title where its neighbours do, '
        'centres its glyph as they do, and reads its value in the caption '
        'role', (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
                  entries: [
                    SettingsEntry(
                      title: 'Neighbour',
                      builder: (context, title, description) => ListTile(
                        leading: const Icon(Icons.restore_rounded),
                        title: title,
                      ),
                    ),
                    SettingsEntry(
                      title: 'Yielding',
                      description: 'A caption',
                      builder: (context, title, description) =>
                          SettingsYieldingTile(
                            leading: const Icon(Icons.public_rounded),
                            title: title,
                            subtitle: description,
                            value: 'A value',
                            trailing: (maxWidth) => const Text('A value'),
                          ),
                    ),
                  ],
                ),
              ],
              query: SettingsQuery.empty,
            ),
          ),
        ),
      );
      final colorScheme = Theme.of(
        tester.element(find.byType(SettingsSectionList)),
      ).colorScheme;

      expect(
        tester.getRect(find.text('Yielding')).left,
        tester.getRect(find.text('Neighbour')).left,
      );
      final tile = tester.getRect(
        find.ancestor(
          of: find.text('Yielding'),
          matching: find.byType(ListTile),
        ),
      );
      expect(
        tester.getCenter(find.byIcon(Icons.public_rounded)).dy,
        moreOrLessEquals(tile.center.dy),
      );
      final value = styleOf(tester, 'A value')!;
      expect(value.fontSize, RowMetrics.secondLineFontSize);
      expect(value.fontWeight, FontWeight.w400);
      expect(value.color, colorScheme.onSurfaceVariant);
    });

    for (final (locale, title, count) in const [
      ('ro', 'Aspectul calendarului și al marcajelor', '20 de opțiuni'),
      ('de', 'Darstellung des Kalenders und der Marker', '20 Optionen'),
    ]) {
      testWidgets('a folded count stays inside a third of its header at 2.0 '
          'on a phone, beside a title that wraps, on one line centred with '
          'the chevron, $locale', (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale(locale),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: Scaffold(
              body: SettingsSectionList(
                sections: [
                  SettingsSectionData(
                    id: 'long',
                    icon: Icons.event_note_rounded,
                    title: title,
                    entries: [for (var i = 0; i < 20; i++) entry('Row $i')],
                  ),
                ],
                query: SettingsQuery.empty,
                collapsedSections: const {'long'},
                onToggleSection: (_) {},
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        final header = tester.getRect(find.byType(InkWell));
        final countRect = tester.getRect(find.text(count));
        expect(countRect.width, lessThanOrEqualTo(header.width / 3));
        expect(countRect.right, lessThanOrEqualTo(header.right));
        // Beside a title on two lines, the count stays on one: its height
        // is its text laid out on a single line.
        expect(
          tester.getRect(find.text(title.toUpperCase())).height,
          greaterThan(countRect.height),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text(count),
            matching: find.byType(RichText),
          ),
        );
        final oneLine = TextPainter(
          text: paragraph.text,
          textScaler: paragraph.textScaler,
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        addTearDown(oneLine.dispose);
        expect(countRect.height, moreOrLessEquals(oneLine.height));
        expect(
          countRect.center.dy,
          moreOrLessEquals(
            tester.getCenter(find.byIcon(Icons.expand_more_rounded)).dy,
          ),
        );
      });
    }
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
