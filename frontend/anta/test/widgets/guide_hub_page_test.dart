import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/guide_book.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/pages/calendar_guide_page.dart';
import 'package:anta/pages/guide_book_page.dart';
import 'package:anta/pages/guide_hub_page.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';

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
    home: const GuideHubPage(),
  );
}

/// The hub's section list's own scrollable — the search field has one too.
Finder _list() => find
    .descendant(
      of: find.descendant(
        of: find.byType(GuideHubPage),
        matching: find.byType(SettingsSectionList),
      ),
      matching: find.byType(Scrollable),
    )
    .first;

Finder _book(GuideBook book) =>
    find.bySemanticsIdentifier(SemanticsIds.guideHubBook(book.slug));

Future<void> _scrollTo(WidgetTester tester, Finder finder) => tester
    .scrollUntilVisible(finder, 300, scrollable: _list(), maxScrolls: 200);

/// A section's header as the kit draws it: the browser's uppercase label.
Finder _header(String title) => find.text(title.toUpperCase());

/// The kit's section [finder] sits in — its header and its group of rows.
Finder _cardOf(Finder finder) =>
    find.ancestor(of: finder, matching: find.byType(SettingsSectionCard)).first;

/// No laid-out text in the hub's list is cut: every paragraph is as tall as
/// its lines need and none ran out of lines. The search field's hint is the
/// kit's, cut at 2.0 on every settings page alike, and is left out.
void _expectNoClippedText(WidgetTester tester) {
  final paragraphs = tester.renderObjectList<RenderParagraph>(
    find.descendant(
      of: find.descendant(
        of: find.byType(GuideHubPage),
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
  late AppDatabase db;

  // A book's page reads the money config and the palette once; an unbound
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

  testWidgets('the hub lists the three guides under one card, by id', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier(SemanticsIds.guideHub), findsOneWidget);
    expect(find.text(en.howToUseAnta), findsOneWidget);
    expect(find.text(en.guideHubIntro), findsOneWidget);
    final card = _cardOf(_header(en.guideHubSectionGuides));
    for (final book in GuideBook.values) {
      expect(
        find.descendant(of: card, matching: _book(book)),
        findsOneWidget,
        reason: book.slug,
      );
      expect(
        find.descendant(of: _book(book), matching: find.text(book.title(en))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _book(book), matching: find.text(book.caption(en))),
        findsOneWidget,
      );
    }
    // Top to bottom: the calendar, the notes, the app.
    final tops = [
      for (final book in GuideBook.values) tester.getTopLeft(_book(book)).dy,
    ];
    expect(tops[1], greaterThan(tops[0]));
    expect(tops[2], greaterThan(tops[1]));
  });

  testWidgets('each guide row pushes its guide, stamped, and back returns to '
      'the hub', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    for (final (book, page, kind, listId) in [
      (
        GuideBook.calendar,
        CalendarGuidePage,
        NavDestinationKind.calendarGuide,
        SemanticsIds.calendarGuide,
      ),
      (
        GuideBook.notes,
        GuideBookPage,
        NavDestinationKind.notesGuide,
        SemanticsIds.guideBook('notes'),
      ),
      (
        GuideBook.app,
        GuideBookPage,
        NavDestinationKind.appGuide,
        SemanticsIds.guideBook('app'),
      ),
    ]) {
      await tester.tap(_book(book));
      await tester.pumpAndSettle();

      final pushed = find.byWidgetPredicate(
        (widget) => widget.runtimeType == page,
      );
      expect(pushed, findsOneWidget, reason: book.slug);
      if (page == GuideBookPage) {
        expect(tester.widget<GuideBookPage>(pushed).book, book);
      }
      expect(find.bySemanticsIdentifier(listId), findsOneWidget);
      final route = ModalRoute.of(tester.element(pushed))!;
      expect(route.settings.arguments, NavDestination(kind));

      Navigator.of(tester.element(pushed)).pop();
      await tester.pumpAndSettle();
      expect(pushed, findsNothing);
      expect(find.byType(GuideHubPage), findsOneWidget);
    }
  });

  group('the search reaches every page of every guide (D2)', () {
    for (final (name, query, rowId, pageId, pageTitle) in [
      (
        'a calendar word',
        en.calendarGuideTemplatesTitle,
        SemanticsIds.calendarGuideRow('templates'),
        SemanticsIds.calendarGuidePage('events'),
        en.calendarGuidePageEvents,
      ),
      (
        'a notes word',
        en.notesGuideBasicsSortTitle,
        SemanticsIds.guideBookRow('notes', 'basics-sort'),
        SemanticsIds.guideBookPage('notes', 'basics'),
        en.notesGuidePageBasics,
      ),
      (
        'an app word',
        en.appGuideBackupFolderTitle,
        SemanticsIds.guideBookRow('app', 'backup-folder'),
        SemanticsIds.guideBookPage('app', 'backup'),
        en.appGuidePageBackup,
      ),
    ]) {
      testWidgets('$name is found under its page\'s name, and clearing the '
          'search restores the hub', (tester) async {
        await tester.pumpWidget(_host());
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), query);
        await tester.pumpAndSettle();

        await _scrollTo(tester, find.bySemanticsIdentifier(rowId));
        final row = find.bySemanticsIdentifier(rowId);
        expect(row, findsOneWidget);
        final card = _cardOf(row);
        expect(
          find.descendant(of: card, matching: _header(pageTitle)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.bySemanticsIdentifier(pageId),
          ),
          findsOneWidget,
        );
        for (final book in GuideBook.values) {
          expect(_book(book), findsNothing, reason: book.slug);
        }

        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        expect(find.bySemanticsIdentifier(rowId), findsNothing);
        for (final book in GuideBook.values) {
          expect(_book(book), findsOneWidget, reason: book.slug);
        }
      });
    }

    testWidgets("a search hit's page row opens that book's page", (
      tester,
    ) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        en.appGuideBackupFolderTitle,
      );
      await tester.pumpAndSettle();
      final page = find.bySemanticsIdentifier(
        SemanticsIds.guideBookPage('app', 'backup'),
      );
      await _scrollTo(tester, page);
      await tester.pumpAndSettle();
      await tester.tap(page);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(
          SemanticsIds.guideBookTopic('app', 'backup'),
        ),
        findsOneWidget,
      );
    });
  });

  group('no overflow and no clipped label at text scale 2.0', () {
    for (final locale in const [Locale('de'), Locale('ro')]) {
      testWidgets('${locale.languageCode} 360×780: the hub and a search', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(locale: locale, textScaler: const TextScaler.linear(2.0)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        _expectNoClippedText(tester);
        for (final book in GuideBook.values) {
          await _scrollTo(tester, _book(book));
          expect(tester.takeException(), isNull);
          _expectNoClippedText(tester);
        }

        final l10n = lookupAppLocalizations(locale);
        await tester.enterText(
          find.byType(TextField),
          l10n.appGuideBackupFolderTitle,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        _expectNoClippedText(tester);
      });
    }
  });
}
