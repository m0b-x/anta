import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/label_appearance_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';

import '../goldens/support/golden_fonts.dart';
import 'support/layout_errors.dart';
import 'support/onboarding_robot.dart';
import 'support/settings_platform_fakes.dart';

/// The first-launch page's paths, pinned against today's behaviour before S3
/// (it scrolls) and S9 (its confirmation pluralizes) of the settings rework
/// (`docs/settings-rework-roadmap.md`, D9). Its import and restore-from-file
/// stay as they are; the record's rule is that they are never reordered or
/// rewritten, and this suite is how a diff proves it.
///
/// Everything runs for real over a temporary documents directory: the real
/// `DatabaseManager`, the file-backed `AppDatabase`, and the real backup
/// import, because the page reaches each through its singleton. Each
/// singleton is warmed in `setUp`, in the real async zone, so a test body
/// only ever queries an open database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const activeKey = 'active_database';

  final l10n = AppLocalizationsEn();

  late Directory tempDir;
  late SharedPreferences prefs;
  late DatabaseManager manager;
  late SettingsService settings;
  late PublicHolidayService holidays;
  late FakeFilePicker picker;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_onboarding');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await AppDatabase.deleteAllData();
    DatabaseLifecycle.notifyDatabaseSwitching();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    // A first launch: an empty directory, nothing chosen, nothing open.
    await AppDatabase.deleteAllData();
    DatabaseLifecycle.notifyDatabaseSwitching();
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    manager = await DatabaseManager.getInstance();
    await AppDatabase.getInstance();
    settings = await SettingsService.getInstance();
    holidays = await PublicHolidayService.getInstance();
    // What the JSON import reaches for, opened here rather than under the
    // test body's `FakeAsync`.
    await BackupService.getInstance();
    await SyncBindingService.getInstance();
    await CalendarPaletteService.getInstance();
    await LabelAppearanceService.getInstance();
    picker = FakeFilePicker()..install();
  });

  Future<bool> onboardingDone(WidgetTester tester) async =>
      (await tester.runAsync(settings.isOnboardingCompleted))!;

  /// The live folder names and note titles of the open database.
  Future<(List<String>, List<String>)> stored(WidgetTester tester) async {
    final rows = await tester.runAsync(() async {
      final db = await AppDatabase.getInstance();
      final folders = await db.folderDao.getAllFolders(includeDeleted: false);
      final notes = await db.noteDao.getAllNotes(includeDeleted: false);
      return (
        [for (final folder in folders) folder.name],
        [for (final note in notes) note.title],
      );
    });
    return rows!;
  }

  /// A minimal version-7 backup with one folder and one note in it, in the
  /// shape `BackupService.exportAllData` writes those two keys.
  Future<String> writeBackup(WidgetTester tester) async {
    final path = p.join(tempDir.path, 'picked', 'anta_backup.json');
    await tester.runAsync(() async {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'version': 7,
          'exportedAt': '2026-10-01T09:00:00.000',
          'folders': [
            {
              JsonKeys.id: 'f1',
              JsonKeys.name: 'Training',
              JsonKeys.parentId: null,
            },
          ],
          'notes': [
            {
              JsonKeys.id: 'n1',
              JsonKeys.folderId: 'f1',
              JsonKeys.title: 'Leg day',
              JsonKeys.content: 'squats',
            },
          ],
          'settings': <String, dynamic>{},
        }),
      );
    });
    return path;
  }

  group('start fresh', () {
    for (final (language, profile) in [
      ('en', HolidayProfile.generic),
      ('ro', HolidayProfile.romania),
      ('de', HolidayProfile.germany),
    ]) {
      testWidgets('in $language it sets the flag, picks the ${profile.name} '
          'holidays '
          'and completes', (tester) async {
        final robot = OnboardingRobot(tester);
        await robot.pump(locale: Locale(language));

        await robot.startFresh();
        await robot.settleUntil(() => robot.completions == 1);

        expect(await onboardingDone(tester), isTrue);
        expect(holidays.profile, profile);
        expect(PublicHolidays.profileForLanguage(language), profile);
        expect(prefs.getString(activeKey), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

  group('restore from a JSON backup', () {
    testWidgets('the backup is confirmed first; cancel imports nothing and '
        'stays on the page', (tester) async {
      picker.nextPath = await writeBackup(tester);
      final robot = OnboardingRobot(tester);
      await robot.pump();

      await robot.restoreFromBackup();
      await robot.settleUntil(() => robot.shows(l10n.confirmImport));
      // The counts' wording is S9's; only that they are offered is pinned.
      expect(robot.shows(l10n.backupContains), isTrue);

      await robot.cancelDialog();
      await robot.settleUntil(() => robot.showsChoices);

      expect(robot.showsDialog, isFalse);
      final (folders, notes) = await stored(tester);
      expect(folders, isEmpty);
      expect(notes, isEmpty);
      expect(await onboardingDone(tester), isFalse);
      expect(robot.completions, 0);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('confirming imports the backup, sets the flag and completes', (
      tester,
    ) async {
      picker.nextPath = await writeBackup(tester);
      final robot = OnboardingRobot(tester);
      await robot.pump();

      await robot.restoreFromBackup();
      await robot.settleUntil(() => robot.shows(l10n.confirmImport));
      await robot.confirmDialog();
      await robot.settleUntil(() => robot.completions == 1);

      final (folders, notes) = await stored(tester);
      expect(folders, ['Training']);
      expect(notes, ['Leg day']);
      expect(await onboardingDone(tester), isTrue);
      expect(robot.shows(l10n.importSuccess(1, 1)), isTrue);
      expect(prefs.getString(activeKey), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a JSON file that is not a backup is refused without a '
        'confirmation', (tester) async {
      final path = p.join(tempDir.path, 'picked', 'other.json');
      await tester.runAsync(() async {
        await Directory(p.dirname(path)).create(recursive: true);
        await File(path).writeAsString(jsonEncode({'hello': 'world'}));
      });
      picker.nextPath = path;
      final robot = OnboardingRobot(tester);
      await robot.pump();

      await robot.restoreFromBackup();
      await robot.settleUntil(() => robot.showsChoices);

      expect(robot.showsDialog, isFalse);
      expect(await onboardingDone(tester), isFalse);
      expect(robot.completions, 0);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('a SQLite file is restored as a new active database and the '
      'restart dialog exits', (tester) async {
    final source = p.join(tempDir.path, 'picked', 'phone backup.db');
    await tester.runAsync(() => writeSqliteHeaderFile(source));
    picker.nextPath = source;
    final platform = recordMethodCalls(SystemChannels.platform);
    final robot = OnboardingRobot(tester);
    await robot.pump();

    await robot.restoreFromBackup();
    await robot.settleUntil(() => robot.shows(l10n.restartRequiredTitle));

    final restored = await tester.runAsync(
      () => manager.databaseExists('phone_backup'),
    );
    expect(restored, isTrue);
    expect(prefs.getString(activeKey), 'phone_backup');
    // Written into the database that is open now — the one being left.
    expect(await onboardingDone(tester), isTrue);
    expect(robot.completions, 0);
    expect(platform.where((c) => c.method == 'SystemNavigator.pop'), isEmpty);

    await robot.tapDialogAction(l10n.exitApp);
    expect(
      platform.where((c) => c.method == 'SystemNavigator.pop'),
      hasLength(1),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an unreadable file shows the error and leaves the flag unset', (
    tester,
  ) async {
    final path = p.join(tempDir.path, 'picked', 'garbled.json');
    await tester.runAsync(() async {
      await Directory(p.dirname(path)).create(recursive: true);
      // Not SQLite, and not UTF-8 either: the read itself throws.
      await File(path).writeAsBytes([0xff, 0xfe, 0xc3, 0x28, 0xa0, 0xa1]);
    });
    picker.nextPath = path;
    final robot = OnboardingRobot(tester);
    await robot.pump();

    await robot.restoreFromBackup();
    await robot.settleUntil(() => robot.shows(l10n.importFailed));

    expect(robot.showsChoices, isTrue);
    expect(robot.showsDialog, isFalse);
    expect(await onboardingDone(tester), isFalse);
    expect(robot.completions, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a cancelled picker leaves the page as it was', (tester) async {
    picker.nextPath = null;
    final robot = OnboardingRobot(tester);
    await robot.pump();

    await robot.restoreFromBackup();

    expect(picker.picks, 1);
    expect(robot.showsChoices, isTrue);
    expect(robot.importing, isFalse);
    expect(await onboardingDone(tester), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('smoke', () {
    // Measured with Roboto: the test font's square glyphs are about twice as
    // wide, and would report overflows no device shows.
    setUpAll(loadGoldenFonts);

    Future<List<FlutterErrorDetails>> pumpAt(WidgetTester tester, Size size) {
      final robot = OnboardingRobot(tester);
      return layoutErrorsDuring(
        () =>
            robot.pump(size: size, locale: const Locale('de'), textScale: 2.0),
      );
    }

    // Today's state, pinned so S3 sees it change: the page is a fixed Column
    // between two Spacers, and at de 2.0 its content (about 848 dp measured
    // on 2026-10-31) runs 116 dp past the 732 dp the 360 × 780 surface
    // leaves inside its padding. When S3 makes the page scroll, this
    // expectation flips to `isEmpty`.
    testWidgets('de 2.0 on 360 × 780 overflows at the bottom (known, S3)', (
      tester,
    ) async {
      final errors = await pumpAt(tester, const Size(360, 780));

      expect(errors, hasLength(1));
      expect(
        errors.single.exceptionAsString(),
        allOf(contains('RenderFlex overflowed'), contains('on the bottom')),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('de 2.0 on 412 × 915 fits with no exception', (tester) async {
      final errors = await pumpAt(tester, const Size(412, 915));

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
