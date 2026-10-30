import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_guide_content.dart';
import 'package:anta/pages/calendar_guide_topic_page.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/guide_try_card_robot.dart';

Widget _host(
  CalendarGuideTopic topic, {
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
    home: CalendarGuideTopicPage(topic: topic),
  );
}

Finder _list() => find
    .descendant(
      of: find.byType(SettingsSectionList),
      matching: find.byType(Scrollable),
    )
    .first;

Finder _row(String slug) =>
    find.bySemanticsIdentifier(SemanticsIds.calendarGuideRow(slug));

Future<void> _scrollTo(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(
      finder,
      300,
      scrollable: _list(),
      // German at text scale 2.0 on a 360-wide phone runs to many screens.
      maxScrolls: 200,
    );

/// Every string drawn under [row], highlighted or not.
Iterable<String> _textsUnder(WidgetTester tester, Finder row) => tester
    .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
    .map((text) => text.data ?? text.textSpan!.toPlainText());

/// No laid-out text on the page is cut: every paragraph is as tall as its
/// lines need and none ran out of lines. The bar's title is the kit's bar's.
/// The unseen copies that size a slot are not drawn: a stand-in cut at its
/// row's limit is not a clipped label.
void _expectNoClippedText(WidgetTester tester) {
  final paragraphs = tester.renderObjectList<RenderParagraph>(
    find.descendant(
      of: find.byType(SettingsSectionList),
      matching: find.byType(RichText),
    ),
  );
  bool unseen(RenderObject paragraph) {
    for (RenderObject? o = paragraph; o != null; o = o.parent) {
      if (o is RenderOpacity && o.opacity == 0) return true;
    }
    return false;
  }

  for (final paragraph in paragraphs) {
    if (unseen(paragraph)) continue;
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

/// §7.5's keep list of docs/calendar-guide-page.md (D41): the frozen row ids
/// that survive the coach rework, page by page, in page order.
const Map<CalendarGuideTopic, List<String>> _slugs = {
  CalendarGuideTopic.screen: ['marks', 'views'],
  CalendarGuideTopic.events: [
    'description',
    'priority',
    'unsaved',
    'templates',
  ],
  CalendarGuideTopic.kinds: [
    'kinds-one-change',
    'kinds-tricky',
    'kinds-birthday',
    'kinds-only-repeat',
  ],
  CalendarGuideTopic.alerts: [
    'alert-kinds',
    'permissions',
    'ring',
    'open-often',
  ],
  CalendarGuideTopic.attendance: ['assume', 'rail', 'per-day'],
  CalendarGuideTopic.categories: ['category', 'cat-change', 'cat-alerts'],
  CalendarGuideTopic.finding: ['filters', 'overview'],
  CalendarGuideTopic.setup: ['settings', 'language'],
  CalendarGuideTopic.good: ['opening', 'back', 'notes'],
};

void main() {
  final en = AppLocalizationsEn();
  late AppDatabase db;

  // Real glyphs: the test font draws every glyph a full em wide, and the
  // "Try it" stages hold real rows whose values clamp at two lines — the
  // clipping checks below would be measuring the font.
  setUpAll(loadGoldenFonts);

  // The events and kinds cards read the calendar's look once; an unbound
  // service would leave a half-built singleton behind for the next case.
  setUp(() async {
    db = await openTestDatabase();
    SettingsService.reset();
    SettingsService.forTesting(db);
  });

  tearDown(() async {
    SettingsService.reset();
    await db.close();
  });

  test('the catalogue holds the keep list, in order, each slug once', () {
    for (final topic in CalendarGuideTopic.values) {
      expect(
        topic.rows(en).map((row) => row.slug).toList(),
        _slugs[topic],
        reason: topic.slug,
      );
    }
    final all = [
      for (final topic in CalendarGuideTopic.values)
        ...topic.rows(en).map((row) => row.slug),
    ];
    expect(all.toSet(), hasLength(all.length));
  });

  for (final topic in CalendarGuideTopic.values) {
    testWidgets('${topic.slug}: the heading, the lead and every row', (
      tester,
    ) async {
      await tester.pumpWidget(_host(topic));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(SemanticsIds.calendarGuideTopic(topic.slug)),
        findsOneWidget,
      );
      // The bar names the guide; the page's own name is the list's heading.
      expect(find.text(en.calendarGuideTitle), findsOneWidget);
      // No search field of the page's own; the finding card's is its stage's.
      expect(
        find.byType(TextField),
        topic == CalendarGuideTopic.finding ? findsOneWidget : findsNothing,
      );
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(
            SemanticsIds.calendarGuideTry(topic.slug),
          ),
          matching: find.byType(TextField),
        ),
        topic == CalendarGuideTopic.finding ? findsOneWidget : findsNothing,
      );
      final heading = tester
          .getSemantics(find.text(topic.title(en)))
          .getSemanticsData();
      expect(heading.flagsCollection.isHeader, isTrue);
      expect(heading.headingLevel, 1);
      final lead = topic.lead(en);
      if (lead != null) expect(find.text(lead), findsOneWidget);
      // A page with something to try opens on its "Try it" card; "How it
      // works" follows it.
      await _scrollTo(tester, find.text(en.calendarGuideHowItWorks));
      expect(find.text(en.calendarGuideHowItWorks), findsOneWidget);

      for (final row in topic.rows(en)) {
        await _scrollTo(tester, _row(row.slug));
        expect(_row(row.slug), findsOneWidget, reason: row.slug);
        expect(
          find.descendant(of: _row(row.slug), matching: find.text(row.title)),
          findsOneWidget,
          reason: row.slug,
        );
      }
    });
  }

  testWidgets('a row is read, never pressed, and TalkBack reads it as one '
      'node', (tester) async {
    await tester.pumpWidget(_host(CalendarGuideTopic.events));
    await tester.pumpAndSettle();

    final body = en.calendarGuideTemplatesBody(en.saveAsTemplate);
    await _scrollTo(tester, find.text(body));
    final row = _row('templates');
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
      find.text(en.calendarGuideTemplatesTitle),
    );
    final bodyNode = tester.getSemantics(find.text(body));
    expect(identical(titleNode, bodyNode), isTrue);
    final data = titleNode.getSemanticsData();
    expect(data.label, contains(en.calendarGuideTemplatesTitle));
    expect(data.label, contains(body));
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    expect(data.flagsCollection.isButton, isFalse);
  });

  group('the guide quotes the live labels', () {
    for (final (locale, l10n, open, close) in [
      (const Locale('en'), en as AppLocalizations, '“', '”'),
      (const Locale('de'), AppLocalizationsDe() as AppLocalizations, '„', '“'),
    ]) {
      testWidgets('${locale.languageCode}: events', (tester) async {
        await tester.pumpWidget(
          _host(CalendarGuideTopic.events, locale: locale),
        );
        await tester.pumpAndSettle();

        await _scrollTo(tester, _row('unsaved'));
        expect(
          _textsUnder(tester, _row('unsaved')),
          contains(contains('$open${l10n.save}$close')),
        );
      });

      testWidgets('${locale.languageCode}: alerts', (tester) async {
        await tester.pumpWidget(
          _host(CalendarGuideTopic.alerts, locale: locale),
        );
        await tester.pumpAndSettle();

        await _scrollTo(tester, _row('alert-kinds'));
        expect(
          _textsUnder(tester, _row('alert-kinds')),
          contains(contains('$open${l10n.eventAlertModeRing}$close')),
        );
      });

      testWidgets('${locale.languageCode}: attendance', (tester) async {
        await tester.pumpWidget(
          _host(CalendarGuideTopic.attendance, locale: locale),
        );
        await tester.pumpAndSettle();

        await _scrollTo(tester, _row('rail'));
        expect(
          _textsUnder(tester, _row('rail')),
          contains(contains('$open${l10n.eventShowInDayRailAuto}$close')),
        );
      });
    }
  });

  // D51 and D52: in German at 2.0 on the small phone the stage the first
  // instruction points at starts on the first screen — the heading stops
  // growing at 1.5, and the events card's report no longer sizes its line.
  for (final topic in const [
    CalendarGuideTopic.events,
    CalendarGuideTopic.categories,
  ]) {
    testWidgets('${topic.slug}: de 2.0 on 360 × 780 opens with the stage on '
        'screen, under a heading clamped at 1.5', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          topic,
          locale: const Locale('de'),
          textScaler: const TextScaler.linear(2.0),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final stage = GuideTryCardRobot(tester, topic.slug).stageRect;
      expect(stage.top, lessThan(780));

      final heading = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text(topic.title(AppLocalizationsDe())),
          matching: find.byType(RichText),
        ),
      );
      expect(
        heading.textScaler.scale(FormMetrics.titleFontSize),
        lessThanOrEqualTo(1.5 * FormMetrics.titleFontSize),
      );
    });
  }

  group(
    'the kinds page: no overflow and no clipped label at text scale 2.0',
    () {
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
                  CalendarGuideTopic.kinds,
                  locale: locale,
                  brightness: brightness,
                  textScaler: const TextScaler.linear(2.0),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              _expectNoClippedText(tester);

              for (final slug in _slugs[CalendarGuideTopic.kinds]!) {
                await _scrollTo(tester, _row(slug));
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
                _expectNoClippedText(tester);
              }
            });
          }
        }
      }
    },
  );
}
