import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/dev_options.dart';
import 'package:anta/pages/developer_options_page.dart';
import 'package:anta/services/dev_options_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../goldens/support/golden_fonts.dart';
import 'support/layout_errors.dart';
import 'support/settings_page_whole.dart';

/// The developer options page's smoke suite (D14 of
/// `docs/settings-rework-roadmap.md`), pinned before a slice of the settings
/// rework relocates it: it opens, measures at de 2.0 on the small phone, and
/// its one destructive control asks before it acts (S6).
///
/// The page reaches `DevOptionsService` through its singleton, which opens
/// `AppDatabase.getInstance()`, so the suite runs over the file-backed
/// database in a temporary documents directory, opened in real async.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storeKey = 'dev_options';

  late Directory tempDir;

  final l10n = AppLocalizationsEn();

  setUpAll(() async {
    // Measured with Roboto: the test font's square glyphs are about twice as
    // wide, and would report overflows no device shows.
    await loadGoldenFonts();
    tempDir = await Directory.systemTemp.createTemp('anta_developer_options');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    // Opened here, in real async: inside `testWidgets` the database answers
    // on a background isolate that `FakeAsync` never lets run.
    final db = await AppDatabase.getInstance();
    await db.customSelect('SELECT 1').get();
    await SettingsService.getInstance();
  });

  setUp(() async {
    // Unlocked, with one option on, as a developer leaves it.
    DevOptions.instance.lockDeveloperMode();
    final db = await AppDatabase.getInstance();
    await db.userSettingsDao.setValue(
      storeKey,
      jsonEncode({'developerModeUnlocked': true, 'showWhitespace': true}),
    );
    DevOptionsService.reset();
    await DevOptionsService.getInstance();
  });

  tearDown(() async {
    DevOptions.instance.lockDeveloperMode();
    DevOptionsService.reset();
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Hands the real event loop back so the page's reads and writes land,
  /// then flushes their `setState`s into frames.
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
        home: const DeveloperOptionsPage(),
      ),
    );
    await settle(tester);
  }

  Future<String?> stored(WidgetTester tester) => tester.runAsync<String?>(
    () async =>
        (await AppDatabase.getInstance()).userSettingsDao.getValue(storeKey),
  );

  Future<void> scrollTo(WidgetTester tester, Finder target) =>
      tester.scrollUntilVisible(
        target,
        200,
        scrollable: find
            .descendant(
              of: find.byType(SettingsSectionList),
              matching: find.byType(Scrollable),
            )
            .first,
      );

  testWidgets('it opens on the stored options with the warning, the toggles '
      'and both footer buttons', (tester) async {
    await pumpPage(tester);

    expect(find.text(l10n.developerOptionsWarning), findsOneWidget);
    final whitespace = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, l10n.showWhitespace),
    );
    expect(whitespace.value, isTrue);
    await scrollTo(tester, find.text(l10n.lockDeveloperMode));
    expect(find.text(l10n.resetToDefaults), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // Pinned at S0 as acting at once. The reset still deletes the stored row,
  // which also holds the unlock — the page stays open on an unlocked
  // session and the next launch starts locked (moving the unlock out of the
  // row is S24, §9) — but it asks first, and the question says so.
  testWidgets('Reset to defaults asks first; cancel keeps the row; yes '
      'deletes it, unlock included', (tester) async {
    await pumpPage(tester);
    final before = await stored(tester);
    final reset = find.bySemanticsIdentifier(
      SemanticsIds.developerOptionsReset,
    );

    await scrollTo(tester, reset);
    await tester.tap(reset);
    await settle(tester);
    expect(find.text(l10n.developerOptionsResetConfirm), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sheetCancel));
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(l10n.developerOptionsReset), findsNothing);
    expect(DevOptions.instance.showWhitespace, isTrue);
    expect(await stored(tester), before);

    await tester.tap(reset);
    await settle(tester);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sheetConfirm));
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(l10n.developerOptionsReset), findsOneWidget);
    expect(DevOptions.instance.showWhitespace, isFalse);
    expect(DevOptions.instance.developerModeUnlocked, isTrue);
    expect(await stored(tester), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the list, every switch row and both footer buttons carry '
      'their ids', (tester) async {
    await pumpPage(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.developerOptionsList),
      findsOneWidget,
    );
    for (final id in [
      for (final key in const [
        'colorMarkdownBlocks',
        'showBlockBoundaries',
        'showWhitespace',
        'showAddButtonTrace',
        'showRenderTime',
        'showFpsCounter',
        'showChunkIndicators',
        'showRepaintRainbow',
        'showCursorInfo',
        'showSelectionDetails',
        'logParserEvents',
        'showNoteSize',
        'showDatabaseStats',
      ])
        SemanticsIds.developerOption(key),
      SemanticsIds.developerOptionsReset,
      SemanticsIds.developerOptionsLock,
    ]) {
      await scrollTo(tester, find.bySemanticsIdentifier(id));
      expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // A probe popped the hub too: both taps resumed after the pending save.
  testWidgets('a double tap on Lock while the save is pending pops one route '
      'and shows one snackbar', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final observer = _PopCounter();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Text('root')),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('hub')),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const DeveloperOptionsPage()),
    );
    await settle(tester);
    final lock = find.bySemanticsIdentifier(SemanticsIds.developerOptionsLock);
    await scrollTo(tester, lock);
    await tester.ensureVisible(lock);
    await tester.pump();

    // No real async between the taps: the file-backed save stays pending.
    await tester.tap(lock);
    await tester.pump(const Duration(milliseconds: 80));
    expect(observer.pops, 0, reason: 'the save is still pending');
    await tester.tap(lock);
    await tester.pump(const Duration(milliseconds: 1));
    // Distinct bars, not nodes: while the route leaves, the messenger shows
    // the one bar on both the leaving and the revealed scaffold.
    final snackbars = Set<Widget>.identity();
    for (var i = 0; i < 14; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      snackbars.addAll(find.byType(SnackBar).evaluate().map((e) => e.widget));
    }
    await settle(tester);

    expect(observer.pops, 1);
    expect(snackbars, hasLength(1));
    expect(find.text('hub'), findsOneWidget);
    expect(DevOptions.instance.developerModeUnlocked, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('de 2.0 on 360 × 780 fits with no exception', (tester) async {
    final errors = await layoutErrorsDuring(() async {
      await pumpPage(
        tester,
        size: const Size(360, 780),
        locale: const Locale('de'),
        textScale: 2.0,
      );
      await scrollTo(tester, find.byIcon(Icons.lock_rounded));
    });

    expect(errors.map((e) => e.exceptionAsString()), isEmpty);
    expect(tester.takeException(), isNull);
    expect(await stored(tester), isNotNull);

    // Whole words too: "Datenbankstati|stik" and "Animati|onsleistung"
    // broke before the copy hyphenated them. Back to the top for the sweep.
    await tester.drag(find.byType(ListView), const Offset(0, 20000));
    await tester.pumpAndSettle();
    await expectPageWhole(tester);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _PopCounter extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}
