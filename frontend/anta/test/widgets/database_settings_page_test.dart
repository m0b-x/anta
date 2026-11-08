import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' show OpenMode, sqlite3;

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/l10n/app_localizations_ro.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/form_rows.dart' show FormCaptionSlot;

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/database_settings_robot.dart';
import 'support/layout_errors.dart';
import 'support/settings_page_whole.dart';
import 'support/settings_platform_fakes.dart';

/// The Databases page's destructive paths, pinned against today's behaviour
/// before S6 of the settings rework (`docs/settings-rework-roadmap.md`, D8)
/// wraps them: a checkpoint before the share, a loading helper around it, a
/// confirm before the switch. The record's rule is that these paths may be
/// wrapped and never reordered or rewritten, and this suite is how a diff
/// proves it — a slice that changes an assertion here says which and why.
/// S6 changed three, each marked where it stands: the switch now asks first,
/// a failed share keeps the page, and the row menu no longer overflows.
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
    // The share goes through the app's one share path, `shareExport`; the
    // storage it is built over is never touched by it.
    final notes = NoteRepository(database: settingsDb);
    GetIt.I.registerSingleton<ImportExportService>(
      ImportExportService(
        noteStorage: NoteStorageService(repository: notes),
        folderStorage: FolderStorageService(
          repository: FolderRepository(database: settingsDb),
        ),
        noteRepository: notes,
      ),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
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

    testWidgets('a create the manager fails shows the sentence alone and logs '
        'the stack', (tester) async {
      // A folder where the file goes: the name reads free, the create throws.
      final blocked = await pathOf('travel');
      await tester.runAsync(() => Directory(blocked).create(recursive: true));
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.tapButton(l10n.createNewDatabase);
      await robot.enterName('travel');
      // Restored inside the body: the binding checks the foundation
      // variables before any tear-down runs.
      final logs = <String>[];
      final print = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      try {
        await robot.confirmDialog();
        await robot.settleUntil(() => robot.shows(l10n.databaseCreateFailed));
      } finally {
        debugPrint = print;
      }

      expect(find.text(l10n.databaseCreateFailed), findsOneWidget);
      expect(robot.showsLoading, isFalse);
      final logged = logs.singleWhere(
        (line) => line.startsWith('[DatabaseSettings] create failed: '),
      );
      expect(logged, contains('#0'), reason: 'the stack, not just the error');
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
    /// The paths the import's check was handed. SQLite cannot run under
    /// `FakeAsync`, so the page meets a check that accepts every file unless
    /// a test says otherwise; the real one is
    /// `test/services/database_manager_import_test.dart`'s.
    late List<String> verified;

    setUp(() {
      verified = [];
      manager.verifyImport = (path) async => verified.add(path);
    });

    tearDown(() {
      manager.verifyImport = DatabaseManager.verifyImportFile;
      DatabaseManager.debugImportChunkWritten = null;
    });

    /// Every file in the databases directory, sidecars and temporary copies
    /// included.
    Future<Set<String>> directoryOnDisk(WidgetTester tester) async {
      final names = await tester.runAsync(() async {
        final dir = Directory(await manager.getDatabaseDirectory());
        return {await for (final entity in dir.list()) p.basename(entity.path)};
      });
      return names!;
    }

    /// A file of [megabytes] MB that passes the header sniff, so the copy
    /// takes that many chunks.
    Future<void> writeLargeSqliteFile(
      WidgetTester tester,
      String path,
      int megabytes,
    ) async {
      await tester.runAsync(() async {
        final bytes = Uint8List(megabytes << 20)
          ..setRange(0, 16, 'SQLite format 3\u0000'.codeUnits);
        await Directory(p.dirname(path)).create(recursive: true);
        await File(path).writeAsBytes(bytes);
      });
    }

    // Was "a SQLite file is copied in verbatim under the suggested name and
    // listed": the file now reaches its name only through the check (S19).
    testWidgets('a SQLite file the check accepts is copied in byte for byte '
        'under the suggested name and listed', (tester) async {
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
      // Checked under a temporary name, never as the database itself.
      final target = await tester.runAsync(() => pathOf('My_Backup'));
      expect(verified, [startsWith('$target.import-')]);
      expect(await directoryOnDisk(tester), {
        'gym_notes.db',
        'work.db',
        'My_Backup.db',
      });
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

    testWidgets('the copy fills a determinate bar under a live Cancel; the '
        'check runs under an indeterminate one whose Cancel is disabled', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final source = p.join(tempDir.path, 'picked', 'big.db');
      await writeLargeSqliteFile(tester, source, 4);
      picker.nextPath = source;
      final firstChunk = Completer<void>();
      final copyGoesOn = Completer<void>();
      DatabaseManager.debugImportChunkWritten = () async {
        if (firstChunk.isCompleted) return;
        firstChunk.complete();
        await copyGoesOn.future;
      };
      final checking = Completer<void>();
      final checkDone = Completer<void>();
      manager.verifyImport = (path) async {
        checking.complete();
        await checkDone.future;
      };

      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();
      await robot.tapButton(l10n.importDatabase);
      await robot.settleUntil(() => robot.showsDialog);
      await robot.confirmDialog();
      await robot.settleUntil(() => firstChunk.isCompleted);
      await robot.settle(rounds: 2);

      expect(robot.importBarValue, closeTo(0.25, 0.001));
      expect(robot.importCancelEnabled, isTrue);
      expect(robot.showsImportStep(l10n.importingDatabase), isTrue);
      expect(robot.showsImportStep(l10n.checkingDatabaseFile), isFalse);

      copyGoesOn.complete();
      await robot.settleUntil(() => checking.isCompleted);
      await robot.settle(rounds: 2);

      expect(robot.importBarValue, isNull);
      expect(robot.importCancelEnabled, isFalse);
      expect(robot.showsImportStep(l10n.checkingDatabaseFile), isTrue);
      expect(robot.showsImportStep(l10n.importingDatabase), isFalse);
      expect(await filesOnDisk(tester), {'gym_notes', 'work'});

      checkDone.complete();
      await robot.settleUntil(() => robot.shows(l10n.databaseImported));

      expect(robot.showsDialog, isFalse);
      expect(await filesOnDisk(tester), {'gym_notes', 'work', 'big'});
      semantics.dispose();

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Cancel during the copy deletes the partial file, says '
        'nothing, and leaves the active database as it was', (tester) async {
      final source = p.join(tempDir.path, 'picked', 'big.db');
      await writeLargeSqliteFile(tester, source, 4);
      picker.nextPath = source;
      await prefs.setString(activeKey, 'work');
      final firstChunk = Completer<void>();
      final copyGoesOn = Completer<void>();
      DatabaseManager.debugImportChunkWritten = () async {
        if (firstChunk.isCompleted) return;
        firstChunk.complete();
        await copyGoesOn.future;
      };

      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();
      await robot.tapButton(l10n.importDatabase);
      await robot.settleUntil(() => robot.showsDialog);
      await robot.confirmDialog();
      await robot.settleUntil(() => firstChunk.isCompleted);

      expect(
        (await directoryOnDisk(tester)).where((n) => n.contains('.import-')),
        hasLength(1),
        reason: 'the partial copy is on disk while the copy is held',
      );
      await robot.cancelDialog();
      expect(robot.importCancelEnabled, isFalse, reason: 'one cancel only');
      copyGoesOn.complete();
      await robot.settleUntil(() => !robot.showsDialog);
      await robot.settle();

      expect(verified, isEmpty);
      expect(await directoryOnDisk(tester), {'gym_notes.db', 'work.db'});
      expect(prefs.getString(activeKey), 'work');
      expect(robot.shows(l10n.importFailed), isFalse);
      expect(robot.shows(l10n.databaseImported), isFalse);
      expect(robot.showsPage, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final (refusal, message) in [
      (const DatabaseImportCorrupt('test'), l10n.databaseImportCorrupt),
      (const DatabaseImportNotAnta(), l10n.databaseImportNotAnta),
      (const DatabaseImportTooNew(99), l10n.databaseImportTooNew),
      (const FileSystemException('disk full'), l10n.importFailed),
    ]) {
      testWidgets('a file the check refuses with ${refusal.runtimeType} says '
          'so and leaves nothing behind', (tester) async {
        final source = p.join(tempDir.path, 'picked', 'refused.db');
        await tester.runAsync(() => writeSqliteHeaderFile(source));
        picker.nextPath = source;
        manager.verifyImport = (_) async => throw refusal;

        final robot = DatabaseSettingsRobot(tester);
        await robot.pump();
        await robot.tapButton(l10n.importDatabase);
        await robot.settleUntil(() => robot.showsDialog);
        await robot.confirmDialog();
        await robot.settleUntil(() => robot.shows(message));
        await robot.settle();

        expect(find.text(message), findsOneWidget);
        expect(robot.showsDialog, isFalse);
        expect(await directoryOnDisk(tester), {'gym_notes.db', 'work.db'});
        expect(robot.listsDatabase('refused'), isFalse);
        expect(prefs.getString(activeKey), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
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
    // S6 changed this pin: S0 had the menu entry write the active name
    // straight away (S7). The confirm now comes first and nothing is written
    // before its yes; from the yes on, the path is the one S0 pinned — the
    // write, then the restart dialog with no way back.
    testWidgets('switching asks first; yes writes the active name before the '
        'restart dialog, which has no way back', (tester) async {
      final platform = recordMethodCalls(SystemChannels.platform);
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.openMenu('work');
      await robot.chooseFromMenu(l10n.switchTo);
      expect(robot.shows(l10n.databaseSwitchConfirm('work')), isTrue);
      expect(prefs.getString(activeKey), isNull);
      await robot.confirmDialog();
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

    testWidgets('cancelling the switch confirm writes nothing and asks for no '
        'restart', (tester) async {
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.openMenu('work');
      await robot.chooseFromMenu(l10n.switchTo);
      await robot.cancelDialog();

      expect(robot.showsDialog, isFalse);
      expect(robot.shows(l10n.restartRequiredTitle), isFalse);
      expect(prefs.getString(activeKey), isNull);
      expect(manager.getActiveDatabaseName(), 'gym_notes');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('share', () {
    /// The share snapshots' folders in the temp directory, by name.
    Set<String> snapshotFolders() => {
      for (final entity in tempDir.listSync())
        if (entity is Directory &&
            p
                .basename(entity.path)
                .startsWith(DatabaseManager.shareSnapshotPrefix))
          p.basename(entity.path),
    };

    tearDown(() {
      for (final name in snapshotFolders()) {
        Directory(p.join(tempDir.path, name)).deleteSync(recursive: true);
      }
    });

    /// The one path the share sheet was handed.
    String sharedPath(List<MethodCall> shares) =>
        ((shares.single.arguments as Map)['paths'] as List).single as String;

    // S18 flipped this pin (D11): the sheet was handed the live file itself;
    // it now gets a snapshot under the same name, so a restore suggests the
    // same database name, in a folder of its own.
    testWidgets('sharing hands the share sheet a snapshot of the active '
        'database under its own name', (tester) async {
      final shares = recordMethodCalls(shareChannel);
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.tapButton(l10n.shareDatabase);
      await robot.settleUntil(() => shares.isNotEmpty);
      await robot.settle();

      expect(shares, hasLength(1));
      expect(shares.single.method, 'share');
      final shared = sharedPath(shares);
      expect(p.basename(shared), 'gym_notes.db');
      expect(p.dirname(p.dirname(shared)), tempDir.path);
      expect(
        p.basename(p.dirname(shared)),
        startsWith(DatabaseManager.shareSnapshotPrefix),
      );
      expect(shared, isNot(await pathOf('gym_notes')));
      // No answer is `unavailable`: the copy waits for the next share.
      expect(File(shared).existsSync(), isTrue);
      expect(robot.showsLoading, isFalse);
      expect(robot.showsPage, isTrue);
      expect(robot.shows(l10n.shareError), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('on Android a share the sheet answered takes the snapshot '
        'folder with it', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final shares = recordMethodCalls(shareChannel, answer: 'org.example');
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.tapButton(l10n.shareDatabase);
      await robot.settleUntil(() => shares.isNotEmpty);
      await robot.settleUntil(() => snapshotFolders().isEmpty);

      expect(File(sharedPath(shares)).existsSync(), isFalse);
      expect(robot.shows(l10n.shareError), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });

    // S18 flipped this pin (D11): the open database was checkpointed so the
    // live file alone held every write; the snapshot now carries the write
    // still in the WAL, with nothing folded.
    testWidgets('the snapshot carries the write still in the WAL and the live '
        'file stays in place', (tester) async {
      final path = await pathOf('gym_notes');
      await tester.runAsync(() async {
        final db = await AppDatabase.getInstance();
        await db.folderDao.createFolder(name: 'Latest');
      });
      final latestAtShare = <int>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        final shared = ((call.arguments as Map)['paths'] as List).single;
        final copy = sqlite3.open(shared as String, mode: OpenMode.readOnly);
        try {
          latestAtShare.add(
            copy
                    .select(
                      "SELECT count(*) FROM folders WHERE name = 'Latest'",
                    )
                    .single
                    .values
                    .first
                as int,
          );
        } finally {
          copy.close();
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));
      expect(File('$path-wal').lengthSync(), greaterThan(0));

      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();
      await robot.tapButton(l10n.shareDatabase);
      await robot.settleUntil(() => latestAtShare.isNotEmpty);
      await robot.settle();

      expect(latestAtShare, [1]);
      expect(File('$path-wal').lengthSync(), greaterThan(0));
      expect(File(path).existsSync(), isTrue);
      expect(robot.showsPage, isTrue);
      expect(robot.shows(l10n.shareError), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // S6 flipped this pin: S0 had the catch pop a second time and take the
    // page itself away (S4). The loading helper now pops its own dialog
    // once, and the page stays with the error on it.
    testWidgets('a share that throws shows the error and keeps the page', (
      tester,
    ) async {
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
      // The error can show while the loading dialog's exit is still running.
      await robot.settleUntil(
        () => robot.shows(l10n.shareError) && !robot.showsLoading,
      );

      // The sentence alone: the exception is logged, never appended.
      expect(find.text(l10n.shareError), findsOneWidget);
      expect(robot.showsLoading, isFalse);
      expect(robot.showsPage, isTrue);
      expect(robot.shows(DatabaseSettingsRobot.baseText), isFalse);
      expect(File(await pathOf('gym_notes')).existsSync(), isTrue);
      // No sheet ever had the snapshot, so it went at once.
      expect(snapshotFolders(), isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // The live file is never handed over nor cleaned up as a temporary
    // export, whatever the share does. The file here is closed: on Windows an
    // open one cannot be deleted at all, which would hide a share that tried.
    for (final (outcome, handler)
        in <(String, Future<Object?>? Function(MethodCall)?)>[
          ('succeeds', (call) async => null),
          (
            'throws',
            (call) async => throw PlatformException(code: 'share_failed'),
          ),
          ('is missing', null),
        ]) {
      testWidgets('a share whose channel $outcome leaves the database file '
          'byte for byte', (tester) async {
        final path = await pathOf('gym_notes');
        // A real database, closed: S18's snapshot reads it, where the
        // header-only file the earlier pin used fails to open (below).
        final bytes = await tester.runAsync(() async {
          final writer = sqlite3.open(path);
          writer.execute('CREATE TABLE items (v TEXT)');
          writer.execute("INSERT INTO items VALUES ('kept')");
          writer.close();
          return File(path).readAsBytes();
        });
        var shared = false;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          shareChannel,
          handler == null
              ? null
              : (call) {
                  shared = true;
                  return handler(call);
                },
        );
        addTearDown(
          () => messenger.setMockMethodCallHandler(shareChannel, null),
        );
        final robot = DatabaseSettingsRobot(tester);
        await robot.pump();

        await robot.tapButton(l10n.shareDatabase);
        await robot.settleUntil(
          () => (shared && !robot.showsLoading) || robot.shows(l10n.shareError),
        );
        await robot.settle();

        expect(robot.shows(l10n.shareError), outcome != 'succeeds');
        expect(robot.showsPage, isTrue);
        expect(File(path).readAsBytesSync(), bytes);

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    // S18 flipped this pin (D11): a reader holding the WAL blocked the
    // checkpoint and refused the share; the snapshot needs no checkpoint.
    testWidgets('a reader holding the WAL no longer refuses the share', (
      tester,
    ) async {
      final shares = recordMethodCalls(shareChannel);
      final path = await pathOf('gym_notes');
      await tester.runAsync(() async {
        final db = await AppDatabase.getInstance();
        await db.folderDao.createFolder(name: 'In the WAL');
      });
      // A foreign reader holding a snapshot keeps the WAL from truncating.
      final reader = sqlite3.open(path, mode: OpenMode.readWrite);
      addTearDown(reader.close);
      reader.execute('BEGIN');
      reader.select('SELECT count(*) FROM folders');

      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();
      await robot.tapButton(l10n.shareDatabase);
      await robot.settleUntil(() => shares.isNotEmpty);
      await robot.settle();
      reader.execute('COMMIT');

      expect(shares, hasLength(1));
      expect(robot.shows(l10n.shareError), isFalse);
      expect(robot.showsLoading, isFalse);
      expect(robot.showsPage, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // `SQLITE_FULL` cannot be staged here; a database SQLite refuses to read
    // fails the same copy on the same path.
    testWidgets('a snapshot that fails shows the error, never reaches the '
        'share sheet and leaves no folder behind', (tester) async {
      final shares = recordMethodCalls(shareChannel);
      final path = await pathOf('gym_notes');
      await tester.runAsync(() => writeSqliteHeaderFile(path));

      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();
      await robot.tapButton(l10n.shareDatabase);
      // The error can show while the loading dialog's exit is still running.
      await robot.settleUntil(
        () => robot.shows(l10n.shareError) && !robot.showsLoading,
      );

      expect(shares, isEmpty);
      expect(snapshotFolders(), isEmpty);
      expect(robot.showsLoading, isFalse);
      expect(robot.showsPage, isTrue);

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

    /// The reclaimable caption as shown: the slot's last text, after the
    /// invisible twins that size it.
    String shownCaption(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(FormCaptionSlot),
            matching: find.byType(Text),
          ),
        )
        .last
        .data!;

    double buttonTop(WidgetTester tester, String label) => tester
        .getTopLeft(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        )
        .dy;

    /// What the Optimize snackbar says before the size it freed.
    final freedPrefix = l10n.optimizeFreed('');

    /// How far below Optimize the Share button sits.
    double shareGap(WidgetTester tester) =>
        buttonTop(tester, l10n.shareDatabase) -
        buttonTop(tester, l10n.optimizeDatabase);

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
      await robot.settleUntil(() => robot.shows(freedPrefix));

      expect(robot.showsLoading, isFalse);
      // The card shows the size read back after the vacuum: it proves the
      // vacuum ran and the info reloaded.
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

    testWidgets('the caption beside Optimize reads the free pages, and none '
        'once optimized (D13)', (tester) async {
      final reclaimable = await tester.runAsync(() async {
        final db = await AppDatabase.getInstance();
        await db.customStatement('CREATE TABLE ballast (v TEXT)');
        await db.customStatement(
          'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
          'WHERE x < 1000) INSERT INTO ballast SELECT hex(randomblob(1900)) '
          'FROM n',
        );
        await db.customStatement('DELETE FROM ballast');
        return db.reclaimableBytes();
      });
      expect(reclaimable, greaterThan(1024 * 1024));
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();
      await robot.scrollTo(l10n.optimizeDatabase);

      final prefix = l10n.databaseReclaimable('');
      // The last match is the shown caption; the slot's sizing twins come
      // before it.
      final caption = tester
          .widgetList<Text>(find.textContaining(prefix))
          .last
          .data!
          .substring(prefix.length);
      // Shown in MB to two decimals.
      expect(
        (bytesOf(caption) - reclaimable!).abs(),
        lessThanOrEqualTo(0.005 * 1024 * 1024),
      );
      // A file over a megabyte can leave a reading in kilobytes, which can
      // be wider than the file's own ("999.5 KB" beside "1.20 MB"): the slot
      // is sized at the widest one.
      expect(
        find.text(
          l10n.databaseReclaimable(l10n.databaseSizeKilobytes('1024.0')),
        ),
        findsOneWidget,
      );

      await robot.tapButton(l10n.optimizeDatabase);
      await robot.settleUntil(() => robot.shows(freedPrefix));

      expect(
        find.text(l10n.databaseReclaimable(l10n.databaseSizeBytes('0'))),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the neutral caption while the active database is not open', (
      tester,
    ) async {
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();
      await robot.scrollTo(l10n.optimizeDatabase);

      expect(shownCaption(tester), l10n.databaseReclaimableUnknown);
    });

    // The caption is read in the page's first load and always laid out, so
    // the Share button under it never moves (D13 review F9).
    testWidgets('the caption is in the first frame, reads the neutral sentence '
        'when the read fails, and the Share button keeps its place', (
      tester,
    ) async {
      const tall = Size(412, 3000);
      final db = (await tester.runAsync(() async {
        final db = await AppDatabase.getInstance();
        await db.customStatement('CREATE TABLE ballast (v TEXT)');
        await db.customStatement(
          'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
          'WHERE x < 200) INSERT INTO ballast SELECT hex(randomblob(1900)) '
          'FROM n',
        );
        await db.customStatement('DELETE FROM ballast');
        // Folded, so closing the database below leaves the size the same.
        await db.checkpoint();
        return db;
      }))!;
      final robot = DatabaseSettingsRobot(tester);
      // Returns on the first frame that shows the page's content.
      await robot.pump(size: tall);

      final known = shownCaption(tester);
      expect(known, startsWith(l10n.databaseReclaimable('')));
      final knownGap = shareGap(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      // A closed connection under the open handle: the read throws.
      await tester.runAsync(db.close);
      await robot.pump(size: tall);

      expect(shownCaption(tester), l10n.databaseReclaimableUnknown);
      expect(shareGap(tester), knownGap);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // Under WAL the vacuum's pages sit in `-wal` until a checkpoint; a size
    // delta read before it came out negative and said "already optimized"
    // right after space was given back (D13 review F3).
    testWidgets('optimizing a file with free pages says what it freed — the '
        'free pages read before the run — never that it was compact', (
      tester,
    ) async {
      final reclaimable = await tester.runAsync(() async {
        final db = await AppDatabase.getInstance();
        // Under the WAL's 1,000-page auto-checkpoint, so only the run's own
        // checkpoint shrinks the main file.
        await db.customStatement('CREATE TABLE ballast (v TEXT)');
        await db.customStatement(
          'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
          'WHERE x < 500) INSERT INTO ballast SELECT hex(randomblob(1900)) '
          'FROM n',
        );
        await db.customStatement('DELETE FROM ballast');
        await db.checkpoint();
        return db.reclaimableBytes();
      });
      expect(reclaimable, greaterThan(1024 * 1024));
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.tapButton(l10n.optimizeDatabase);
      await robot.settleUntil(() => robot.shows(freedPrefix));

      final freed = tester
          .widget<Text>(find.textContaining(freedPrefix))
          .data!
          .substring(freedPrefix.length);
      // Shown in MB to two decimals.
      expect(
        (bytesOf(freed) - reclaimable!).abs(),
        lessThanOrEqualTo(0.005 * 1024 * 1024),
      );
      expect(robot.shows(l10n.optimizeAlreadyCompact), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // The size before counts the `-wal` sidecar and the run's checkpoint
    // folds it back, so a size delta called those pages freed.
    testWidgets('a file with no free pages is already compact, however much '
        'sits in its WAL', (tester) async {
      await tester.runAsync(() async {
        final db = await AppDatabase.getInstance();
        // Under the WAL's 1,000-page auto-checkpoint: it stays in `-wal`.
        await db.customStatement('CREATE TABLE ballast (v TEXT)');
        await db.customStatement(
          'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
          'WHERE x < 500) INSERT INTO ballast SELECT hex(randomblob(1900)) '
          'FROM n',
        );
        expect(await db.reclaimableBytes(), 0);
        final wal = File('${await pathOf('gym_notes')}-wal');
        expect(wal.lengthSync(), greaterThan(1024 * 1024));
      });
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      await robot.tapButton(l10n.optimizeDatabase);
      await robot.settleUntil(() => robot.shows(l10n.optimizeAlreadyCompact));

      expect(robot.shows(freedPrefix), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Optimize refreshes the page in place: the scroll and the '
        'Share button stay where they were', (tester) async {
      await tester.runAsync(() async {
        final db = await AppDatabase.getInstance();
        await db.customStatement('CREATE TABLE ballast (v TEXT)');
        await db.customStatement(
          'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
          'WHERE x < 500) INSERT INTO ballast SELECT hex(randomblob(1900)) '
          'FROM n',
        );
        await db.customStatement('DELETE FROM ballast');
        await db.checkpoint();
      });
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump(size: const Size(360, 780));
      Finder button(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      await robot.scrollTo(l10n.optimizeDatabase);
      await tester.ensureVisible(button(l10n.optimizeDatabase));
      await tester.pump();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final offset = position.pixels;
      expect(offset, greaterThan(0), reason: 'the page was scrolled');
      final shareBefore = tester.getRect(button(l10n.shareDatabase));

      // Tapped where it stands: the robot's tap would scroll to it first.
      await tester.tap(button(l10n.optimizeDatabase));
      await robot.settleUntil(() => robot.shows(freedPrefix));

      expect(
        tester.state<ScrollableState>(find.byType(Scrollable).first).position,
        same(position),
        reason: 'the list was kept, not rebuilt behind a spinner',
      );
      expect(position.pixels, offset);
      expect(tester.getRect(button(l10n.shareDatabase)), shareBefore);

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
      // No database file is left. The directory itself may be back: the next
      // database or settings read recreates it, and an open handle would
      // have made the delete throw instead.
      final databasesLeft = await tester.runAsync(() async {
        final directory = Directory(await manager.getDatabaseDirectory());
        if (!await directory.exists()) return const <String>[];
        return [
          await for (final entity in directory.list())
            if (entity.path.endsWith('.db')) entity.path,
        ];
      });
      expect(databasesLeft, isEmpty);

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

    // S6 flipped this pin: S0 pinned "Zu dieser Datenbank wechseln"
    // overflowing the popup's 256 dp at 2.0 as a bare Row's text. The label
    // is Flexible now and wraps inside the entry; the switch confirm it opens
    // is read at the same size.
    testWidgets('the row menu and the switch confirm fit with no overflow', (
      tester,
    ) async {
      final robot = DatabaseSettingsRobot(tester);
      await pumpLarge(robot);

      final errors = await layoutErrorsDuring(() async {
        await robot.openMenu('work');
        expect(robot.shows(de.switchTo), isTrue);
        await robot.chooseFromMenu(de.switchTo);
        expect(robot.shows(de.databaseSwitchConfirm('work')), isTrue);
        await robot.cancelDialog();
      });

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);
      expect(prefs.getString(activeKey), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the import dialog fits both its steps with no overflow, and '
        'the step\'s switch keeps its height', (tester) async {
      final source = p.join(tempDir.path, 'picked', 'big.db');
      await tester.runAsync(() async {
        final bytes = Uint8List(2 << 20)
          ..setRange(0, 16, 'SQLite format 3\u0000'.codeUnits);
        await Directory(p.dirname(source)).create(recursive: true);
        await File(source).writeAsBytes(bytes);
      });
      picker.nextPath = source;
      final firstChunk = Completer<void>();
      final copyGoesOn = Completer<void>();
      DatabaseManager.debugImportChunkWritten = () async {
        if (firstChunk.isCompleted) return;
        firstChunk.complete();
        await copyGoesOn.future;
      };
      final checking = Completer<void>();
      final checkDone = Completer<void>();
      manager.verifyImport = (_) async {
        checking.complete();
        await checkDone.future;
      };
      addTearDown(() {
        manager.verifyImport = DatabaseManager.verifyImportFile;
        DatabaseManager.debugImportChunkWritten = null;
      });
      final robot = DatabaseSettingsRobot(tester);
      await pumpLarge(robot);

      // The dialog's own surface: the AlertDialog widget fills the screen.
      final surface = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first;
      late Size copying;
      late Size verifying;
      final errors = await layoutErrorsDuring(() async {
        await robot.tapButton(de.importDatabase);
        await robot.settleUntil(() => robot.showsDialog);
        await robot.confirmDialog();
        await robot.settleUntil(() => firstChunk.isCompleted);
        await robot.settle(rounds: 2);
        copying = tester.getSize(surface);
        copyGoesOn.complete();
        await robot.settleUntil(() => checking.isCompleted);
        await robot.settle(rounds: 2);
        verifying = tester.getSize(surface);
        checkDone.complete();
        await robot.settleUntil(() => robot.shows(de.databaseImported));
      });

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);
      expect(
        copying.height,
        lessThan(780),
        reason: 'the surface, not the route',
      );
      expect(verifying, copying);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // At ro 2.0 the danger header overflowed by 14 dp, "Ultima Modificare"
    // got 28 dp beside its value, and the two path buttons broke their
    // words in half a card. Database names are the user's text and may
    // break anywhere, so they are left out.
    for (final (locale, l10n) in <(Locale, AppLocalizations)>[
      (const Locale('de'), de),
      (const Locale('ro'), AppLocalizationsRo()),
    ]) {
      testWidgets('${locale.languageCode} at 2.0: the stat labels, the danger '
          'header and the path buttons hold their words, with no overflow', (
        tester,
      ) async {
        final robot = DatabaseSettingsRobot(tester);
        final errors = await layoutErrorsDuring(() async {
          await robot.pump(
            size: const Size(360, 780),
            locale: locale,
            textScale: 2.0,
          );
          for (final text in [
            l10n.size,
            l10n.lastModified,
            l10n.copyPath,
            l10n.openInFinder,
            l10n.dangerZone,
          ]) {
            await robot.scrollTo(text);
            final paragraph = tester.renderObject<RenderParagraph>(
              find.text(text),
            );
            expect(
              paragraph.size.width,
              greaterThanOrEqualTo(
                paragraph.getMinIntrinsicWidth(double.infinity) - 0.01,
              ),
              reason: '"$text" breaks inside a word',
            );
            expectBreaksBetweenWords(paragraph);
          }
        });

        expect(errors.map((e) => e.exceptionAsString()), isEmpty);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

  group('localized values', () {
    final de = AppLocalizationsDe();

    testWidgets('sizes and dates follow the locale, never hand-built', (
      tester,
    ) async {
      // 1,536 bytes: one and a half kilobytes, which German writes "1,5".
      final modified = await tester.runAsync(() async {
        final file = File(await pathOf('gym_notes'));
        await file.writeAsBytes(List.filled(1536, 0));
        return (await file.stat()).modified;
      });
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump(locale: const Locale('de'));

      expect(robot.statValue(de.size), de.databaseSizeKilobytes('1,5'));
      expect(
        robot.statValue(de.lastModified),
        DateFormat.yMd('de').add_Hm().format(modified!),
      );
      // The empty database's row reads in bytes, in the same words.
      expect(robot.shows(de.databaseSizeBytes('0')), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a missing file reads Unknown, not a literal', (tester) async {
      await tester.runAsync(() async {
        await File(await pathOf('gym_notes')).delete();
      });
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump(locale: const Locale('de'));

      expect(robot.statValue(de.size), de.unknownValue);
      expect(robot.statValue(de.lastModified), de.unknownValue);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('ids', () {
    testWidgets('every control a flow taps carries its id', (tester) async {
      final robot = DatabaseSettingsRobot(tester);
      await robot.pump();

      for (final id in [
        SemanticsIds.databasesPage,
        SemanticsIds.databasesList,
        SemanticsIds.databaseRow('gym_notes'),
        SemanticsIds.databaseMore('gym_notes'),
        SemanticsIds.databaseRow('work'),
        SemanticsIds.databaseMore('work'),
        SemanticsIds.databaseCreate,
        SemanticsIds.databaseImport,
        SemanticsIds.databasePath,
      ]) {
        expect(robot.showsId(id), isTrue, reason: id);
      }

      await robot.openMenu('work');
      for (final id in [
        SemanticsIds.databaseMenuSwitch,
        SemanticsIds.databaseMenuRename,
        SemanticsIds.databaseMenuDelete,
      ]) {
        expect(robot.showsId(id), isTrue, reason: id);
      }
      await robot.dismissMenu();

      // The list builds lazily; the lower cards exist once scrolled to.
      await robot.scrollTo(l10n.deleteAllData);
      for (final id in [
        SemanticsIds.databaseShare,
        SemanticsIds.databaseOptimize,
        SemanticsIds.databaseDeleteAll,
      ]) {
        expect(robot.showsId(id), isTrue, reason: id);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
