import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/l10n/app_localizations_ro.dart';
import 'package:anta/models/app_guide_content.dart';
import 'package:anta/models/calendar_guide_content.dart';
import 'package:anta/models/guide_book.dart';
import 'package:anta/models/guide_content.dart';
import 'package:anta/models/notes_guide_content.dart';
import 'package:anta/pages/guide_book_page.dart';
import 'package:anta/pages/guide_topic_page.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/money_display_config.dart';
import 'package:anta/utils/settings_search.dart';
import 'package:anta/widgets/calendar_guide_rows.dart';
import 'package:anta/widgets/guide_example_row.dart';
import 'package:anta/widgets/settings_section_list.dart';
import 'package:anta/widgets/simple_markdown_preview.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';

Widget _app(
  Widget home, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: home,
  );
}

/// Every page of both books, each written in full (§6 of
/// docs/guide-hub-roadmap.md).
final List<(GuideBook, GuideTopic)> _written = [
  for (final topic in NotesGuideTopic.values) (GuideBook.notes, topic),
  for (final topic in AppGuideTopic.values) (GuideBook.app, topic),
];

/// The page's read rows, in page order.
List<CalendarGuideRow> _readRows(GuideTopic topic, AppLocalizations l10n) => [
  for (final entry in topic.entries(l10n))
    if (entry case GuideReadEntry(:final row)) row,
];

/// The list's own scrollable — a hub's search field has one too.
Finder _list() => find
    .descendant(
      of: find.byType(SettingsSectionList),
      matching: find.byType(Scrollable),
    )
    .first;

Finder _hubRow(GuideBook book, GuideTopic topic) => find.bySemanticsIdentifier(
  SemanticsIds.guideBookPage(book.slug, topic.slug),
);

Finder _row(GuideBook book, String slug) =>
    find.bySemanticsIdentifier(SemanticsIds.guideBookRow(book.slug, slug));

Finder _example(GuideBook book, String slug) =>
    find.bySemanticsIdentifier(SemanticsIds.guideBookExample(book.slug, slug));

/// A page's row by the id its kind takes.
Finder _entry(GuideBook book, GuideEntry entry) => switch (entry) {
  GuideReadEntry(:final row) => _row(book, row.slug),
  GuideExampleEntry(:final slug) => _example(book, slug),
};

/// Moves the list itself rather than dragging it, until [finder] is built.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final position = tester.state<ScrollableState>(_list()).position;
  // German at text scale 2.0 on a 360-wide phone runs to many screens.
  for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
    position.jumpTo(
      (position.pixels + 300).clamp(0.0, position.maxScrollExtent),
    );
    await tester.pump();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// A section's header as the kit draws it: the browser's uppercase label.
Finder _header(String title) => find.text(title.toUpperCase());

/// The kit's section [finder] sits in — its header and its group of rows.
Finder _cardOf(Finder finder) =>
    find.ancestor(of: finder, matching: find.byType(SettingsSectionCard)).first;

/// Every string drawn under [row], highlighted or not.
Iterable<String> _textsUnder(WidgetTester tester, Finder row) => tester
    .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
    .map((text) => text.data ?? text.textSpan!.toPlainText());

/// No laid-out text in the list is cut: every paragraph is as tall as its
/// lines need and none ran out of lines. The search field's hint is the
/// kit's, cut at 2.0 on every settings page alike, and is left out.
void _expectNoClippedText(WidgetTester tester) {
  final paragraphs = tester.renderObjectList<RenderParagraph>(
    find.descendant(
      of: find.byType(SettingsSectionList),
      matching: find.byType(RichText),
    ),
  );
  for (final paragraph in paragraphs) {
    final reason = paragraph.text.toPlainText();
    expect(paragraph.didExceedMaxLines, isFalse, reason: reason);
    expect(
      paragraph.size.height,
      moreOrLessEquals(
        paragraph.getMaxIntrinsicHeight(paragraph.size.width),
        epsilon: 0.01,
      ),
      reason: reason,
    );
  }
}

