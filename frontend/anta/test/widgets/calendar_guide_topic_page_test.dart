import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_guide_content.dart';
import 'package:anta/pages/calendar_guide_topic_page.dart';
import 'package:anta/widgets/settings_section_list.dart';

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

/// §8.2 table 4 of docs/calendar-guide-page.md, with the priority row after
/// description (D36): the frozen row ids, page by page, in page order.
const Map<CalendarGuideTopic, List<String>> _slugs = {
  CalendarGuideTopic.screen: ['month', 'marks', 'panel', 'views'],
  CalendarGuideTopic.events: [
    'add-event',
    'time',
    'open',
    'description',
    'priority',
    'unsaved',
    'templates',
  ],
  CalendarGuideTopic.kinds: [
    'repeat',
    'kinds-one',
    'kinds-dates',
    'kinds-only-one',
    'kinds-only-repeat',
    'kinds-one-change',
    'kinds-tricky',
    'kinds-birthday',
    'skipped',
  ],
  CalendarGuideTopic.alerts: [
    'add-alert',
    'alert-kinds',
    'permissions',
    'ring',
    'open-often',
    'quick-alarm',
    'hub',
  ],
  CalendarGuideTopic.attendance: [
    'attendance',
    'assume',
    'count',
    'rail',
    'per-day',
  ],
  CalendarGuideTopic.categories: [
    'category',
    'cat-create',
    'cat-change',
    'cat-hide',
    'cat-delete',
    'cat-alerts',
  ],
  CalendarGuideTopic.finding: ['search', 'filters', 'overview'],
  CalendarGuideTopic.setup: ['settings', 'holidays', 'week-start', 'language'],
  CalendarGuideTopic.good: ['opening', 'back', 'notes'],
};

void main() {
  final en = AppLocalizationsEn();

  test('the catalogue holds table 4, in order, each slug once', () {
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
      expect(find.byType(TextField), findsNothing);
      final heading = tester
          .getSemantics(find.text(topic.title(en)))
          .getSemanticsData();
      expect(heading.flagsCollection.isHeader, isTrue);
      expect(heading.headingLevel, 1);
      final lead = topic.lead(en);
      if (lead != null) expect(find.text(lead), findsOneWidget);
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

    final body = en.calendarGuideAddBody(en.save);
    await _scrollTo(tester, find.text(body));
    final row = _row('add-event');
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byType(ListTile)),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.byType(InkWell)),
      findsNothing,
    );

    final titleNode = tester.getSemantics(find.text(en.calendarGuideAddTitle));
    final bodyNode = tester.getSemantics(find.text(body));
    expect(identical(titleNode, bodyNode), isTrue);
    final data = titleNode.getSemanticsData();
    expect(data.label, contains(en.calendarGuideAddTitle));
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

        await _scrollTo(tester, _row('add-event'));
        expect(
          _textsUnder(tester, _row('add-event')),
          contains(contains('$open${l10n.save}$close')),
        );
      });

      testWidgets('${locale.languageCode}: alerts', (tester) async {
        await tester.pumpWidget(
          _host(CalendarGuideTopic.alerts, locale: locale),
        );
        await tester.pumpAndSettle();

        await _scrollTo(tester, _row('add-alert'));
        expect(
          _textsUnder(tester, _row('add-alert')),
          contains(contains('$open${l10n.eventAlertAdd}$close')),
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
