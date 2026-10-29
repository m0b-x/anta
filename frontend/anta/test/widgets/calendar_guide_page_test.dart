import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/guide_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_guide_content.dart';
import 'package:anta/pages/calendar_guide_page.dart';
import 'package:anta/pages/calendar_guide_topic_page.dart';
import 'package:anta/widgets/settings_section_list.dart';

Widget _host({
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
    home: const CalendarGuidePage(),
  );
}

/// The hub's section list's own scrollable — the search field has one too.
Finder _list() => find
    .descendant(
      of: find.descendant(
        of: find.byType(CalendarGuidePage),
        matching: find.byType(SettingsSectionList),
      ),
      matching: find.byType(Scrollable),
    )
    .first;

/// The hub's rows top to bottom: "Start here" holds the screen and Good to
/// know, "How do I…" the seven tasks.
final List<CalendarGuideTopic> _hubOrder = [
  CalendarGuideTopic.screen,
  CalendarGuideTopic.good,
  for (final topic in CalendarGuideTopic.values)
    if (topic != CalendarGuideTopic.screen && topic != CalendarGuideTopic.good)
      topic,
];

Finder _page(CalendarGuideTopic topic) =>
    find.bySemanticsIdentifier(SemanticsIds.calendarGuidePage(topic.slug));

/// The Practice calendar's row, first in "Start here".
final Finder _practice = find.bySemanticsIdentifier(
  SemanticsIds.calendarGuidePage(calendarGuidePracticeSlug),
);

Finder _row(String slug) =>
    find.bySemanticsIdentifier(SemanticsIds.calendarGuideRow(slug));

Future<void> _scrollTo(WidgetTester tester, Finder finder) => tester
    .scrollUntilVisible(finder, 300, scrollable: _list(), maxScrolls: 200);

/// The section card [finder] sits in.
Finder _cardOf(Finder finder) =>
    find.ancestor(of: finder, matching: find.byType(Card)).first;

