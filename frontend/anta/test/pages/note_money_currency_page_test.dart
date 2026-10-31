import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/pages/note_money_currency_page.dart';
import 'package:anta/services/settings_service.dart';

import '../goldens/support/golden_fonts.dart';
import '../widgets/support/layout_errors.dart';

/// The per-note currency page's smoke suite (D14 of
/// `docs/settings-rework-roadmap.md`), pinned before S6 of the settings
/// rework names its row menus (S18): it opens on two notes, measures at
/// de 2.0 on the small phone, a row's menu opens and dismisses, and its
/// custom-symbol dialog cancels — each with nothing written.
///
/// The page opens `AppDatabase.getInstance()` and `SettingsService` itself,
/// so the suite runs over the file-backed database in a temporary documents
/// directory, opened in real async.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<String> noteIds;

  final l10n = AppLocalizationsEn();

  setUpAll(() async {
    // Measured with Roboto: the test font's square glyphs are about twice as
    // wide, and would report overflows no device shows.
    await loadGoldenFonts();
    tempDir = await Directory.systemTemp.createTemp('anta_note_currency');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    // Opened here, in real async: inside `testWidgets` the database answers
    // on a background isolate that `FakeAsync` never lets run.
    final db = await AppDatabase.getInstance();
    final folder = await db.folderDao.createFolder(name: 'Training');
    noteIds = [
      for (final title in ['Leg day', 'Arm day'])
        (await db.noteDao.createNote(folderId: folder.id, title: title)).id,
    ];
    await SettingsService.getInstance();
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Hands the real event loop back so the page's reads land, then flushes
  /// their `setState`s into frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(412, 915),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const NoteMoneyCurrencyPage(),
      ),
    );
    await settle(tester);
  }

  /// Every stored setting, where a per-note currency would land.
  Future<Map<String, String>> storedSettings(WidgetTester tester) async =>
      (await tester.runAsync(
        () async =>
            (await AppDatabase.getInstance()).userSettingsDao.getAllSettings(),
      ))!;

  /// Each seeded note's override as the page reads it back.
  Future<List<Object?>> storedOverrides(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final settings = await SettingsService.getInstance();
        return [
          for (final id in noteIds) await settings.getNoteMoneyCurrency(id),
        ];
      }))!;

  Finder rowMenu(String title) => find.descendant(
    of: find.widgetWithText(ListTile, title),
    matching: find.byType(PopupMenuButton<int>),
  );

  Future<void> openRowMenu(WidgetTester tester, String title) async {
    await tester.tap(rowMenu(title));
    await tester.pumpAndSettle();
  }

  testWidgets('it opens on every note, each on the global currency, sorted '
      'by title', (tester) async {
    await pumpPage(tester);

    expect(find.text(l10n.useGlobalCurrency), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Arm day')).dy,
      lessThan(tester.getTopLeft(find.text('Leg day')).dy),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets("a row's menu opens on the global currency, the presets and "
      'the custom symbol, and dismisses writing nothing', (tester) async {
    await pumpPage(tester);
    final before = await storedSettings(tester);

    await openRowMenu(tester, 'Leg day');
    expect(
      find.widgetWithText(PopupMenuItem<int>, l10n.useGlobalCurrency),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(PopupMenuItem<int>, l10n.moneyCustomSymbol),
      findsOneWidget,
    );
    expect(find.byType(PopupMenuItem<int>), findsNWidgets(5));

    // Outside the menu: the barrier's dismiss, as a tap beside it does.
    await tester.tapAt(const Offset(8, 8));
    await settle(tester);

    expect(find.byType(PopupMenuItem<int>), findsNothing);
    expect(find.text(l10n.useGlobalCurrency), findsNWidgets(2));
    expect(await storedSettings(tester), before);
    expect(await storedOverrides(tester), [null, null]);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the custom symbol dialog, typed into and cancelled, writes '
      'nothing', (tester) async {
    await pumpPage(tester);
    final before = await storedSettings(tester);

    await openRowMenu(tester, 'Leg day');
    await tester.tap(
      find.widgetWithText(PopupMenuItem<int>, l10n.moneyCustomSymbol),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'kr',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sheetCancel));
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('kr'), findsNothing);
    expect(find.text(l10n.useGlobalCurrency), findsNWidgets(2));
    expect(await storedSettings(tester), before);
    expect(await storedOverrides(tester), [null, null]);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('smoke', () {
    Future<void> pumpSmall(WidgetTester tester) => pumpPage(
      tester,
      size: const Size(360, 780),
      locale: const Locale('de'),
      textScale: 2.0,
    );

    testWidgets('de 2.0 on 360 × 780 fits with no exception', (tester) async {
      final errors = await layoutErrorsDuring(() => pumpSmall(tester));

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);
      expect(find.text('Leg day'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // Today's state, pinned so S6 sees it change: the menu's "Use global
    // currency" item is a Row of an icon, a gap and an unbounded Text, and
    // "Globale Währung verwenden" at 2.0 runs 130 dp past the width the
    // menu gives it (measured 2026-10-31). When S6 bounds the label, this
    // expectation flips to `isEmpty`.
    testWidgets("de 2.0 on 360 × 780, the row menu's global item overflows "
        'on the right (known, S6)', (tester) async {
      await pumpSmall(tester);
      final errors = await layoutErrorsDuring(
        () => openRowMenu(tester, 'Leg day'),
      );

      expect(errors, hasLength(1));
      expect(
        errors.single.exceptionAsString(),
        allOf(contains('RenderFlex overflowed'), contains('on the right')),
      );
      expect(
        errors.single.toString(),
        contains('note_money_currency_page.dart'),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('de 2.0 on 360 × 780, the custom symbol dialog fits with no '
        'exception', (tester) async {
      await pumpSmall(tester);
      // The menu's own overflow is the test above's.
      await layoutErrorsDuring(() => openRowMenu(tester, 'Leg day'));
      final errors = await layoutErrorsDuring(() async {
        await tester.tap(find.byType(PopupMenuItem<int>).last);
        await tester.pumpAndSettle();
      });

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
