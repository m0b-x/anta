import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/pages/calendar_guide_page.dart';
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

/// The section list's own scrollable — the search field has one too.
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
      // German at text scale 2.0 on a 360-wide phone is over 20,000 px tall.
      maxScrolls: 200,
    );

/// Every string drawn under [row], highlighted or not.
Iterable<String> _textsUnder(WidgetTester tester, Finder row) => tester
    .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
    .map((text) => text.data ?? text.textSpan!.toPlainText());

void main() {
  final en = AppLocalizationsEn();

  testWidgets('every section title and every row title is on the page', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(
      find.text(en.calendarGuideIntro(en.calendarGuideTitle)),
      findsOneWidget,
    );
    for (final title in [
      en.calendarGuideSectionCalendar,
      en.calendarGuideMonthTitle,
      en.calendarGuideMarksTitle,
      en.calendarGuidePanelTitle,
      en.calendarGuideViewsTitle,
      en.calendarGuideSectionEvents,
      en.calendarGuideAddTitle,
      en.calendarGuideTimeTitle,
      en.calendarGuideCategoryTitle,
      en.calendarGuideRepeatTitle,
      en.calendarGuideOpenTitle,
      en.calendarGuideDescriptionTitle,
      en.calendarGuideUnsavedTitle(en.save),
      en.calendarGuideTrackTitle,
      en.calendarGuideTemplatesTitle,
      en.calendarGuideSectionAlerts,
      en.calendarGuideAlertAddTitle,
      en.calendarGuideAlertKindsTitle,
      en.calendarGuidePermissionsTitle,
      en.calendarGuideRingTitle,
      en.calendarGuideOpenOftenTitle,
      en.calendarGuideQuickAlarmTitle,
      en.calendarGuideHubTitle,
      en.calendarGuideSectionFinding,
      en.calendarGuideSearchTitle,
      en.calendarGuideOverviewTitle,
      en.calendarGuideFiltersTitle,
      en.calendarGuideSectionSettings,
      en.calendarGuideSettingsTitle,
      en.calendarGuideHolidaysTitle,
      en.calendarGuideWeekStartTitle,
      en.calendarGuideCategoriesTitle,
      en.calendarGuideLanguageTitle,
      en.calendarGuideSectionGood,
      en.calendarGuideOpeningTitle,
      en.calendarGuideBackTitle,
      en.calendarGuideNotesTitle,
    ]) {
      await _scrollTo(tester, find.text(title));
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('the search narrows the rows and clearing it restores them', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    final field = find.byType(TextField);

    await tester.enterText(field, 'repeat');
    await tester.pumpAndSettle();
    expect(_row('repeat'), findsOneWidget);
    expect(_row('add-event'), findsNothing);
    expect(
      find.text(en.calendarGuideIntro(en.calendarGuideTitle)),
      findsNothing,
    );

    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text(en.calendarGuideAddTitle));
    expect(_row('add-event'), findsOneWidget);
    await _scrollTo(tester, find.text(en.calendarGuideRepeatTitle));
    expect(_row('repeat'), findsOneWidget);

    await tester.enterText(field, 'zzqxj');
    await tester.pumpAndSettle();
    expect(find.text(en.noMatchesFound), findsOneWidget);
  });

  testWidgets('a quoted label is searchable: "Speichern" finds the de Add '
      'row', (tester) async {
    await tester.pumpWidget(_host(locale: const Locale('de')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Speichern');
    await tester.pumpAndSettle();
    expect(_row('add-event'), findsOneWidget);
    expect(_row('month'), findsNothing);
  });

  group('the guide quotes the live labels', () {
    for (final (locale, l10n, open, close) in [
      (const Locale('en'), en as AppLocalizations, '“', '”'),
      (const Locale('de'), AppLocalizationsDe() as AppLocalizations, '„', '“'),
    ]) {
      testWidgets(locale.languageCode, (tester) async {
        await tester.pumpWidget(_host(locale: locale));
        await tester.pumpAndSettle();

        await _scrollTo(tester, find.text(l10n.calendarGuideAddTitle));
        expect(
          _textsUnder(tester, _row('add-event')),
          contains(contains('$open${l10n.save}$close')),
        );

        await _scrollTo(tester, find.text(l10n.calendarGuideAlertAddTitle));
        expect(
          _textsUnder(tester, _row('add-alert')),
          contains(contains('$open${l10n.eventAlertAdd}$close')),
        );
      });
    }
  });

  group('no overflow at text scale 2.0', () {
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

            await _scrollTo(
              tester,
              find.text(lookupAppLocalizations(locale).calendarGuideNotesTitle),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(_row('notes'), findsOneWidget);
          });
        }
      }
    }
  });

  testWidgets('the list and its rows carry their automation ids', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.calendarGuide),
      findsOneWidget,
    );
    await _scrollTo(tester, find.text(en.calendarGuideAddTitle));
    expect(_row('add-event'), findsOneWidget);
    expect(
      SemanticsIds.calendarGuideRow('add-event'),
      'calendar-guide-add-event',
    );
  });

  testWidgets('a row is read, never pressed, and TalkBack reads it as one '
      'node', (tester) async {
    await tester.pumpWidget(_host());
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
}
