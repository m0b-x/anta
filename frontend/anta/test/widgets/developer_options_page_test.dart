import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// The developer options page's smoke suite (D14 of
/// `docs/settings-rework-roadmap.md`), pinned before a slice of the settings
/// rework relocates it: it opens, measures at de 2.0 on the small phone, and
/// its one destructive control is pinned as it is today.
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

  // Today's state: the reset has no confirmation, so there is no dialog to
  // cancel. It deletes the stored row, which also holds the unlock — the
  // page stays open on an unlocked session, and the next launch starts
  // locked.
  testWidgets('Reset to defaults acts at once with no confirmation and '
      'deletes the stored row, unlock included (known; S24, deferred to §9)', (
    tester,
  ) async {
    await pumpPage(tester);

    await scrollTo(tester, find.text(l10n.resetToDefaults));
    await tester.tap(find.text(l10n.resetToDefaults));
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(l10n.developerOptionsReset), findsOneWidget);
    expect(DevOptions.instance.showWhitespace, isFalse);
    expect(DevOptions.instance.developerModeUnlocked, isTrue);
    expect(await stored(tester), isNull);

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

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