void main() {
  final en = AppLocalizationsEn();
  late AppDatabase db;

  setUpAll(loadGoldenFonts);

  // A page reads the money config and the palette once; an unbound service
  // would leave a half-built singleton behind for the next case.
  setUp(() async {
    db = await openTestDatabase();
    SettingsService.reset();
    SettingsService.forTesting(db);
  });

  tearDown(() async {
    SettingsService.reset();
    await db.close();
  });

  test('the catalogues: every slug once per book, the hub split covers '
      'every page once', () {
    for (final book in [GuideBook.notes, GuideBook.app]) {
      final topics = book.topics.map((topic) => topic.slug).toList();
      expect(topics.toSet(), hasLength(topics.length), reason: book.slug);
      expect(book.topics, containsAll(book.startHere));
      final rows = [
        for (final topic in book.topics)
          for (final entry in topic.entries(en))
            switch (entry) {
              GuideReadEntry(:final row) => row.slug,
              GuideExampleEntry(:final slug) => slug,
            },
      ];
      expect(rows.toSet(), hasLength(rows.length), reason: book.slug);
    }
    expect(NotesGuideTopic.values, hasLength(11));
  });

  for (final book in [GuideBook.notes, GuideBook.app]) {
    testWidgets('${book.slug}: every page row sits in its card, by id', (
      tester,
    ) async {
      await tester.pumpWidget(_app(GuideBookPage(book: book)));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(SemanticsIds.guideBook(book.slug)),
        findsOneWidget,
      );
      expect(find.text(book.title(en)), findsOneWidget);
      expect(find.text(book.intro(en)), findsOneWidget);
      for (final topic in book.topics) {
        await _scrollTo(tester, _hubRow(book, topic));
        final title = book.startHere.contains(topic)
            ? en.calendarGuideStartHere
            : en.calendarGuideHowDoI;
        expect(
          find.descendant(
            of: _cardOf(_hubRow(book, topic)),
            matching: _header(title),
          ),
          findsOneWidget,
          reason: topic.slug,
        );
        expect(
          find.descendant(
            of: _hubRow(book, topic),
            matching: find.text(topic.title(en)),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('${book.slug}: every page row pushes its page unstamped, and '
        'back returns to the book', (tester) async {
      await tester.pumpWidget(_app(GuideBookPage(book: book)));
      await tester.pumpAndSettle();

      for (final topic in book.topics) {
        await _scrollTo(tester, _hubRow(book, topic));
        await tester.tap(_hubRow(book, topic));
        await tester.pumpAndSettle();

        final page = find.byType(GuideTopicPage);
        expect(page, findsOneWidget, reason: topic.slug);
        // A plain push: no name and no arguments for a restore to replay.
        final route = ModalRoute.of(tester.element(page))!;
        expect(route.settings.name, isNull);
        expect(route.settings.arguments, isNull);
        expect(
          find.bySemanticsIdentifier(
            SemanticsIds.guideBookTopic(book.slug, topic.slug),
          ),
          findsOneWidget,
        );

        Navigator.of(tester.element(page)).pop();
        await tester.pumpAndSettle();
        expect(page, findsNothing);
      }
    });
  }

  testWidgets('the book search finds a row under its page', (tester) async {
    await tester.pumpWidget(_app(const GuideBookPage(book: GuideBook.app)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), en.appGuideSyncStopTitle);
    await tester.pumpAndSettle();
    final row = _row(GuideBook.app, 'sync-stop');
    expect(row, findsOneWidget);
    expect(
      find.descendant(
        of: _cardOf(row),
        matching: _hubRow(GuideBook.app, AppGuideTopic.sync),
      ),
      findsOneWidget,
    );
    expect(_hubRow(GuideBook.app, AppGuideTopic.menu), findsNothing);
  });

  testWidgets('the book search finds a page by a word only an example '
      'caption holds', (tester) async {
    await tester.pumpWidget(_app(const GuideBookPage(book: GuideBook.notes)));
    await tester.pumpAndSettle();

    // "tildes" is in the emphasis example's caption and in no row of the book.
    expect(en.notesGuideExEmphasisCaption, contains('tildes'));
    await tester.enterText(find.byType(TextField), 'tildes');
    await tester.pumpAndSettle();
    expect(_hubRow(GuideBook.notes, NotesGuideTopic.markdown), findsOneWidget);
    for (final topic in NotesGuideTopic.values) {
      if (topic == NotesGuideTopic.markdown) continue;
      expect(_hubRow(GuideBook.notes, topic), findsNothing, reason: topic.slug);
    }
  });

  for (final (book, topic) in _written) {
    testWidgets('${book.slug} ${topic.slug}: the heading, the lead and every '
        'row', (tester) async {
      await tester.pumpWidget(_app(GuideTopicPage(book: book, topic: topic)));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(
          SemanticsIds.guideBookTopic(book.slug, topic.slug),
        ),
        findsOneWidget,
      );
      // No search field: the hubs search every page.
      expect(find.byType(TextField), findsNothing);
      final heading = tester
          .getSemantics(find.text(topic.title(en)))
          .getSemanticsData();
      expect(heading.flagsCollection.isHeader, isTrue);
      // The bar names the book and is the route's one level-1 heading.
      expect(heading.headingLevel, 2);
      final levelOne = find.semantics.byPredicate(
        (node) => node.getSemanticsData().headingLevel == 1,
      );
      expect(levelOne, findsOne);
      expect(levelOne.evaluate().single.label, book.title(en));
      final lead = topic.lead(en);
      if (lead != null) expect(find.text(lead), findsOneWidget);
      expect(
        find.text(en.calendarGuideHowItWorks.toUpperCase()),
        findsOneWidget,
      );

      expect(_readRows(topic, en), isNotEmpty);
      for (final entry in topic.entries(en)) {
        final found = _entry(book, entry);
        await _scrollTo(tester, found);
        expect(found, findsOneWidget);
        switch (entry) {
          case GuideReadEntry(:final row):
            expect(
              find.descendant(of: found, matching: find.text(row.title)),
              findsOneWidget,
              reason: row.slug,
            );
            // Read, never pressed.
            expect(
              find.descendant(of: found, matching: find.byType(InkWell)),
              findsNothing,
              reason: row.slug,
            );
            final data = tester
                .getSemantics(
                  find.descendant(of: found, matching: find.text(row.title)),
                )
                .getSemanticsData();
            expect(data.hasAction(SemanticsAction.tap), isFalse);
            expect(data.flagsCollection.isButton, isFalse);
          case GuideExampleEntry(:final slug, :final source):
            // The typed block, not the preview: a plain line previews as
            // the same words.
            expect(
              find.descendant(
                of: found,
                matching: find.byWidgetPredicate(
                  (widget) => widget is Text && widget.data == source,
                ),
              ),
              findsOneWidget,
              reason: slug,
            );
            expect(
              find.descendant(
                of: found,
                matching: find.byType(SimpleMarkdownPreview),
              ),
              findsOneWidget,
              reason: slug,
            );
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a read row is read, never pressed, and TalkBack reads it as '
      'one node', (tester) async {
    await tester.pumpWidget(
      _app(
        const GuideTopicPage(book: GuideBook.app, topic: AppGuideTopic.backup),
      ),
    );
    await tester.pumpAndSettle();

    final row = _row(GuideBook.app, 'backup-folder');
    final body = en.appGuideBackupFolderBody(en.shareFolder);
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byType(ListTile)),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.byType(InkWell)),
      findsNothing,
    );
    final titleNode = tester.getSemantics(
      find.text(en.appGuideBackupFolderTitle),
    );
    final bodyNode = tester.getSemantics(find.text(body));
    expect(identical(titleNode, bodyNode), isTrue);
    final data = titleNode.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    expect(data.flagsCollection.isButton, isFalse);
  });

  group('an example row', () {
    Widget exampleHost(GuideExampleEntry example, MoneyDisplayConfig money) {
      return _app(
        Scaffold(
          body: SettingsSectionList(
            query: SettingsQuery.empty,
            sections: [
              SettingsSectionData(
                icon: Icons.text_fields_rounded,
                title: en.calendarGuideHowItWorks,
                entries: [
                  guideExampleEntry(
                    example,
                    book: GuideBook.notes,
                    moneyConfig: money,
                    colorPalette: MarkdownColorPalette.presets,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    for (final (slug, source, caption) in [
      ('heading', en.notesGuideExHeadingSource, en.notesGuideExHeadingCaption),
      (
        'money-basic',
        en.notesGuideExMoneyBasicSource,
        en.notesGuideExMoneyBasicCaption,
      ),
      (
        'money-target',
        en.notesGuideExMoneyTargetSource,
        en.notesGuideExMoneyTargetCaption,
      ),
    ]) {
      testWidgets('$slug shows its source as typed over the app\'s own '
          'preview, with the page\'s config, and its caption', (tester) async {
        const money = MoneyDisplayConfig(enabled: true, currencySymbol: '€');
        await tester.pumpWidget(
          exampleHost(
            GuideExampleEntry(slug: slug, source: source, caption: caption),
            money,
          ),
        );
        await tester.pumpAndSettle();

        final row = find.bySemanticsIdentifier(
          SemanticsIds.guideBookExample('notes', slug),
        );
        expect(row, findsOneWidget);
        final typed = find.descendant(of: row, matching: find.text(source));
        expect(typed, findsOneWidget);
        // One typed line, one drawn line: no soft wrap, a sideways scroll.
        expect(tester.widget<Text>(typed).softWrap, isFalse);
        final scroller = find.ancestor(
          of: typed,
          matching: find.byType(SingleChildScrollView),
        );
        expect(scroller, findsOneWidget);
        expect(
          tester.widget<SingleChildScrollView>(scroller).scrollDirection,
          Axis.horizontal,
        );
        final preview = find.descendant(
          of: row,
          matching: find.byType(SimpleMarkdownPreview),
        );
        expect(preview, findsOneWidget);
        final widget = tester.widget<SimpleMarkdownPreview>(preview);
        expect(widget.data, source);
        expect(widget.moneyConfig, money);
        expect(widget.scrollable, isFalse);
        expect(widget.onTapLink, isNull);
        expect(widget.onCheckboxTap, isNull);
        expect(widget.onTapWikiLink, isNull);
        // The caption is running text: the read row's paragraph colour, not
        // a row title's.
        final captionText = find.descendant(
          of: row,
          matching: find.text(caption),
        );
        expect(captionText, findsOneWidget);
        final colorScheme = Theme.of(tester.element(row)).colorScheme;
        expect(
          tester.widget<Text>(captionText).style?.color,
          colorScheme.onSurfaceVariant,
        );
        for (final label in [en.guideExampleTyped, en.guideExampleShown]) {
          expect(
            find.descendant(of: row, matching: find.text(label.toUpperCase())),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a read row and an example row in one card start their text '
        'on one edge', (tester) async {
      final read = CalendarGuideRow(
        'read',
        Icons.title_rounded,
        en.notesGuideMarkdownLead,
        en.notesGuideExHeadingCaption,
      );
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SettingsSectionList(
              query: SettingsQuery.empty,
              sections: [
                SettingsSectionData(
                  icon: Icons.text_fields_rounded,
                  title: en.calendarGuideHowItWorks,
                  entries: [
                    calendarGuideReadEntry(read),
                    guideExampleEntry(
                      GuideExampleEntry(
                        slug: 'heading',
                        source: en.notesGuideExHeadingSource,
                        caption: en.notesGuideExHeadingCaption,
                      ),
                      book: GuideBook.notes,
                      moneyConfig: const MoneyDisplayConfig(enabled: true),
                      colorPalette: MarkdownColorPalette.presets,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final example = find.bySemanticsIdentifier(
        SemanticsIds.guideBookExample('notes', 'heading'),
      );
      final edge = tester.getTopLeft(find.text(read.title)).dx;
      for (final text in [
        en.guideExampleTyped.toUpperCase(),
        en.notesGuideExHeadingCaption,
      ]) {
        expect(
          tester
              .getTopLeft(
                find.descendant(of: example, matching: find.text(text)),
              )
              .dx,
          edge,
          reason: text,
        );
      }
      expect(
        tester.getTopLeft(find.byIcon(Icons.code_rounded)).dx,
        tester.getTopLeft(find.byIcon(Icons.title_rounded)).dx,
      );
    });
  });

  testWidgets('the money page draws its examples as a ledger in her currency '
      'even with the ledger switched off (§4)', (tester) async {
    final settings = SettingsService.forTesting(db);
    await settings.setMoneyLedgerEnabled(false);
    await settings.setMoneyCurrencySymbol('€');

    await tester.pumpWidget(
      _app(
        const GuideTopicPage(
          book: GuideBook.notes,
          topic: NotesGuideTopic.money,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final previews = tester.widgetList<SimpleMarkdownPreview>(
      find.byType(SimpleMarkdownPreview),
    );
    expect(previews, isNotEmpty);
    for (final preview in previews) {
      expect(preview.moneyConfig.enabled, isTrue, reason: preview.data);
      expect(preview.moneyConfig.currencySymbol, '€', reason: preview.data);
    }
  });

  group('the guide quotes the live labels', () {
    for (final (locale, l10n, open, close) in [
      (const Locale('en'), en as AppLocalizations, '“', '”'),
      (const Locale('de'), AppLocalizationsDe() as AppLocalizations, '„', '“'),
      (const Locale('ro'), AppLocalizationsRo() as AppLocalizations, '„', '”'),
    ]) {
      for (final (book, topic, slug, label)
          in <(GuideBook, GuideTopic, String, String)>[
            (
              GuideBook.notes,
              NotesGuideTopic.basics,
              'basics-create',
              l10n.newNote,
            ),
            (
              GuideBook.notes,
              NotesGuideTopic.basics,
              'basics-sort',
              l10n.sortByCustom,
            ),
            (
              GuideBook.notes,
              NotesGuideTopic.money,
              'money-settings',
              l10n.moneySection,
            ),
            (
              GuideBook.notes,
              NotesGuideTopic.money,
              'money-settings',
              l10n.moneyLedgerEnabledLabel,
            ),
            (
              GuideBook.notes,
              NotesGuideTopic.money,
              'money-buttons',
              l10n.shortcutMoneyAdd,
            ),
            (
              GuideBook.notes,
              NotesGuideTopic.bar,
              'bar-shortcuts',
              l10n.shortcuts,
            ),
            (
              GuideBook.notes,
              NotesGuideTopic.bar,
              'bar-profiles',
              l10n.switchBar,
            ),
            (
              GuideBook.notes,
              NotesGuideTopic.bar,
              'bar-layout',
              l10n.splitToolbar,
            ),
            (
              GuideBook.app,
              AppGuideTopic.backup,
              'backup-folder',
              l10n.shareFolder,
            ),
            (GuideBook.app, AppGuideTopic.sync, 'sync-stop', l10n.syncStop),
          ]) {
        testWidgets('${locale.languageCode}: ${book.slug} $slug', (
          tester,
        ) async {
          await tester.pumpWidget(
            _app(
              GuideTopicPage(book: book, topic: topic),
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();

          await _scrollTo(tester, _row(book, slug));
          expect(
            _textsUnder(tester, _row(book, slug)),
            contains(contains('$open$label$close')),
          );
        });
      }
    }
  });

  group('no overflow and no clipped label at text scale 2.0', () {
    for (final locale in const [Locale('de'), Locale('ro')]) {
      for (final size in const [Size(360, 780), Size(412, 915)]) {
        for (final brightness in Brightness.values) {
          for (final book in [GuideBook.notes, GuideBook.app]) {
            testWidgets('${locale.languageCode} ${size.width.toInt()}×'
                '${size.height.toInt()} ${brightness.name}: ${book.slug}', (
              tester,
            ) async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              final l10n = lookupAppLocalizations(locale);
              Widget host(Widget home) => _app(
                home,
                locale: locale,
                brightness: brightness,
                textScaler: const TextScaler.linear(2.0),
              );

              await tester.pumpWidget(host(GuideBookPage(book: book)));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              _expectNoClippedText(tester);
              for (final topic in book.topics) {
                await _scrollTo(tester, _hubRow(book, topic));
                expect(tester.takeException(), isNull);
                _expectNoClippedText(tester);
              }

              for (final (written, topic) in _written) {
                if (written != book) continue;
                await tester.pumpWidget(
                  host(GuideTopicPage(book: book, topic: topic)),
                );
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull, reason: topic.slug);
                _expectNoClippedText(tester);
                for (final entry in topic.entries(l10n)) {
                  await _scrollTo(tester, _entry(book, entry));
                  expect(tester.takeException(), isNull, reason: topic.slug);
                  _expectNoClippedText(tester);
                }
              }
            });
          }
        }
      }
    }
  });
}