/// No laid-out text in the hub's list is cut: every paragraph is as tall as
/// its lines need and none ran out of lines. The search field's hint is the
/// kit's, cut at 2.0 on every settings page alike, and is left out.
void _expectNoClippedText(WidgetTester tester) {
  final paragraphs = tester.renderObjectList<RenderParagraph>(
    find.descendant(
      of: find.descendant(
        of: find.byType(CalendarGuidePage),
        matching: find.byType(SettingsSectionList),
      ),
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

  testWidgets('the hub lists its ten rows under its two cards', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(
      find.text(en.calendarGuideIntro(en.calendarGuideTryIt)),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.calendarGuide),
      findsOneWidget,
    );
    expect(find.text(en.calendarGuideStartHere), findsOneWidget);
    expect(_practice, findsOneWidget);
    expect(
      find.descendant(
        of: _practice,
        matching: find.text(en.calendarGuidePagePractice),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _practice,
        matching: find.text(en.calendarGuidePagePracticeCaption),
      ),
      findsOneWidget,
    );
    for (final topic in _hubOrder) {
      await _scrollTo(tester, _page(topic));
      expect(_page(topic), findsOneWidget, reason: topic.slug);
      expect(
        find.descendant(of: _page(topic), matching: find.text(topic.title(en))),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _page(topic),
          matching: find.text(topic.caption(en)),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: _cardOf(_page(CalendarGuideTopic.setup)),
        matching: find.text(en.calendarGuideHowDoI),
      ),
      findsOneWidget,
    );
  });

  testWidgets('"Start here" holds the practice calendar, the screen and Good '
      'to know, "How do I…" the seven tasks in order', (tester) async {
    // Tall enough that the list builds every row at once.
    tester.view.physicalSize = const Size(412, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    const startHere = [CalendarGuideTopic.screen, CalendarGuideTopic.good];
    const howDoI = [
      CalendarGuideTopic.events,
      CalendarGuideTopic.kinds,
      CalendarGuideTopic.alerts,
      CalendarGuideTopic.attendance,
      CalendarGuideTopic.categories,
      CalendarGuideTopic.finding,
      CalendarGuideTopic.setup,
    ];
    for (final (cardTitle, topics) in [
      (en.calendarGuideStartHere, startHere),
      (en.calendarGuideHowDoI, howDoI),
    ]) {
      for (final topic in topics) {
        expect(
          find.descendant(
            of: _cardOf(_page(topic)),
            matching: find.text(cardTitle),
          ),
          findsOneWidget,
          reason: topic.slug,
        );
      }
    }
    expect(
      find.descendant(
        of: _cardOf(_practice),
        matching: find.text(en.calendarGuideStartHere),
      ),
      findsOneWidget,
    );
    final order = [
      _practice,
      for (final topic in [...startHere, ...howDoI]) _page(topic),
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        tester.getTopLeft(order[i - 1]).dy,
        lessThan(tester.getTopLeft(order[i]).dy),
        reason: 'row ${i - 1} before row $i',
      );
    }
  });

  testWidgets('a hub title is drawn in the style the glyph rule measures', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final topic = CalendarGuideTopic.events;
    final title = tester.widget<Text>(
      find.descendant(of: _page(topic), matching: find.text(topic.title(en))),
    );
    expect(title.style?.fontSize, GuideMetrics.hubTitleFontSize);
    expect(title.style?.fontWeight, GuideMetrics.hubTitleFontWeight);
  });

  testWidgets('every hub row pushes its page, and back returns to the hub', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    for (final topic in _hubOrder) {
      await _scrollTo(tester, _page(topic));
      await tester.tap(_page(topic));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarGuideTopicPage), findsOneWidget);
      // A plain push: no name and no arguments for a restore to replay.
      final route = ModalRoute.of(
        tester.element(find.byType(CalendarGuideTopicPage)),
      )!;
      expect(route.settings.name, isNull);
      expect(route.settings.arguments, isNull);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.calendarGuideTopic(topic.slug)),
        findsOneWidget,
        reason: topic.slug,
      );
      expect(find.text(topic.title(en)), findsOneWidget);

      Navigator.of(tester.element(find.byType(CalendarGuideTopicPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(CalendarGuideTopicPage), findsNothing);
    }
  });

  testWidgets('a hub row is one button node with the title and its caption', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final topic = CalendarGuideTopic.events;
    final titleNode = tester.getSemantics(find.text(topic.title(en)));
    final captionNode = tester.getSemantics(find.text(topic.caption(en)));
    expect(identical(titleNode, captionNode), isTrue);
    final data = titleNode.getSemanticsData();
    expect(data.label, contains(topic.title(en)));
    expect(data.label, contains(topic.caption(en)));
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.flagsCollection.isButton, isTrue);
    expect(
      find.descendant(
        of: _page(topic),
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsOneWidget,
    );
  });

  group('the glyph rule', () {
    testWidgets('en at 1.0: every hub row carries its page glyph', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: _practice,
          matching: find.byIcon(calendarGuidePracticeIcon),
        ),
        findsOneWidget,
      );
      for (final topic in _hubOrder) {
        await _scrollTo(tester, _page(topic));
        expect(
          find.descendant(of: _page(topic), matching: find.byIcon(topic.icon)),
          findsOneWidget,
          reason: topic.slug,
        );
      }
    });

    testWidgets('de at 2.0 on 360: every hub row drops its glyph', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          locale: const Locale('de'),
          textScaler: const TextScaler.linear(2.0),
        ),
      );
      await tester.pumpAndSettle();
      await _scrollTo(tester, _practice);
      expect(
        find.descendant(
          of: _practice,
          matching: find.byIcon(calendarGuidePracticeIcon),
        ),
        findsNothing,
      );
      for (final topic in _hubOrder) {
        await _scrollTo(tester, _page(topic));
        expect(
          find.descendant(of: _page(topic), matching: find.byIcon(topic.icon)),
          findsNothing,
          reason: topic.slug,
        );
      }
    });
  });

  testWidgets('the search narrows to the matching rows, each under its '
      "page's name, and clearing it restores the hub", (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    final field = find.byType(TextField);

    await tester.enterText(field, 'repeat');
    await tester.pumpAndSettle();
    expect(_row('repeat'), findsOneWidget);
    expect(_row('add-event'), findsNothing);
    expect(
      find.text(en.calendarGuideIntro(en.calendarGuideTryIt)),
      findsNothing,
    );
    expect(find.text(en.calendarGuideStartHere), findsNothing);
    expect(find.text(en.calendarGuideHowDoI), findsNothing);
    // The row lives on the kinds page: it sits in that page's section, under
    // the page's name and after the row that opens the page.
    final kinds = CalendarGuideTopic.kinds;
    final card = _cardOf(_row('repeat'));
    // The page's name and glyph twice in the card — once on the row that
    // opens the page, once more on the section's header.
    Finder pageName(Finder scope) => find.descendant(
      of: scope,
      matching: find.byWidgetPredicate(
        (widget) => widget is HighlightedText && widget.text == kinds.title(en),
      ),
    );
    expect(pageName(card), findsNWidgets(2));
    expect(pageName(_page(kinds)), findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byIcon(kinds.icon)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: _page(kinds), matching: find.byIcon(kinds.icon)),
      findsOneWidget,
    );
    expect(find.descendant(of: card, matching: _page(kinds)), findsOneWidget);
    expect(
      tester.getTopLeft(_page(kinds)).dy,
      lessThan(tester.getTopLeft(_row('repeat')).dy),
    );

    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    expect(_row('repeat'), findsNothing);
    expect(find.text(en.calendarGuideStartHere), findsOneWidget);
    await _scrollTo(tester, _page(CalendarGuideTopic.kinds));
    expect(_page(CalendarGuideTopic.kinds), findsOneWidget);

    await tester.enterText(field, 'zzqxj');
    await tester.pumpAndSettle();
    expect(find.text(en.noMatchesFound), findsOneWidget);
  });

  testWidgets('a query that hits a page name keeps only the matching rows '
      'of that page', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // "delete" is in the events page's name, in its open row and not in its
    // time row.
    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pumpAndSettle();
    expect(_page(CalendarGuideTopic.events), findsOneWidget);
    expect(_row('open'), findsOneWidget);
    expect(_row('time'), findsNothing);
  });

  testWidgets('de at 2.0 on 360: the search results neither overflow nor '
      'clip', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        locale: const Locale('de'),
        textScaler: const TextScaler.linear(2.0),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ereignis');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    _expectNoClippedText(tester);

    for (var i = 0; i < 40; i++) {
      final position = tester.state<ScrollableState>(_list()).position;
      if (position.pixels >= position.maxScrollExtent) break;
      await tester.drag(_list(), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      _expectNoClippedText(tester);
    }
  });

  testWidgets("a search hit's page row opens that page", (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      en.calendarGuideKindsBirthdayTitle,
    );
    await tester.pumpAndSettle();
    expect(_row('kinds-birthday'), findsOneWidget);

    await tester.tap(_page(CalendarGuideTopic.kinds));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.calendarGuideTopic('kinds')),
      findsOneWidget,
    );
  });

  for (final (locale, query) in const [
    (Locale('en'), 'practice'),
    (Locale('de'), 'Übung'),
  ]) {
    testWidgets('"$query" finds the Practice calendar row, alone in a section '
        'under its own name', (tester) async {
      await tester.pumpWidget(_host(locale: locale));
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(locale);

      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
      expect(_practice, findsOneWidget);
      final card = _cardOf(_practice);
      expect(
        find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is HighlightedText &&
                widget.text == l10n.calendarGuidePagePractice,
          ),
        ),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byIcon(calendarGuidePracticeIcon),
        ),
        findsWidgets,
      );
      for (final topic in CalendarGuideTopic.values) {
        expect(
          find.descendant(of: card, matching: _page(topic)),
          findsNothing,
          reason: topic.slug,
        );
      }
    });
  }

  testWidgets('a quoted label is searchable: "Speichern" finds the de Add '
      'row', (tester) async {
    await tester.pumpWidget(_host(locale: const Locale('de')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Speichern');
    await tester.pumpAndSettle();
    expect(_row('add-event'), findsOneWidget);
    expect(_row('month'), findsNothing);
  });

  group('no overflow and no clipped label at text scale 2.0', () {
    for (final locale in const [Locale('de'), Locale('ro')]) {
      for (final size in const [Size(360, 780), Size(412, 915)]) {
        for (final brightness in Brightness.values) {
          testWidgets('${locale.languageCode} ${size.width.toInt()}×'
              '${size.height.toInt()} ${brightness.name}', (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(
              _host(
                locale: locale,
                brightness: brightness,
                textScaler: const TextScaler.linear(2.0),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            _expectNoClippedText(tester);

            for (final topic in _hubOrder) {
              await _scrollTo(tester, _page(topic));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              _expectNoClippedText(tester);
            }
          });
        }
      }
    }
  });
}
