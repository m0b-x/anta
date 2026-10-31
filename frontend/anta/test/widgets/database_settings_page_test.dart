import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/database_settings_robot.dart';
import 'support/layout_errors.dart';
import 'support/settings_platform_fakes.dart';

/// The Databases page's destructive paths, pinned against today's behaviour
/// before S6 of the settings rework (`docs/settings-rework-roadmap.md`, D8)
/// wraps them: a checkpoint before the share, a loading helper around it, a
/// confirm before the switch. The record's rule is that these paths may be
/// wrapped and never reordered or rewritten, and this suite is how a diff
/// proves it — a slice that changes an assertion here says which and why.
///
/// Everything runs for real: the real `DatabaseManager` over a temporary
/// documents directory, and the real file-backed `AppDatabase` where a path
/// reaches it (optimize, delete all). Settings live in an in-memory database
/// so nothing holds a database file open unless the test opened it — on
/// Windows an open file can be neither renamed nor deleted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Settings run on an in-memory database beside the file-backed one the
  // optimize and delete-all paths open.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const activeKey = 'active_database';
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  final l10n = AppLocalizationsEn();

  late Directory tempDir;
  late SharedPreferences prefs;
  late DatabaseManager manager;
  late AppDatabase settingsDb;
  late FakeFilePicker picker;

  setUpAll(() async {
    // Measured with Roboto: the test font's square glyphs are about twice as
    // wide, and its overflows — no device shows them — would fail the path
    // tests, which see every overflow a row menu reports.
    await loadGoldenFonts();
    tempDir = await Directory.systemTemp.createTemp('anta_database_page');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await AppDatabase.deleteAllData();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    // Closes whatever the last test opened and empties the directory.
    await AppDatabase.deleteAllData();
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    manager = await DatabaseManager.getInstance();
    await manager.createDatabase('gym_notes');
    await manager.createDatabase('work');
    SettingsService.reset();
    settingsDb = await openTestDatabase();
    SettingsService.forTesting(settingsDb);
    picker = FakeFilePicker()..install();
  });

  tearDown(() async {
    SettingsService.reset();
    await settingsDb.close();
  });

  /// The database files on disk, by name.
  Future<Set<String>> filesOnDisk(WidgetTester tester) async {
    final names = await tester.runAsync(() async {
      final infos = await manager.listDatabases();
      return {for (final info in infos) info.name};
    });
    return names!;
  }

  Future<String> pathOf(String name) => manager.getDatabasePath(name);

  group('create', () {
    testWidgets('creating a database writes its file and lists it', (
      tester,
    ) async {
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.tapButton(l10n.createNewDatabase);
      await robot.enterName('travel');
      await robot.confirmDialog();
      await robot.settleUntil(() => robot.shows(l10n.databaseCreated));

      expect(await filesOnDisk(tester), {'gym_notes', 'work', 'travel'});
      expect(robot.listsDatabase('travel'), isTrue);
      expect(robot.showsLoading, isFalse);
      expect(prefs.getString(activeKey), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('cancelling the create dialog writes nothing', (tester) async {
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.tapButton(l10n.createNewDatabase);
      await robot.enterName('travel');
      await robot.cancelDialog();

      expect(robot.showsDialog, isFalse);
      expect(await filesOnDisk(tester), {'gym_notes', 'work'});

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('an invalid or taken name is refused before anything is '
        'written', (tester) async {
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.tapButton(l10n.createNewDatabase);
      await robot.enterName('two words');
      await robot.confirmDialog();
      expect(robot.shows(l10n.invalidDatabaseName), isTrue);

      await robot.tapButton(l10n.createNewDatabase);
      await robot.enterName('work');
      await robot.confirmDialog();
      expect(robot.shows(l10n.databaseExists), isTrue);

      expect(robot.showsLoading, isFalse);
      expect(await filesOnDisk(tester), {'gym_notes', 'work'});

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('import', () {
    testWidgets('a SQLite file is copied in verbatim under the suggested name '
        'and listed', (tester) async {
      final source = p.join(tempDir.path, 'picked', 'My Backup.db');
      final bytes = await tester.runAsync(() async {
        final file = await writeSqliteHeaderFile(source);
        return file.readAsBytes();
      });
      picker.nextPath = source;

      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();
      await robot.tapButton(l10n.importDatabase);
      await robot.settleUntil(() => robot.showsDialog);

      expect(robot.dialogFieldText, 'My_Backup');
      await robot.confirmDialog();
      await robot.settleUntil(() => robot.shows(l10n.databaseImported));

      expect(picker.picks, 1);
      expect(await filesOnDisk(tester), {'gym_notes', 'work', 'My_Backup'});
      final copied = await tester.runAsync(
        () async => File(await pathOf('My_Backup')).readAsBytes(),
      );
      expect(copied, bytes);
      expect(robot.listsDatabase('My_Backup'), isTrue);
      expect(robot.showsLoading, isFalse);
      expect(prefs.getString(activeKey), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a file that is not SQLite is refused before the name dialog', (
      tester,
    ) async {
      final source = p.join(tempDir.path, 'picked', 'notes.txt');
      await tester.runAsync(() async {
        await Directory(p.dirname(source)).create(recursive: true);
        await File(source).writeAsString('not a database at all');
      });
      picker.nextPath = source;

      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();
      await robot.tapButton(l10n.importDatabase);
      await robot.settleUntil(() => robot.shows(l10n.invalidDatabaseFile));

      expect(robot.showsDialog, isFalse);
      expect(await filesOnDisk(tester), {'gym_notes', 'work'});

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'a cancelled picker or a cancelled name dialog copies nothing',
      (tester) async {
        final source = p.join(tempDir.path, 'picked', 'cancelled.db');
        await tester.runAsync(() => writeSqliteHeaderFile(source));

        final robot = DatabaseSettingsRobot(tester);
        await robot.pump();

        picker.nextPath = null;
        await robot.tapButton(l10n.importDatabase);
        expect(picker.picks, 1);
        expect(robot.showsDialog, isFalse);

        picker.nextPath = source;
        await robot.tapButton(l10n.importDatabase);
        await robot.settleUntil(() => robot.showsDialog);
        await robot.cancelDialog();

        expect(robot.showsDialog, isFalse);
        expect(await filesOnDisk(tester), {'gym_notes', 'work'});

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('rename', () {
    testWidgets('renaming the active database moves its file and the active '
        'name follows', (tester) async {
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.openMenu('gym_notes');
      await robot.chooseFromMenu(l10n.rename);
      expect(robot.dialogFieldText, 'gym_notes');
      await robot.enterName('training');
      await robot.confirmDialog();
      await robot.settleUntil(() => robot.shows(l10n.databaseRenamed));

      expect(await filesOnDisk(tester), {'training', 'work'});
      expect(prefs.getString(activeKey), 'training');
      expect(robot.listsDatabase('training'), isTrue);
      expect(robot.listsDatabase('gym_notes'), isFalse);
      expect(robot.showsLoading, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('renaming another database leaves the active name alone', (
      tester,
    ) async {
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.openMenu('work');
      await robot.chooseFromMenu(l10n.rename);
      await robot.enterName('office');
      await robot.confirmDialog();
      await robot.settleUntil(() => robot.shows(l10n.databaseRenamed));

      expect(await filesOnDisk(tester), {'gym_notes', 'office'});
      expect(prefs.getString(activeKey), isNull);
      expect(manager.getActiveDatabaseName(), 'gym_notes');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('cancelling the rename dialog leaves files and the active name '
        'untouched', (tester) async {
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.openMenu('gym_notes');
      await robot.chooseFromMenu(l10n.rename);
      await robot.enterName('training');
      await robot.cancelDialog();

      expect(robot.showsDialog, isFalse);
      expect(await filesOnDisk(tester), {'gym_notes', 'work'});
      expect(prefs.getString(activeKey), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('delete', () {
    testWidgets('deleting another database removes its file and its row', (
      tester,
    ) async {
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.openMenu('work');
      await robot.chooseFromMenu(l10n.delete);
      expect(robot.shows(l10n.deleteDatabaseConfirm('work')), isTrue);
      await robot.confirmDialog();
      await robot.settleUntil(() => robot.shows(l10n.databaseDeleted));

      expect(await filesOnDisk(tester), {'gym_notes'});
      expect(robot.listsDatabase('work'), isFalse);
      expect(prefs.getString(activeKey), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('cancelling the delete confirm keeps the file', (tester) async {
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.openMenu('work');
      await robot.chooseFromMenu(l10n.delete);
      await robot.cancelDialog();

      expect(robot.showsDialog, isFalse);
      expect(await filesOnDisk(tester), {'gym_notes', 'work'});
      expect(robot.listsDatabase('work'), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the active database offers no switch and a disabled delete', (
      tester,
    ) async {
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.openMenu('gym_notes');
      expect(robot.shows(l10n.switchTo), isFalse);
      expect(robot.menuItem(l10n.delete).enabled, isFalse);
      await robot.chooseFromMenu(l10n.delete);
      await robot.dismissMenu();

      expect(robot.showsDialog, isFalse);
      expect(await filesOnDisk(tester), {'gym_notes', 'work'});

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('switch', () {
    testWidgets('switching writes the active name before the restart dialog, '
        'which has no way back — today\'s S7 behaviour, no confirm yet', (
      tester,
    ) async {
      final platform = recordMethodCalls(SystemChannels.platform);
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.openMenu('work');
      await robot.chooseFromMenu(l10n.switchTo);
      await robot.settleUntil(() => robot.shows(l10n.restartRequiredTitle));

      expect(prefs.getString(activeKey), 'work');
      expect(robot.showsLoading, isFalse);

      // Neither the barrier nor system back closes it, and the switch stays
      // written whatever the user does next.
      await robot.tapOutsideDialog();
      await tester.binding.handlePopRoute();
      await robot.settle();
      expect(robot.shows(l10n.restartRequiredTitle), isTrue);
      expect(prefs.getString(activeKey), 'work');
      expect(platform.where((c) => c.method == 'SystemNavigator.pop'), isEmpty);

      await robot.tapDialogAction(l10n.exitApp);
      expect(
        platform.where((c) => c.method == 'SystemNavigator.pop'),
        hasLength(1),
      );
      expect(await filesOnDisk(tester), {'gym_notes', 'work'});

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('share', () {
    testWidgets('sharing hands the active database file itself to the share '
        'sheet', (tester) async {
      final shares = recordMethodCalls(shareChannel);
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.tapButton(l10n.shareDatabase);
      await robot.settleUntil(() => shares.isNotEmpty);
      await robot.settle();

      expect(shares, hasLength(1));
      expect(shares.single.method, 'share');
      final arguments = shares.single.arguments as Map;
      expect(arguments['paths'], [await pathOf('gym_notes')]);
      expect(robot.showsLoading, isFalse);
      expect(robot.showsPage, isTrue);
      expect(robot.shows(l10n.shareError), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a share that throws pops twice and takes the page itself '
        'away (today, S4)', (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        shareChannel,
        (call) async => throw PlatformException(code: 'share_failed'),
      );
      addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump(overBase: true);

      await robot.tapButton(l10n.shareDatabase);
      await robot.settleUntil(() => !robot.showsPage);

      // The loading dialog was already closed before the share; the catch's
      // pop closes it again, and what it finds on top is the page.
      expect(robot.showsLoading, isFalse);
      expect(robot.showsPage, isFalse);
      expect(robot.shows(DatabaseSettingsRobot.baseText), isTrue);
      expect(robot.shows(l10n.shareError), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('optimize', () {
    /// Bytes from the size the info card shows ("12.34 MB", "5.0 KB").
    int bytesOf(String shown) {
      final [number, unit] = shown.split(' ');
      final scale = switch (unit) {
        'MB' => 1024 * 1024,
        'KB' => 1024,
        _ => 1,
      };
      return (double.parse(number) * scale).round();
    }

    testWidgets('optimizing vacuums the open database, keeps its rows and '
        'reloads the size', (tester) async {
      await tester.runAsync(() async {
        final db = await AppDatabase.getInstance();
        await db.folderDao.createFolder(name: 'Kept');
        // Free pages for the vacuum to drop: a page-sized row per page, a
        // quarter of them kept. The kept part is over the WAL's 1,000-page
        // auto-checkpoint, so the vacuum's own commit checkpoints and the
        // main file truncates to the compacted size; the drop is big enough
        // that the file plus the WAL the vacuum leaves (about half of what
        // it was, measured) is still under it.
        await db.customStatement('CREATE TABLE ballast (kept INTEGER, v TEXT)');
        await db.customStatement(
          'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
          'WHERE x < 6000) INSERT INTO ballast SELECT x % 4 = 0, '
          'hex(randomblob(1900)) FROM n',
        );
        await db.customStatement('DELETE FROM ballast WHERE kept = 0');
        // Folded into the main file, so the size the page reads first is the
        // file's, free pages included.
        await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
      });
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();
      final sizeBefore = bytesOf(robot.statValue(l10n.size));

      await robot.tapButton(l10n.optimizeDatabase);
      await robot.settleUntil(() => robot.shows(l10n.optimizationComplete));

      expect(robot.showsLoading, isFalse);
      // The suffix is computed from the size read back after the vacuum, and
      // the card shows that size: both prove the vacuum ran and the info
      // reloaded.
      expect(robot.shows(l10n.saved), isTrue);
      final sizeAfter = bytesOf(robot.statValue(l10n.size));
      expect(sizeAfter, lessThan(sizeBefore));
      final folders = await tester.runAsync(
        () async => (await AppDatabase.getInstance()).folderDao.getAllFolders(
          includeDeleted: false,
        ),
      );
      expect(folders!.map((f) => f.name), contains('Kept'));

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('delete all', () {
    Future<void> seed(WidgetTester tester) async {
      await tester.runAsync(() async {
        final db = await AppDatabase.getInstance();
        final folder = await db.folderDao.createFolder(name: 'Training');
        await db.noteDao.createNote(
          folderId: folder.id,
          title: 'Leg day',
          content: 'squats',
        );
      });
    }

    Future<(int, int)> rowCounts(WidgetTester tester) async {
      final counts = await tester.runAsync(() async {
        final db = await AppDatabase.getInstance();
        final folders = await db.folderDao.getAllFolders(includeDeleted: true);
        final notes = await db.noteDao.getAllNotes(includeDeleted: true);
        return (folders.length, notes.length);
      });
      return counts!;
    }

    testWidgets('cancelling the delete-all confirm keeps every row', (
      tester,
    ) async {
      await seed(tester);
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.tapButton(l10n.deleteAllData);
      expect(robot.shows(l10n.deleteConfirmation), isTrue);
      await robot.cancelDialog();

      expect(robot.showsDialog, isFalse);
      expect(await rowCounts(tester), (1, 1));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('delete all wipes the database directory and asks for a '
        'restart that exits', (tester) async {
      await seed(tester);
      final platform = recordMethodCalls(SystemChannels.platform);
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.tapButton(l10n.deleteAllData);
      await robot.confirmDialog();
      await robot.settleUntil(() => robot.shows(l10n.dataDeleted));

      expect(robot.showsLoading, isFalse);
      final directoryLeft = await tester.runAsync(
        () async => Directory(await manager.getDatabaseDirectory()).exists(),
      );
      expect(directoryLeft, isFalse);

      await robot.tapOutsideDialog();
      expect(robot.shows(l10n.dataDeleted), isTrue);
      expect(platform.where((c) => c.method == 'SystemNavigator.pop'), isEmpty);
      await robot.tapDialogAction(l10n.exitApp);
      expect(
        platform.where((c) => c.method == 'SystemNavigator.pop'),
        hasLength(1),
      );

      // What the next launch opens is a fresh, empty database.
      expect(await rowCounts(tester), (0, 0));

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('smoke at de 2.0 on 360 × 780', () {
    final de = AppLocalizationsDe();

    Future<void> pumpLarge(DatabaseSettingsRobot robot) => robot.pump(
      size: const Size(360, 780),
      locale: const Locale('de'),
      textScale: 2.0,
    );

    testWidgets('the page opens and scrolls to its end with no overflow and '
        'no exception', (tester) async {
      final robot = DatabaseSettingsRobot(tester);
      final errors = await layoutErrorsDuring(() async {
        await pumpLarge(robot);
        // The list builds lazily; scrolling to its end lays out every card.
        await robot.scrollTo(de.deleteAllData);
      });

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);
      expect(find.text(de.deleteAllData).hitTestable(), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // Today's state, pinned so S6 sees it change: the row menu's entries are
    // bare Rows in the popup's 256 dp of content width, and "Zu dieser
    // Datenbank wechseln" at 2.0 does not fit. When S6 wraps the label, this
    // expectation flips to `isEmpty`.
    testWidgets('the row menu overflows on its switch entry (known, S6)', (
      tester,
    ) async {
      final robot = DatabaseSettingsRobot(tester)..captureMenuOverflows = true;
      await pumpLarge(robot);

      await robot.openMenu('work');
      expect(robot.shows(de.switchTo), isTrue);
      await robot.dismissMenu();

      // The overflow is the switch entry's own Row, not any other.
      expect(robot.menuOverflows, contains(contains(de.switchTo)));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
